#!/usr/bin/env bats
# mcp-proxy-search.bats
# Path: tests/mcp-proxy-search.bats
#
# Unit + integration tests for bin/mcp-proxy-search.
#
# Unit tests source the script so they can call internal functions directly.
# Integration tests pipe JSON-RPC messages into the script's stdin and assert
# newline-delimited responses on stdout.
#
# Run: bats tests/mcp-proxy-search.bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/mcp-proxy-search"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

# --- Setup / teardown ---
setup() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    [ -x "$SCRIPT" ] || skip "mcp-proxy-search not executable"

    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"

    export MCP_KEY_HEALTH_DIR="${TEST_TMPDIR}/state"
    export KEY_ROTATE_BACKEND=dotenv
    export KEY_ROTATE_DOTENV="${TEST_TMPDIR}/.env"
    unset TAVILY_API_KEY
    unset BRAVE_API_KEY
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# --- Mock factories ---

# A mock curl that emits canned JSON based on env vars. Drops HTTP status via
# the `-w '%{http_code}'` suffix the script relies on.
#   TAVILY_MOCK_STATUS=200|429|432|500  (default 200)
#   BRAVE_MOCK_STATUS=200|429|500        (default 200)
#   MOCK_CURL_LOG=/path/to/log           appends each invocation's argv
create_curl_mock() {
    local mock="${TEST_TMPDIR}/curl"
    cat >"${mock}" <<'MOCK_EOF'
#!/usr/bin/env bash
log="${MOCK_CURL_LOG:-}"
[[ -n "${log}" ]] && printf '%s\n' "$*" >>"${log}"

url=""
for a in "$@"; do
    case "$a" in https://*|http://*) url="$a" ;; esac
done

status_code="200"
body="{}"
if [[ "${url}" == *"api.tavily.com/search"* ]]; then
    status_code="${TAVILY_MOCK_STATUS:-200}"
    if [[ "${status_code}" == "200" ]]; then
        body='{"query":"mock","results":[{"title":"Mocked Tavily","url":"https://example.com/t","content":"mock content"}]}'
    else
        body='{"detail":"mock error"}'
    fi
elif [[ "${url}" == *"api.search.brave.com"* ]]; then
    status_code="${BRAVE_MOCK_STATUS:-200}"
    if [[ "${status_code}" == "200" ]]; then
        body='{"query":{"original":"mock"},"web":{"results":[{"title":"Mocked Brave","url":"https://example.com/b","description":"brave desc"}]}}'
    else
        body='{"detail":"mock error"}'
    fi
fi

# Mimic curl -w '\n__HTTP_STATUS__%{http_code}' via the -w flag the script uses.
# We still need to write status code because the script relies on -w expansion.
printf '%s\n__HTTP_STATUS__%s' "${body}" "${status_code}"
MOCK_EOF
    chmod +x "${mock}"
}

# Mock mcp-key-rotate. Recognizes the --recover-from-failure subcommand and
# emits the "Active: <key>" contract the proxy parses. Rotation target is
# controlled via ROTATE_MOCK_NEXT_KEY (default: next-key-from-mock).
create_rotate_mock() {
    local mock="${TEST_TMPDIR}/mcp-key-rotate"
    cat >"${mock}" <<'MOCK_EOF'
#!/usr/bin/env bash
set -euo pipefail
service="${1:-}"
action="${2:-}"
if [[ "${action}" == "--recover-from-failure" ]]; then
    next="${ROTATE_MOCK_NEXT_KEY:-next-key-from-mock}"
    echo "Rotated ${service}: old-key -> new-key"
    echo "Now active: key [2] of 2 (backend: test-mock)"
    echo "Active: ${next}"
    exit 0
fi
exit 1
MOCK_EOF
    chmod +x "${mock}"
}

create_rotate_mock_fail() {
    local mock="${TEST_TMPDIR}/mcp-key-rotate"
    cat >"${mock}" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "rotation failed" >&2
exit 1
MOCK_EOF
    chmod +x "${mock}"
}

# Seed a fixture .env so read_active_key's dotenv branch returns something.
seed_dotenv_key() {
    local name="$1" value="$2"
    echo "${name}=${value}" >>"${KEY_ROTATE_DOTENV}"
}

# Run the script with the mock directory prepended to PATH so curl and
# mcp-key-rotate resolve to our fakes.
run_proxy_with_input() {
    local input="$1"
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        KEY_ROTATE_BACKEND=dotenv \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
}

run_proxy_with_multiline_input() {
    local input_file="$1"
    run bash -c "cat '${input_file}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        KEY_ROTATE_BACKEND=dotenv \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
}

# ==========================================================================
# UNIT TESTS (source-based)
# ==========================================================================
# These source the script to gain access to its internal functions, then
# invoke them directly. The top-level `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`
# guard in the script prevents the stdio loop from running during sourcing.

source_script() {
    # shellcheck disable=SC1090
    source "$SCRIPT"
}

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "script passes bash syntax check" {
    bash -n "$SCRIPT"
}

@test "sourcing the script does NOT enter the stdio loop" {
    run bash -c "source '$SCRIPT' && echo SOURCED"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SOURCED"* ]]
}

# --- read_active_key ---

@test "read_active_key: reads from dotenv when Doppler is unavailable" {
    seed_dotenv_key "TAVILY_API_KEY" "dotenv-tavily-key"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        source '$SCRIPT'
        read_active_key tavily"
    [ "$status" -eq 0 ]
    [ "$output" = "dotenv-tavily-key" ]
}

@test "read_active_key: falls back to env var when no dotenv entry" {
    : >"${KEY_ROTATE_DOTENV}"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        export BRAVE_API_KEY='env-brave-key'
        source '$SCRIPT'
        read_active_key brave"
    [ "$status" -eq 0 ]
    [ "$output" = "env-brave-key" ]
}

@test "read_active_key: returns empty string when no source has the key" {
    : >"${KEY_ROTATE_DOTENV}"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        unset TAVILY_API_KEY
        source '$SCRIPT'
        read_active_key tavily"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "read_active_key: case-insensitive service name maps to uppercase env var" {
    seed_dotenv_key "BRAVE_API_KEY" "fixture-brave"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        source '$SCRIPT'
        read_active_key brave"
    [ "$status" -eq 0 ]
    [ "$output" = "fixture-brave" ]
}

# --- recover_from_failure ---

@test "recover_from_failure: parses 'Active:' line from mcp-key-rotate output" {
    create_rotate_mock
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'
        export ROTATE_MOCK_NEXT_KEY='the-new-key-42'
        source '$SCRIPT'
        recover_from_failure tavily old-failed-key"
    [ "$status" -eq 0 ]
    [ "$output" = "the-new-key-42" ]
}

@test "recover_from_failure: returns non-zero when mcp-key-rotate fails" {
    create_rotate_mock_fail
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'
        source '$SCRIPT'
        recover_from_failure tavily dead-key"
    [ "$status" -ne 0 ]
}

# --- Vendor HTTP wrappers ---

@test "http_tavily_search: raw output parses to status=200 on mock success" {
    create_curl_mock
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export TAVILY_MOCK_STATUS=200
        source '$SCRIPT'
        raw=\$(http_tavily_search fake-key 'q' 3)
        split_curl_raw \"\${raw}\"
        echo \"STATUS=\${CURL_STATUS}\"
        echo \"\${CURL_BODY}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=200"* ]]
    [[ "$output" == *"Mocked Tavily"* ]]
}

@test "http_tavily_search: raw output parses to status=432 on quota error" {
    create_curl_mock
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export TAVILY_MOCK_STATUS=432
        source '$SCRIPT'
        raw=\$(http_tavily_search fake-key 'q' 3)
        split_curl_raw \"\${raw}\"
        echo \"STATUS=\${CURL_STATUS}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=432"* ]]
}

@test "http_brave_search: raw output parses to status=200 on mock success" {
    create_curl_mock
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export BRAVE_MOCK_STATUS=200
        source '$SCRIPT'
        raw=\$(http_brave_search fake-key 'q' 5)
        split_curl_raw \"\${raw}\"
        echo \"STATUS=\${CURL_STATUS}\"
        echo \"\${CURL_BODY}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=200"* ]]
    [[ "$output" == *"Mocked Brave"* ]]
}

@test "http_brave_search: raw output parses to status=429 on rate limit" {
    create_curl_mock
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export BRAVE_MOCK_STATUS=429
        source '$SCRIPT'
        raw=\$(http_brave_search fake-key 'q' 5)
        split_curl_raw \"\${raw}\"
        echo \"STATUS=\${CURL_STATUS}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=429"* ]]
}

@test "split_curl_raw: parses body and status from curl marker format" {
    run bash -c "
        source '$SCRIPT'
        raw=\$(printf '%s\n__HTTP_STATUS__%s' '{\"ok\":true}' '200')
        split_curl_raw \"\${raw}\"
        echo \"S=\${CURL_STATUS}\"
        echo \"B=\${CURL_BODY}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"S=200"* ]]
    [[ "$output" == *'B={"ok":true}'* ]]
}

# --- call_with_rotation ---

@test "call_with_rotation: ok path on HTTP 200, no rotation" {
    create_curl_mock
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "first-key"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        export TAVILY_MOCK_STATUS=200
        source '$SCRIPT'
        call_with_rotation tavily 'q' 3
        echo \"STATUS=\${CALL_STATUS}\"
        echo \"\${CALL_BODY}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"Mocked Tavily"* ]]
}

@test "call_with_rotation: no_key when key source is empty" {
    : >"${KEY_ROTATE_DOTENV}"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        unset TAVILY_API_KEY
        source '$SCRIPT'
        call_with_rotation tavily 'q' 3 || true
        echo \"STATUS=\${CALL_STATUS}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=no_key"* ]]
}

@test "call_with_rotation: 432 then rotate then success (transparent recovery)" {
    # First call returns 432; after recovery the mock curl is replaced with
    # one that returns 200. This proves the rotate-once-and-retry path.
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "dying-key"
    local toggle="${TEST_TMPDIR}/curl-toggle"
    echo 432 >"${toggle}"
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
toggle_file="${CURL_TOGGLE_FILE}"
status="$(cat "${toggle_file}" 2>/dev/null || echo 200)"
# Flip to 200 after first call
echo 200 >"${toggle_file}"
url=""
for a in "$@"; do
    case "$a" in https://*|http://*) url="$a" ;; esac
done
if [[ "${url}" == *"api.tavily.com/search"* ]]; then
    if [[ "${status}" == "200" ]]; then
        printf '%s\n__HTTP_STATUS__%s' '{"query":"mock","results":[{"title":"After Rotation","url":"https://example.com/r","content":"recovered"}]}' "${status}"
    else
        printf '%s\n__HTTP_STATUS__%s' '{"detail":"quota"}' "${status}"
    fi
fi
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"

    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export CURL_TOGGLE_FILE='${toggle}'
        export MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        source '$SCRIPT'
        call_with_rotation tavily 'q' 3
        echo \"STATUS=\${CALL_STATUS}\"
        echo \"\${CALL_BODY}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"After Rotation"* ]]
}

@test "call_with_rotation: 432 then rotate fails => quota_exhausted" {
    create_curl_mock
    create_rotate_mock_fail
    seed_dotenv_key "TAVILY_API_KEY" "dying-key"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        export TAVILY_MOCK_STATUS=432
        source '$SCRIPT'
        call_with_rotation tavily 'q' 3 || true
        echo \"STATUS=\${CALL_STATUS}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=quota_exhausted"* ]]
}

@test "call_with_rotation: 429 on brave then rotate and succeed" {
    create_rotate_mock
    seed_dotenv_key "BRAVE_API_KEY" "dying-brave-key"
    local toggle="${TEST_TMPDIR}/curl-toggle"
    echo 429 >"${toggle}"
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
toggle_file="${CURL_TOGGLE_FILE}"
status="$(cat "${toggle_file}" 2>/dev/null || echo 200)"
echo 200 >"${toggle_file}"
url=""
for a in "$@"; do case "$a" in https://*|http://*) url="$a" ;; esac; done
if [[ "${url}" == *"api.search.brave.com"* ]]; then
    if [[ "${status}" == "200" ]]; then
        printf '%s\n__HTTP_STATUS__%s' '{"query":{"original":"mock"},"web":{"results":[{"title":"Brave Recovered","url":"https://example.com/b","description":"recovered"}]}}' "${status}"
    else
        printf '%s\n__HTTP_STATUS__%s' '{"detail":"rate"}' "${status}"
    fi
fi
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"

    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export CURL_TOGGLE_FILE='${toggle}'
        export MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        source '$SCRIPT'
        call_with_rotation brave 'q' 5
        echo \"STATUS=\${CALL_STATUS}\"
        echo \"\${CALL_BODY}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=ok"* ]]
    [[ "$output" == *"Brave Recovered"* ]]
}

@test "call_with_rotation: non-quota 500 error => http_error, no retry" {
    create_curl_mock
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "fixture-key"
    local log="${TEST_TMPDIR}/curl.log"
    : >"${log}"
    run bash -c "
        export PATH='${TEST_TMPDIR}:/usr/bin:/bin'
        export CURL_CMD='${TEST_TMPDIR}/curl'
        export MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate'
        export KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}'
        export TAVILY_MOCK_STATUS=500
        export MOCK_CURL_LOG='${log}'
        source '$SCRIPT'
        call_with_rotation tavily 'q' 3 || true
        echo \"STATUS=\${CALL_STATUS}\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=http_error"* ]]
    local call_count
    call_count="$(wc -l <"${log}")"
    [ "${call_count}" -eq 1 ]
}

# --- JSON-RPC response emitters ---

@test "emit_result: produces valid JSON-RPC 2.0 envelope" {
    run bash -c "source '$SCRIPT' && emit_result 1 '{\"foo\":\"bar\"}'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.jsonrpc == "2.0" and .id == 1 and .result.foo == "bar"'
}

@test "emit_rpc_error: produces JSON-RPC error envelope with code and message" {
    run bash -c "source '$SCRIPT' && emit_rpc_error 42 -32601 'method not found: foo'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.jsonrpc == "2.0" and .id == 42 and .error.code == -32601 and .error.message == "method not found: foo"'
}

@test "emit_tool_success: produces MCP tool result with isError=false" {
    run bash -c "source '$SCRIPT' && emit_tool_success 7 'hello world'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == false and .result.content[0].text == "hello world" and .result.content[0].type == "text"'
}

@test "emit_tool_error: produces MCP tool result with isError=true" {
    run bash -c "source '$SCRIPT' && emit_tool_error 9 'boom'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == true and .result.content[0].text == "boom"'
}

@test "handle_initialize: returns protocolVersion + serverInfo" {
    run bash -c "source '$SCRIPT' && handle_initialize 1"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.protocolVersion == "2024-11-05"'
    echo "$output" | jq -e '.result.serverInfo.name == "mcp-proxy-search"'
    echo "$output" | jq -e '.result.capabilities.tools'
}

@test "handle_tools_list: returns both tools with required input schemas" {
    run bash -c "source '$SCRIPT' && handle_tools_list 5"
    [ "$status" -eq 0 ]
    local tool_names
    tool_names="$(echo "$output" | jq -r '.result.tools[].name' | sort | tr '\n' ' ')"
    [[ "$tool_names" == *"brave_web_search"* ]]
    [[ "$tool_names" == *"tavily_search"* ]]
    echo "$output" | jq -e '.result.tools[] | select(.name=="tavily_search") | .inputSchema.required[] | select(. == "query")'
    echo "$output" | jq -e '.result.tools[] | select(.name=="brave_web_search") | .inputSchema.required[] | select(. == "query")'
}

# ==========================================================================
# INTEGRATION TESTS (JSON-RPC over stdio)
# ==========================================================================

@test "stdio: initialize handshake returns correct protocolVersion" {
    local input='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
    run_proxy_with_input "${input}"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.id == 1 and .result.protocolVersion == "2024-11-05"'
}

@test "stdio: notifications/initialized produces NO response" {
    local input='{"jsonrpc":"2.0","method":"notifications/initialized"}'
    run_proxy_with_input "${input}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "stdio: tools/list returns both tools" {
    local input='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    run_proxy_with_input "${input}"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.tools | length == 2'
}

@test "stdio: unknown method returns JSON-RPC error -32601" {
    local input='{"jsonrpc":"2.0","id":99,"method":"completely/madeup"}'
    run_proxy_with_input "${input}"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.error.code == -32601'
    [[ "$output" == *"completely/madeup"* ]]
}

@test "stdio: ping returns empty result" {
    local input='{"jsonrpc":"2.0","id":3,"method":"ping"}'
    run_proxy_with_input "${input}"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result == {}'
}

@test "stdio: tools/call tavily_search (mock 200) returns real content" {
    create_curl_mock
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "fixture-tavily"

    local input='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"cats","max_results":3}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=200 \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == false'
    echo "$output" | jq -e '.result.content[0].text | contains("Mocked Tavily")'
}

@test "stdio: tools/call brave_web_search (mock 200) returns real content" {
    create_curl_mock
    create_rotate_mock
    seed_dotenv_key "BRAVE_API_KEY" "fixture-brave"

    local input='{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"brave_web_search","arguments":{"query":"dogs","count":5}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        BRAVE_MOCK_STATUS=200 \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == false'
    echo "$output" | jq -e '.result.content[0].text | contains("Mocked Brave")'
}

@test "stdio: tools/call tavily_search with 432+rotation returns recovered content" {
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "dying-tavily"

    # Toggle mock: 432 on first call, 200 after.
    local toggle="${TEST_TMPDIR}/curl-toggle"
    echo 432 >"${toggle}"
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
toggle_file="${CURL_TOGGLE_FILE}"
status="$(cat "${toggle_file}" 2>/dev/null || echo 200)"
echo 200 >"${toggle_file}"
url=""
for a in "$@"; do case "$a" in https://*|http://*) url="$a" ;; esac; done
if [[ "${url}" == *"api.tavily.com/search"* ]]; then
    if [[ "${status}" == "200" ]]; then
        printf '%s\n__HTTP_STATUS__%s' '{"query":"recovered","results":[{"title":"Recovered Tavily","url":"https://example.com/r","content":"post-rotation"}]}' "${status}"
    else
        printf '%s\n__HTTP_STATUS__%s' '{"detail":"quota"}' "${status}"
    fi
fi
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"

    local input='{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        CURL_TOGGLE_FILE='${toggle}' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == false'
    echo "$output" | jq -e '.result.content[0].text | contains("Recovered Tavily")'
}

@test "stdio: tools/call with 432+rotation failure returns isError=true" {
    create_curl_mock
    create_rotate_mock_fail
    seed_dotenv_key "TAVILY_API_KEY" "dead-tavily"

    local input='{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=432 \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"quota_exhausted"* ]]
}

@test "stdio: tools/call unknown tool returns isError=true" {
    local input='{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}'
    run_proxy_with_input "${input}"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"unknown tool"* ]]
}

@test "stdio: tools/call missing required query argument returns isError=true" {
    local input='{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"tavily_search","arguments":{}}}'
    run_proxy_with_input "${input}"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"missing required argument"* ]]
}

@test "stdio: tools/call with no_key (empty .env and no env var) returns isError" {
    : >"${KEY_ROTATE_DOTENV}"
    create_curl_mock
    create_rotate_mock

    local input='{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | \
        env -u TAVILY_API_KEY \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.isError == true'
    [[ "$output" == *"no_key"* ]]
}

@test "stdio: malformed JSON line is silently ignored" {
    run_proxy_with_input 'not json at all'
    [ "$status" -eq 0 ]
    # stdout must be empty (no noise on bad input)
    [ -z "$output" ]
}

@test "stdio: empty line is silently ignored" {
    run_proxy_with_input ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "stdio: full handshake sequence (init + initialized + tools/list)" {
    local input_file="${TEST_TMPDIR}/handshake.jsonl"
    cat >"${input_file}" <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"bats","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
EOF
    run_proxy_with_multiline_input "${input_file}"
    [ "$status" -eq 0 ]

    # Exactly 2 output lines (initialize result + tools/list result; notification has no response)
    local line_count
    line_count="$(printf '%s\n' "$output" | grep -c '^{')"
    [ "${line_count}" -eq 2 ]

    local first_line second_line
    first_line="$(printf '%s\n' "$output" | sed -n '1p')"
    second_line="$(printf '%s\n' "$output" | sed -n '2p')"
    echo "${first_line}" | jq -e '.id == 1 and .result.protocolVersion == "2024-11-05"'
    echo "${second_line}" | jq -e '.id == 2 and (.result.tools | length == 2)'
}

@test "stdio: multiple tools/call requests in one session, both succeed" {
    create_curl_mock
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "fixture-tavily"
    seed_dotenv_key "BRAVE_API_KEY" "fixture-brave"

    local input_file="${TEST_TMPDIR}/session.jsonl"
    cat >"${input_file}" <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"alpha"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"brave_web_search","arguments":{"query":"beta"}}}
EOF

    run bash -c "cat '${input_file}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=200 \
        BRAVE_MOCK_STATUS=200 \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]

    # Three responses: init, tavily, brave (initialized is a notification)
    local line_count
    line_count="$(printf '%s\n' "$output" | grep -c '^{')"
    [ "${line_count}" -eq 3 ]

    echo "$output" | sed -n '2p' | jq -e '.result.isError == false and (.result.content[0].text | contains("Mocked Tavily"))'
    echo "$output" | sed -n '3p' | jq -e '.result.isError == false and (.result.content[0].text | contains("Mocked Brave"))'
}

# ==========================================================================
# STDOUT CLEANLINESS (critical: MCP clients parse stdout line-by-line)
# ==========================================================================

@test "stdout cleanliness: every stdout line is parseable JSON-RPC 2.0" {
    create_curl_mock
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "fixture"

    local input_file="${TEST_TMPDIR}/session.jsonl"
    cat >"${input_file}" <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}
{"jsonrpc":"2.0","id":4,"method":"ping"}
{"jsonrpc":"2.0","id":5,"method":"doesnotexist"}
EOF

    run bash -c "cat '${input_file}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        TAVILY_MOCK_STATUS=200 \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]

    # Every non-empty line must parse as JSON with jsonrpc == "2.0"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "$line" | jq -e '.jsonrpc == "2.0"'
    done <<<"$output"
}

@test "stdout cleanliness: debug logs go to stderr, not stdout" {
    create_curl_mock
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "fixture"

    local input='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local stdout_file="${TEST_TMPDIR}/stdout.txt"
    local stderr_file="${TEST_TMPDIR}/stderr.txt"

    bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        MCP_PROXY_DEBUG=1 \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'" \
        >"${stdout_file}" 2>"${stderr_file}"

    # stdout must be ONLY the JSON-RPC response
    [ -s "${stdout_file}" ]
    jq -e '.jsonrpc == "2.0"' <"${stdout_file}"

    # stderr must contain the debug tag
    [ -s "${stderr_file}" ]
    grep -q "mcp-proxy-search" "${stderr_file}"
}

@test "stdout cleanliness: recover_from_failure output never leaks to stdout" {
    create_rotate_mock
    seed_dotenv_key "TAVILY_API_KEY" "dying-key"

    # 432 then 200 toggle
    local toggle="${TEST_TMPDIR}/curl-toggle"
    echo 432 >"${toggle}"
    cat >"${TEST_TMPDIR}/curl" <<'MOCK_EOF'
#!/usr/bin/env bash
status="$(cat "${CURL_TOGGLE_FILE}" 2>/dev/null || echo 200)"
echo 200 >"${CURL_TOGGLE_FILE}"
url=""
for a in "$@"; do case "$a" in https://*|http://*) url="$a" ;; esac; done
if [[ "${url}" == *"api.tavily.com/search"* ]]; then
    if [[ "${status}" == "200" ]]; then
        printf '%s\n__HTTP_STATUS__%s' '{"query":"ok","results":[{"title":"OK","url":"https://example.com/o","content":"ok"}]}' "${status}"
    else
        printf '%s\n__HTTP_STATUS__%s' '{"detail":"quota"}' "${status}"
    fi
fi
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/curl"

    local input='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"tavily_search","arguments":{"query":"q"}}}'
    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        CURL_CMD='${TEST_TMPDIR}/curl' \
        CURL_TOGGLE_FILE='${toggle}' \
        KEY_ROTATE_DOTENV='${KEY_ROTATE_DOTENV}' \
        MCP_KEY_ROTATE_BIN='${TEST_TMPDIR}/mcp-key-rotate' \
        bash '$SCRIPT'"
    [ "$status" -eq 0 ]

    # Exactly ONE stdout line — the final successful tool response.
    # The mcp-key-rotate mock prints "Rotated..." and "Now active..." to its
    # own stdout, but the proxy captures that via $() substitution and only
    # extracts "Active: <key>" — none of the rotation output should leak.
    local line_count
    line_count="$(printf '%s\n' "$output" | grep -c '^{')"
    [ "${line_count}" -eq 1 ]

    # Response must be a valid MCP tool success
    echo "$output" | jq -e '.result.isError == false'
    [[ "$output" != *"Rotated "* ]]
    [[ "$output" != *"Now active"* ]]
}

# ==========================================================================
# FIXTURES / REPO WIRING
# ==========================================================================

@test "script lives at the expected path for .mcp.json referencing" {
    [ -f "${REPO_ROOT}/bin/mcp-proxy-search" ]
    [ -x "${REPO_ROOT}/bin/mcp-proxy-search" ]
}

@test "script sits next to bin/mcp-key-rotate (so SCRIPT_DIR default resolves)" {
    [ -x "${REPO_ROOT}/bin/mcp-key-rotate" ]
    [ -x "${REPO_ROOT}/bin/mcp-proxy-search" ]
}
