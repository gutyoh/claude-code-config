#!/usr/bin/env bats
# mcp-proxy-search.bats — tests for bin/mcp-proxy-search
# Run: bats tests/mcp-proxy-search.bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/mcp-proxy-search"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    [ -x "$SCRIPT" ] || skip "mcp-proxy-search not executable"
    export TEST_TMPDIR; TEST_TMPDIR="$(mktemp -d)"
    export MCP_KEY_HEALTH_DIR="${TEST_TMPDIR}/state"
    export KEY_ROTATE_BACKEND=dotenv
    export KEY_ROTATE_DOTENV="${TEST_TMPDIR}/.env"
    unset TAVILY_API_KEY BRAVE_API_KEY
}

teardown() { rm -rf "${TEST_TMPDIR}"; }

# --- Mock curl: routes by URL pattern, status via env vars ---
create_curl_mock() {
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in https://*|http://*) url="$a" ;; esac; done

status="200"; body='{}'
if [[ "${url}" == *"api.tavily.com"* ]]; then
    status="${TAVILY_MOCK_STATUS:-200}"
    if [[ "${status}" == "200" ]]; then
        case "${url}" in
            */search)   body='{"query":"mock","results":[{"title":"Mock Tavily Search"}]}' ;;
            */extract)  body='{"results":[{"url":"https://example.com","raw_content":"extracted"}]}' ;;
            */crawl)    body='{"results":[{"url":"https://example.com/page","raw_content":"crawled"}]}' ;;
            */map)      body='{"urls":["https://example.com/a","https://example.com/b"]}' ;;
            */research) body='{"report":"Research findings on the topic."}' ;;
        esac
    else
        body='{"detail":"mock error"}'
    fi
elif [[ "${url}" == *"api.search.brave.com"* ]]; then
    status="${BRAVE_MOCK_STATUS:-200}"
    if [[ "${status}" == "200" ]]; then
        case "${url}" in
            */news/*)   body='{"results":[{"title":"Mock News"}]}' ;;
            */images/*) body='{"results":[{"title":"Mock Image"}]}' ;;
            */videos/*) body='{"results":[{"title":"Mock Video"}]}' ;;
            *)          body='{"web":{"results":[{"title":"Mock Brave Web"}]}}' ;;
        esac
    else
        body='{"detail":"mock error"}'
    fi
fi
printf '%s\n__HTTP_STATUS__%s' "${body}" "${status}"
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"
}

create_rotate_mock() {
    cat >"${TEST_TMPDIR}/mcp-key-rotate" <<'MOCK_EOF'
#!/usr/bin/env bash
service="${1:-}"; action="${2:-}"
if [[ "${action}" == "--recover-from-failure" ]]; then
    echo "Rotated ${service}: old -> new"
    echo "Active: ${ROTATE_MOCK_NEXT_KEY:-next-key-from-mock}"
    exit 0
fi
exit 1
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/mcp-key-rotate"
}

create_rotate_mock_fail() {
    cat >"${TEST_TMPDIR}/mcp-key-rotate" <<'MOCK_EOF'
#!/usr/bin/env bash
exit 1
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/mcp-key-rotate"
}

seed_dotenv_key() { echo "$1=$2" >>"${KEY_ROTATE_DOTENV}"; }

# Run the proxy with a single JSON-RPC line on stdin.
run_proxy() {
    local input="$1"
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
}

# Run with a multi-line input file.
run_proxy_file() {
    run bash -c "cat '$1' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
}

# ==========================================================================
# UNIT: Script basics
# ==========================================================================

@test "script is executable and passes syntax check" {
    [ -x "$SCRIPT" ] && bash -n "$SCRIPT"
}

@test "sourcing does NOT enter stdio loop" {
    run bash -c "source '$SCRIPT'; set +e; echo SOURCED"
    [ "$status" -eq 0 ]; [[ "$output" == *"SOURCED"* ]]
}

# ==========================================================================
# UNIT: read_active_key
# ==========================================================================

@test "read_active_key: reads from dotenv" {
    seed_dotenv_key "TAVILY_API_KEY" "dotenv-tavily"
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'; source '$SCRIPT'; set +e; read_active_key tavily"
    [ "$output" = "dotenv-tavily" ]
}

@test "read_active_key: falls back to env var" {
    : >"${KEY_ROTATE_DOTENV}"
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' BRAVE_API_KEY='env-brave'; source '$SCRIPT'; set +e; read_active_key brave"
    [ "$output" = "env-brave" ]
}

@test "read_active_key: returns empty when no source" {
    : >"${KEY_ROTATE_DOTENV}"
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'; source '$SCRIPT'; set +e; read_active_key tavily"
    [ -z "$output" ]
}

# ==========================================================================
# UNIT: recover_from_failure
# ==========================================================================

@test "recover_from_failure: parses Active line" {
    create_rotate_mock
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' ROTATE_MOCK_NEXT_KEY='new-key-42'; source '$SCRIPT'; set +e; recover_from_failure tavily old"
    [ "$output" = "new-key-42" ]
}

@test "recover_from_failure: returns non-zero on failure" {
    create_rotate_mock_fail
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'; source '$SCRIPT'; set +e; recover_from_failure tavily x"
    [ "$status" -ne 0 ]
}

# ==========================================================================
# UNIT: HTTP helpers
# ==========================================================================

@test "http_tavily_post: 200 returns body with status marker" {
    create_curl_mock
    run bash -c "export CURL_CMD='${TEST_TMPDIR}/curl' TAVILY_MOCK_STATUS=200; source '$SCRIPT'; set +e; raw=\$(http_tavily_post k search '{\"query\":\"q\"}') && split_curl_raw \"\${raw}\" && echo S=\${CURL_STATUS} B=\${CURL_BODY}"
    [[ "$output" == *"S=200"* ]]; [[ "$output" == *"Mock Tavily Search"* ]]
}

@test "http_tavily_post: 432 status propagates" {
    create_curl_mock
    run bash -c "export CURL_CMD='${TEST_TMPDIR}/curl' TAVILY_MOCK_STATUS=432; source '$SCRIPT'; set +e; raw=\$(http_tavily_post k search '{\"query\":\"q\"}') && split_curl_raw \"\${raw}\" && echo S=\${CURL_STATUS}"
    [[ "$output" == *"S=432"* ]]
}

@test "http_brave_get: 200 returns body with status marker" {
    create_curl_mock
    run bash -c "export CURL_CMD='${TEST_TMPDIR}/curl' BRAVE_MOCK_STATUS=200; source '$SCRIPT'; set +e; raw=\$(http_brave_get k web/search --data-urlencode q=test) && split_curl_raw \"\${raw}\" && echo S=\${CURL_STATUS} B=\${CURL_BODY}"
    [[ "$output" == *"S=200"* ]]; [[ "$output" == *"Mock Brave Web"* ]]
}

@test "http_brave_get: 429 status propagates" {
    create_curl_mock
    run bash -c "export CURL_CMD='${TEST_TMPDIR}/curl' BRAVE_MOCK_STATUS=429; source '$SCRIPT'; set +e; raw=\$(http_brave_get k web/search --data-urlencode q=test) && split_curl_raw \"\${raw}\" && echo S=\${CURL_STATUS}"
    [[ "$output" == *"S=429"* ]]
}

# ==========================================================================
# UNIT: call_with_rotation
# ==========================================================================

@test "call_with_rotation: ok path (200)" {
    create_curl_mock; create_rotate_mock; seed_dotenv_key "TAVILY_API_KEY" "k"
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' CURL_CMD='${TEST_TMPDIR}/curl' MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' TAVILY_MOCK_STATUS=200; source '$SCRIPT'; set +e; call_with_rotation tavily _tavily_search q 3 && echo S=\${CALL_STATUS} B=\${CALL_BODY}"
    [[ "$output" == *"S=ok"* ]]; [[ "$output" == *"Mock Tavily Search"* ]]
}

@test "call_with_rotation: no_key when empty" {
    : >"${KEY_ROTATE_DOTENV}"
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'; source '$SCRIPT'; set +e; call_with_rotation tavily _tavily_search q 3 || true && echo S=\${CALL_STATUS}"
    [[ "$output" == *"S=no_key"* ]]
}

@test "call_with_rotation: 432 then rotate then ok" {
    create_rotate_mock; seed_dotenv_key "TAVILY_API_KEY" "k"
    local toggle="${TEST_TMPDIR}/toggle"; echo 432 >"${toggle}"
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
s="$(cat "${CURL_TOGGLE_FILE}")"; echo 200 >"${CURL_TOGGLE_FILE}"
url=""; for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
[[ "${url}" == *"api.tavily.com"* ]] && {
    [[ "${s}" == "200" ]] && printf '%s\n__HTTP_STATUS__200' '{"results":[{"title":"Recovered"}]}' || printf '%s\n__HTTP_STATUS__%s' '{"detail":"quota"}' "${s}"
}
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' CURL_CMD='${TEST_TMPDIR}/curl' CURL_TOGGLE_FILE='${toggle}' MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'; source '$SCRIPT'; set +e; call_with_rotation tavily _tavily_search q 3 && echo S=\${CALL_STATUS} B=\${CALL_BODY}"
    [[ "$output" == *"S=ok"* ]]; [[ "$output" == *"Recovered"* ]]
}

@test "call_with_rotation: 500 => http_error, no retry" {
    create_curl_mock; create_rotate_mock; seed_dotenv_key "TAVILY_API_KEY" "k"
    run bash -c "export PATH='${TEST_TMPDIR}:/usr/bin:/bin' CURL_CMD='${TEST_TMPDIR}/curl' MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' TAVILY_MOCK_STATUS=500; source '$SCRIPT'; set +e; call_with_rotation tavily _tavily_search q 3 || true && echo S=\${CALL_STATUS}"
    [[ "$output" == *"S=http_error"* ]]
}

# ==========================================================================
# UNIT: no-key setup instructions
# ==========================================================================

@test "no_key_message: includes setup steps for tavily" {
    run bash -c "source '$SCRIPT'; set +e; no_key_message tavily tavily_search"
    [[ "$output" == *"TAVILY_API_KEY"* ]]
    [[ "$output" == *"tavily.com"* ]]
    [[ "$output" == *"/web-search"* ]]
}

@test "no_key_message: includes setup steps for brave" {
    run bash -c "source '$SCRIPT'; set +e; no_key_message brave brave_web_search"
    [[ "$output" == *"BRAVE_API_KEY"* ]]
    [[ "$output" == *"brave.com"* ]]
}

# ==========================================================================
# UNIT: JSON-RPC emitters
# ==========================================================================

@test "emit_tool_success: valid MCP content with isError=false" {
    run bash -c "source '$SCRIPT'; set +e; emit_tool_success 1 hello"
    echo "$output" | jq -e '.result.isError == false and .result.content[0].text == "hello"'
}

@test "emit_tool_error: valid MCP content with isError=true" {
    run bash -c "source '$SCRIPT'; set +e; emit_tool_error 1 boom"
    echo "$output" | jq -e '.result.isError == true and .result.content[0].text == "boom"'
}

@test "emit_rpc_error: JSON-RPC error envelope" {
    run bash -c "source '$SCRIPT'; set +e; emit_rpc_error 1 -32601 'not found'"
    echo "$output" | jq -e '.error.code == -32601'
}

@test "handle_initialize: returns protocolVersion + serverInfo" {
    run bash -c "source '$SCRIPT'; set +e; handle_initialize 1"
    echo "$output" | jq -e '.result.protocolVersion == "2024-11-05" and .result.serverInfo.name == "mcp-proxy-search"'
}

# ==========================================================================
# UNIT: handle_tools_list (all 10 tools)
# ==========================================================================

@test "handle_tools_list: returns exactly 10 tools" {
    run bash -c "source '$SCRIPT'; set +e; handle_tools_list 1"
    echo "$output" | jq -e '.result.tools | length == 10'
}

@test "handle_tools_list: all tool names present" {
    run bash -c "source '$SCRIPT'; set +e; handle_tools_list 1"
    for tool in tavily_search tavily_extract tavily_crawl tavily_map tavily_research brave_web_search brave_local_search brave_news_search brave_image_search brave_video_search; do
        echo "$output" | jq -e --arg n "$tool" '.result.tools[] | select(.name == $n)'
    done
}

@test "handle_tools_list: every tool has required field in inputSchema" {
    run bash -c "source '$SCRIPT'; set +e; handle_tools_list 1"
    echo "$output" | jq -e '.result.tools[] | .inputSchema.required | length > 0'
}

# ==========================================================================
# STDIO INTEGRATION: protocol basics
# ==========================================================================

@test "stdio: initialize returns correct version" {
    run_proxy '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    echo "$output" | jq -e '.result.protocolVersion == "2024-11-05"'
}

@test "stdio: notifications/initialized => no response" {
    run_proxy '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    [ -z "$output" ]
}

@test "stdio: unknown method => -32601" {
    run_proxy '{"jsonrpc":"2.0","id":1,"method":"bogus"}'
    echo "$output" | jq -e '.error.code == -32601'
}

@test "stdio: ping => empty result" {
    run_proxy '{"jsonrpc":"2.0","id":1,"method":"ping"}'
    echo "$output" | jq -e '.result == {}'
}

@test "stdio: malformed JSON => silent ignore" {
    run_proxy 'not json'; [ -z "$output" ]
}

@test "stdio: empty line => silent ignore" {
    run_proxy ''; [ -z "$output" ]
}

# ==========================================================================
# STDIO INTEGRATION: tool calls (happy path, all 10 tools)
# ==========================================================================

_test_tool_success() {
    local tool="$1" args_json="$2" expect_in_body="$3" key_var="$4" key_val="$5"
    create_curl_mock; create_rotate_mock; seed_dotenv_key "${key_var}" "${key_val}"
    local input
    input="$(jq -nc --arg t "${tool}" --argjson a "${args_json}" '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$t,arguments:$a}}')"
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=200 BRAVE_MOCK_STATUS=200 \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == false'
    [[ "$output" == *"${expect_in_body}"* ]]
}

@test "stdio: tavily_search returns results" {
    _test_tool_success tavily_search '{"query":"q"}' "Mock Tavily Search" TAVILY_API_KEY k
}

@test "stdio: tavily_extract returns results" {
    _test_tool_success tavily_extract '{"urls":["https://example.com"]}' "extracted" TAVILY_API_KEY k
}

@test "stdio: tavily_crawl returns results" {
    _test_tool_success tavily_crawl '{"url":"https://example.com"}' "crawled" TAVILY_API_KEY k
}

@test "stdio: tavily_map returns results" {
    _test_tool_success tavily_map '{"url":"https://example.com"}' "urls" TAVILY_API_KEY k
}

@test "stdio: tavily_research returns results" {
    _test_tool_success tavily_research '{"input":"topic"}' "Research findings" TAVILY_API_KEY k
}

@test "stdio: brave_web_search returns results" {
    _test_tool_success brave_web_search '{"query":"q"}' "Mock Brave Web" BRAVE_API_KEY k
}

@test "stdio: brave_local_search returns results" {
    _test_tool_success brave_local_search '{"query":"pizza near me"}' "Mock Brave Web" BRAVE_API_KEY k
}

@test "stdio: brave_news_search returns results" {
    _test_tool_success brave_news_search '{"query":"breaking"}' "Mock News" BRAVE_API_KEY k
}

@test "stdio: brave_image_search returns results" {
    _test_tool_success brave_image_search '{"query":"cats"}' "Mock Image" BRAVE_API_KEY k
}

@test "stdio: brave_video_search returns results" {
    _test_tool_success brave_video_search '{"query":"tutorial"}' "Mock Video" BRAVE_API_KEY k
}

# ==========================================================================
# STDIO INTEGRATION: error paths
# ==========================================================================

@test "stdio: unknown tool => isError=true" {
    run_proxy '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"nope","arguments":{}}}'
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"unknown tool"* ]]
}

@test "stdio: missing required query => isError=true" {
    run_proxy '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tavily_search","arguments":{}}}'
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"missing required"* ]]
}

@test "stdio: missing required urls for extract => isError=true" {
    run_proxy '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tavily_extract","arguments":{}}}'
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"missing required"* ]]
}

@test "stdio: no_key shows setup instructions with signup URL" {
    : >"${KEY_ROTATE_DOTENV}"
    create_curl_mock; create_rotate_mock
    local input='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | env -u TAVILY_API_KEY \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"TAVILY_API_KEY"* ]]
    [[ "$output" == *"tavily.com"* ]]
    [[ "$output" == *"/web-search"* ]]
}

@test "stdio: 432 + rotation => transparent recovery" {
    create_rotate_mock; seed_dotenv_key "TAVILY_API_KEY" "k"
    local toggle="${TEST_TMPDIR}/toggle"; echo 432 >"${toggle}"
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
s="$(cat "${CURL_TOGGLE_FILE}")"; echo 200 >"${CURL_TOGGLE_FILE}"
url=""; for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
[[ "${url}" == *"api.tavily.com"* ]] && {
    [[ "${s}" == "200" ]] && printf '%s\n__HTTP_STATUS__200' '{"results":[{"title":"Recovered"}]}' || printf '%s\n__HTTP_STATUS__%s' '{"detail":"q"}' "${s}"
}
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"
    local input='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' CURL_TOGGLE_FILE='${toggle}' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
    echo "$output" | jq -e '.result.isError == false'
    [[ "$output" == *"Recovered"* ]]
}

@test "stdio: 432 + rotation failure => quota_exhausted" {
    create_curl_mock; create_rotate_mock_fail; seed_dotenv_key "TAVILY_API_KEY" "k"
    local input='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=432 \
        bash '$SCRIPT'"
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"quota_exhausted"* ]]
}

# ==========================================================================
# STDIO INTEGRATION: full session
# ==========================================================================

@test "stdio: full handshake + two tool calls" {
    create_curl_mock; create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "k"; seed_dotenv_key "BRAVE_API_KEY" "k"
    local f="${TEST_TMPDIR}/session.jsonl"
    cat >"${f}" <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"a"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"brave_web_search","arguments":{"query":"b"}}}
EOF
    run bash -c "cat '${f}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=200 BRAVE_MOCK_STATUS=200 \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    local lc; lc="$(printf '%s\n' "$output" | grep -c '^{')"
    [ "${lc}" -eq 3 ]
    echo "$output" | sed -n '2p' | jq -e '.result.isError == false'
    echo "$output" | sed -n '3p' | jq -e '.result.isError == false'
}

# ==========================================================================
# STDOUT CLEANLINESS
# ==========================================================================

@test "stdout: every line is valid JSON-RPC 2.0" {
    create_curl_mock; create_rotate_mock; seed_dotenv_key "TAVILY_API_KEY" "k"
    local f="${TEST_TMPDIR}/session.jsonl"
    cat >"${f}" <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}
{"jsonrpc":"2.0","id":4,"method":"ping"}
{"jsonrpc":"2.0","id":5,"method":"bogus"}
EOF
    run bash -c "cat '${f}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=200 \
        bash '$SCRIPT'"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq -e '.jsonrpc == "2.0"'
    done <<<"$output"
}

@test "stdout: debug logs go to stderr only" {
    create_curl_mock; create_rotate_mock; seed_dotenv_key "TAVILY_API_KEY" "k"
    local so="${TEST_TMPDIR}/stdout" se="${TEST_TMPDIR}/stderr"
    bash -c "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}' | \
        PATH='${TEST_TMPDIR}:${PATH}' MCP_PROXY_DEBUG=1 \
        CURL_CMD='${TEST_TMPDIR}/curl' KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'" >"${so}" 2>"${se}"
    jq -e '.jsonrpc == "2.0"' <"${so}"
    grep -q "mcp-proxy-search" "${se}"
}

@test "stdout: rotation chatter never leaks" {
    create_rotate_mock; seed_dotenv_key "TAVILY_API_KEY" "k"
    local toggle="${TEST_TMPDIR}/toggle"; echo 432 >"${toggle}"
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
s="$(cat "${CURL_TOGGLE_FILE}")"; echo 200 >"${CURL_TOGGLE_FILE}"
url=""; for a in "$@"; do case "$a" in https://*) url="$a" ;; esac; done
[[ "${url}" == *"api.tavily.com"* ]] && {
    [[ "${s}" == "200" ]] && printf '%s\n__HTTP_STATUS__200' '{"results":[{"title":"OK"}]}' || printf '%s\n__HTTP_STATUS__%s' '{"d":"q"}' "${s}"
}
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"
    local input='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' CURL_CMD='${TEST_TMPDIR}/curl' CURL_TOGGLE_FILE='${toggle}' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
    local lc; lc="$(printf '%s\n' "$output" | grep -c '^{')"
    [ "${lc}" -eq 1 ]
    [[ "$output" != *"Rotated "* ]]
}

# ==========================================================================
# FIXTURES
# ==========================================================================

@test "script at expected path" { [ -x "${REPO_ROOT}/bin/mcp-proxy-search" ]; }
@test "mcp-key-rotate co-located" { [ -x "${REPO_ROOT}/bin/mcp-key-rotate" ]; }
