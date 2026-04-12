#!/usr/bin/env bats
# mcp-setup.bats
# Path: tests/mcp-setup.bats
#
# Unit + integration tests for MCP server setup (lib/setup/mcp.sh).
# Verifies JSON generation via jq, backend detection, and the full
# configure flow using `claude mcp add-json`.
#
# Run: bats tests/mcp-setup.bats
#      make test

# shellcheck disable=SC2030,SC2031 # false positives — each @test is a subshell by design (shellcheck#3263)

MCP_SH="$BATS_TEST_DIRNAME/../lib/setup/mcp.sh"

# --- Setup / Teardown ---

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"

    # Set CLAUDE_JSON before sourcing mcp.sh (setup.sh declares it readonly,
    # so we source mcp.sh directly and provide the var ourselves).
    export CLAUDE_JSON="${TEST_TMPDIR}/claude.json"

    # Source only the MCP module — it is self-contained except for CLAUDE_JSON
    # and INSTALL_MCP_SERVERS (which we set per-test).
    # shellcheck source=../lib/setup/mcp.sh
    source "$MCP_SH"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# ==========================================================================
# UNIT TESTS: _build_mcp_json — JSON generation
# ==========================================================================

@test "_build_mcp_json: proxy-backed brave-search produces correct JSON (any backend)" {
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"
    echo "${result}" | python3 -m json.tool > /dev/null

    local cmd
    cmd="$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin)['command'])")"
    [ "$cmd" = "mcp-proxy-search" ]

    local type_val
    type_val="$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin)['type'])")"
    [ "$type_val" = "stdio" ]

    local args_json
    args_json="$(echo "${result}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['args']))")"
    [ "$args_json" = '["--service", "brave"]' ]
}

@test "_build_mcp_json: proxy-backed brave-search same JSON regardless of backend" {
    local d e
    d="$(_build_mcp_json "brave-search" "doppler")"
    e="$(_build_mcp_json "brave-search" "envfile")"
    [ "$d" = "$e" ]
}

@test "_build_mcp_json: proxy-backed tavily produces --service tavily" {
    local result
    result="$(_build_mcp_json "tavily" "doppler")"
    echo "${result}" | python3 -m json.tool > /dev/null

    local args_json
    args_json="$(echo "${result}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['args']))")"
    [ "$args_json" = '["--service", "tavily"]' ]
}

@test "_build_mcp_json: proxy JSON has command=mcp-proxy-search for tavily" {
    local result
    result="$(_build_mcp_json "tavily" "envfile")"
    local cmd
    cmd="$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin)['command'])")"
    [ "$cmd" = "mcp-proxy-search" ]
}

@test "_build_mcp_json: proxy JSON has no env field (proxy reads keys itself)" {
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"
    local has_env
    has_env="$(echo "${result}" | python3 -c "import sys,json; d=json.load(sys.stdin); print('env' in d)")"
    [ "$has_env" = "False" ]
}

@test "_build_mcp_json: proxy JSON has no doppler/npx args" {
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"
    [[ "$result" != *"doppler"* ]]
    [[ "$result" != *"npx"* ]]
}

@test "_build_mcp_json: envfile backend has type stdio" {
    local result
    result="$(_build_mcp_json "tavily" "envfile")"

    local type_val
    type_val="$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin)['type'])")"
    [ "$type_val" = "stdio" ]
}

# ==========================================================================
# UNIT TESTS: _build_mcp_json — custom Doppler project/config
# ==========================================================================

@test "_build_mcp_json: proxy-backed servers ignore Doppler project/config overrides" {
    # Proxy handles its own key resolution — the JSON should not contain
    # any Doppler project/config references regardless of env.
    local result
    result="$(MCP_DOPPLER_PROJECT=my-custom-proj MCP_DOPPLER_CONFIG=staging bash -c '
        source "'"${MCP_SH}"'"
        _build_mcp_json "brave-search" "doppler"
    ')"
    [[ "$result" != *"my-custom-proj"* ]]
    [[ "$result" != *"staging"* ]]
    [[ "$result" == *"mcp-proxy-search"* ]]
}

# ==========================================================================
# UNIT TESTS: _build_mcp_json — output is always valid JSON
# ==========================================================================

@test "_build_mcp_json: all server+backend combos produce valid JSON" {
    local key backend
    for key in brave-search tavily; do
        for backend in doppler envfile; do
            local result
            result="$(_build_mcp_json "${key}" "${backend}")"
            echo "${result}" | python3 -m json.tool > /dev/null 2>&1
        done
    done
}

@test "_build_mcp_json: JSON has exactly 3 top-level keys" {
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"

    local key_count
    key_count="$(echo "${result}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")"
    [ "$key_count" = "3" ]
}

# ==========================================================================
# UNIT TESTS: mcp_get — registry lookups
# ==========================================================================

@test "mcp_get: returns mcp-proxy-search as package for brave-search" {
    local pkg
    pkg="$(mcp_get "brave-search" "package")"
    [ "$pkg" = "mcp-proxy-search" ]
}

@test "mcp_get: returns mcp-proxy-search as package for tavily" {
    local pkg
    pkg="$(mcp_get "tavily" "package")"
    [ "$pkg" = "mcp-proxy-search" ]
}

@test "mcp_get: returns correct proxy_service for brave-search" {
    local svc
    svc="$(mcp_get "brave-search" "proxy_service")"
    [ "$svc" = "brave" ]
}

@test "mcp_get: returns correct proxy_service for tavily" {
    local svc
    svc="$(mcp_get "tavily" "proxy_service")"
    [ "$svc" = "tavily" ]
}

@test "mcp_get: returns correct env_var for brave-search" {
    local ev
    ev="$(mcp_get "brave-search" "env_var")"
    [ "$ev" = "BRAVE_API_KEY" ]
}

@test "mcp_get: returns correct env_var for tavily" {
    local ev
    ev="$(mcp_get "tavily" "env_var")"
    [ "$ev" = "TAVILY_API_KEY" ]
}

@test "mcp_get: unknown key returns error" {
    run mcp_get "unknown-server" "package"
    [ "$status" -eq 1 ]
}

# ==========================================================================
# INTEGRATION TESTS: _configure_single_mcp with mocked claude CLI
# ==========================================================================

@test "integration: _configure_single_mcp calls claude mcp add-json (doppler)" {
    # Create a mock claude that captures its arguments
    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    _configure_single_mcp "brave-search" "doppler"

    # Verify claude was called with add-json, not add
    local call
    call="$(cat "${mock_log}")"
    [[ "$call" == *"mcp add-json"* ]]
    [[ "$call" == *"--scope user"* ]]
    [[ "$call" == *"brave-search"* ]]
}

@test "integration: _configure_single_mcp calls claude mcp add-json (envfile)" {
    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    _configure_single_mcp "tavily" "envfile"

    local call
    call="$(cat "${mock_log}")"
    [[ "$call" == *"mcp add-json"* ]]
    [[ "$call" == *"tavily"* ]]
}

@test "integration: _configure_single_mcp passes valid JSON to claude" {
    # Mock claude that validates the JSON argument
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
# The last argument should be JSON — validate it
for arg in "$@"; do :; done  # last arg is in $arg
echo "$arg" | python3 -m json.tool > /dev/null 2>&1 || exit 99
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    run _configure_single_mcp "brave-search" "doppler"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
}

@test "integration: _configure_single_mcp shows error on claude failure" {
    # Mock claude that always fails
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    run _configure_single_mcp "brave-search" "doppler"
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"Manual:"* ]]
}

@test "integration: _configure_single_mcp removes existing before re-adding" {
    # Create a fake ~/.claude.json with an existing brave-search entry
    cat > "${CLAUDE_JSON}" <<'JSON'
{"mcpServers":{"brave-search":{"type":"stdio","command":"old"}}}
JSON

    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    _configure_single_mcp "brave-search" "doppler"

    # Should have two calls: remove then add-json
    local call_count
    call_count="$(wc -l < "${mock_log}" | tr -d ' ')"
    [ "$call_count" -eq 2 ]

    # First call should be remove
    local first_call
    first_call="$(head -1 "${mock_log}")"
    [[ "$first_call" == *"mcp remove"* ]]

    # Second call should be add-json
    local second_call
    second_call="$(tail -1 "${mock_log}")"
    [[ "$second_call" == *"mcp add-json"* ]]
}

@test "integration: _configure_single_mcp skips remove when no existing config" {
    # No CLAUDE_JSON file exists
    rm -f "${CLAUDE_JSON}"

    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    _configure_single_mcp "brave-search" "doppler"

    # Should have only one call: add-json (no remove)
    local call_count
    call_count="$(wc -l < "${mock_log}" | tr -d ' ')"
    [ "$call_count" -eq 1 ]

    local call
    call="$(cat "${mock_log}")"
    [[ "$call" == *"mcp add-json"* ]]
}

@test "integration: _configure_single_mcp skips remove when server not in config" {
    # CLAUDE_JSON exists but doesn't have brave-search
    cat > "${CLAUDE_JSON}" <<'JSON'
{"mcpServers":{"other-server":{"type":"stdio","command":"foo"}}}
JSON

    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    _configure_single_mcp "brave-search" "doppler"

    # Should have only one call: add-json (no remove)
    local call_count
    call_count="$(wc -l < "${mock_log}" | tr -d ' ')"
    [ "$call_count" -eq 1 ]
}

# ==========================================================================
# INTEGRATION TESTS: configure_mcp_servers (full flow)
# ==========================================================================

@test "integration: configure_mcp_servers processes all selected servers" {
    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    # Set up the servers to install
    INSTALL_MCP_SERVERS=("brave-search" "tavily")

    run configure_mcp_servers
    [ "$status" -eq 0 ]

    # Should have called add-json for both servers
    local brave_count tavily_count
    brave_count="$(grep -c "brave-search" "${mock_log}")"
    tavily_count="$(grep -c "tavily" "${mock_log}")"
    [ "$brave_count" -ge 1 ]
    [ "$tavily_count" -ge 1 ]
}

@test "integration: configure_mcp_servers warns when claude CLI not found" {
    # Build a hermetic PATH with only the tools mcp.sh needs (bash, jq, python3)
    # but intentionally excluding claude — avoids false pass if claude is in
    # /usr/local/bin or /opt/homebrew/bin on some machines.
    local hermetic="${TEST_TMPDIR}/hermetic-bin"
    mkdir -p "${hermetic}"
    local cmd
    for cmd in bash jq python3; do
        local real
        real="$(command -v "${cmd}" 2>/dev/null)" && ln -s "${real}" "${hermetic}/${cmd}"
    done

    run bash -c '
        export PATH="'"${hermetic}"'"
        source "'"${MCP_SH}"'"
        INSTALL_MCP_SERVERS=("brave-search")
        configure_mcp_servers
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code CLI not found"* ]]
}

# ==========================================================================
# REGRESSION TEST: the original bug — short flags after -- are not consumed
# ==========================================================================

@test "regression: proxy JSON args don't contain CLI-parseable flags" {
    # Proxy servers use simple --service args, no -p/-c that could be
    # consumed by the claude CLI parser.
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"

    local args_json
    args_json="$(echo "${result}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['args']))")"
    [ "$args_json" = '["--service", "brave"]' ]
    [[ "$result" != *'"-p"'* ]]
    [[ "$result" != *'"-c"'* ]]

    # Mock claude receives the JSON as one argument (no flag leakage)
    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
for arg in "$@"; do echo "ARG:${arg}"; done >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    _configure_single_mcp "brave-search" "doppler"

    # --service should be INSIDE the JSON string, not a standalone CLI flag
    local standalone_service
    standalone_service="$(grep -c '^ARG:--service$' "${mock_log}" || true)"
    [ "$standalone_service" -eq 0 ]

    # The JSON argument should contain --service
    local json_arg
    json_arg="$(grep 'ARG:{' "${mock_log}")"
    [[ "$json_arg" == *'"--service"'* ]]
    [[ "$json_arg" == *'"brave"'* ]]
}
