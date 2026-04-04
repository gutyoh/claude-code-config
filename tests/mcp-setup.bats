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

@test "_build_mcp_json: doppler backend produces correct JSON for brave-search" {
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"

    # Validate it's valid JSON
    echo "${result}" | python3 -m json.tool > /dev/null

    # Check structure
    local cmd args_len
    cmd="$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin)['command'])")"
    [ "$cmd" = "doppler" ]

    local type_val
    type_val="$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin)['type'])")"
    [ "$type_val" = "stdio" ]
}

@test "_build_mcp_json: doppler backend includes -p and -c flags in args" {
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"

    # Extract args as a comma-separated string for easy matching
    local args
    args="$(echo "${result}" | python3 -c "import sys,json; print(','.join(json.load(sys.stdin)['args']))")"

    [[ "$args" == *"-p"* ]]
    [[ "$args" == *"-c"* ]]
    [[ "$args" == *"claude-code-config"* ]]
    [[ "$args" == *"dev"* ]]
    [[ "$args" == *"--"* ]]
    [[ "$args" == *"npx"* ]]
    [[ "$args" == *"-y"* ]]
    [[ "$args" == *"@brave/brave-search-mcp-server"* ]]
}

@test "_build_mcp_json: doppler backend args are in correct order" {
    local result
    result="$(_build_mcp_json "brave-search" "doppler")"

    # Verify exact args array
    local args_json
    args_json="$(echo "${result}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['args']))")"
    [ "$args_json" = '["run", "-p", "claude-code-config", "-c", "dev", "--", "npx", "-y", "@brave/brave-search-mcp-server"]' ]
}

@test "_build_mcp_json: doppler backend produces correct JSON for tavily" {
    local result
    result="$(_build_mcp_json "tavily" "doppler")"

    echo "${result}" | python3 -m json.tool > /dev/null

    local args_json
    args_json="$(echo "${result}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['args']))")"
    [ "$args_json" = '["run", "-p", "claude-code-config", "-c", "dev", "--", "npx", "-y", "tavily-mcp@0.2.17"]' ]
}

@test "_build_mcp_json: envfile backend produces correct JSON for brave-search" {
    local result
    result="$(_build_mcp_json "brave-search" "envfile")"

    echo "${result}" | python3 -m json.tool > /dev/null

    local cmd
    cmd="$(echo "${result}" | python3 -c "import sys,json; print(json.load(sys.stdin)['command'])")"
    [ "$cmd" = "mcp-env-inject" ]

    local args_json
    args_json="$(echo "${result}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['args']))")"
    [ "$args_json" = '["npx", "-y", "@brave/brave-search-mcp-server"]' ]
}

@test "_build_mcp_json: envfile backend produces correct JSON for tavily" {
    local result
    result="$(_build_mcp_json "tavily" "envfile")"

    echo "${result}" | python3 -m json.tool > /dev/null

    local args_json
    args_json="$(echo "${result}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['args']))")"
    [ "$args_json" = '["npx", "-y", "tavily-mcp@0.2.17"]' ]
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

@test "_build_mcp_json: respects MCP_DOPPLER_PROJECT override" {
    # DOPPLER_PROJECT is readonly in the sourced script, so we override
    # by sourcing again with the env var set in a subshell
    local result
    result="$(MCP_DOPPLER_PROJECT=my-custom-proj bash -c '
        source "'"${MCP_SH}"'"
        _build_mcp_json "brave-search" "doppler"
    ')"

    [[ "$result" == *"my-custom-proj"* ]]
}

@test "_build_mcp_json: respects MCP_DOPPLER_CONFIG override" {
    local result
    result="$(MCP_DOPPLER_CONFIG=staging bash -c '
        source "'"${MCP_SH}"'"
        _build_mcp_json "brave-search" "doppler"
    ')"

    [[ "$result" == *"staging"* ]]
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

@test "mcp_get: returns correct package for brave-search" {
    local pkg
    pkg="$(mcp_get "brave-search" "package")"
    [ "$pkg" = "@brave/brave-search-mcp-server" ]
}

@test "mcp_get: returns correct package for tavily" {
    local pkg
    pkg="$(mcp_get "tavily" "package")"
    [ "$pkg" = "tavily-mcp@0.2.17" ]
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
    # Run in a subshell with PATH stripped to only system dirs (no claude).
    # /usr/bin:/bin provide bash, rm, jq, python3, etc.
    run bash -c '
        export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
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

@test "regression: JSON args contain -p and -c without CLI parser conflict" {
    # This is the core regression test. The old `claude mcp add` approach
    # failed because `-p` and `-c` after `--` were consumed by the CLI parser.
    # With `claude mcp add-json`, flags are inside a JSON string argument,
    # so the CLI parser never sees them.

    local result
    result="$(_build_mcp_json "brave-search" "doppler")"

    # The JSON must contain -p and -c as args elements
    local has_p has_c
    has_p="$(echo "${result}" | python3 -c "import sys,json; print('-p' in json.load(sys.stdin)['args'])")"
    has_c="$(echo "${result}" | python3 -c "import sys,json; print('-c' in json.load(sys.stdin)['args'])")"
    [ "$has_p" = "True" ]
    [ "$has_c" = "True" ]

    # But they're inside a JSON string, not as CLI flags
    # The mock claude should receive them as part of one JSON argument
    local mock_log="${TEST_TMPDIR}/claude-calls.log"
    cat > "${TEST_TMPDIR}/claude" <<'MOCK'
#!/usr/bin/env bash
# Log each argument on its own line for inspection
for arg in "$@"; do
    echo "ARG:${arg}"
done >> "$(dirname "$0")/claude-calls.log"
exit 0
MOCK
    chmod +x "${TEST_TMPDIR}/claude"
    export PATH="${TEST_TMPDIR}:${PATH}"

    _configure_single_mcp "brave-search" "doppler"

    # -p and -c should NOT appear as standalone arguments
    # They should only appear inside the JSON string argument
    local standalone_p standalone_c
    standalone_p="$(grep -c '^ARG:-p$' "${mock_log}" || true)"
    standalone_c="$(grep -c '^ARG:-c$' "${mock_log}" || true)"
    [ "$standalone_p" -eq 0 ]
    [ "$standalone_c" -eq 0 ]

    # The JSON argument should contain them
    local json_arg
    json_arg="$(grep 'ARG:{' "${mock_log}")"
    [[ "$json_arg" == *'"-p"'* ]]
    [[ "$json_arg" == *'"-c"'* ]]
}
