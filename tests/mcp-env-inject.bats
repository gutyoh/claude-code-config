#!/usr/bin/env bats
# mcp-env-inject.bats
# Path: tests/mcp-env-inject.bats
#
# Unit + integration tests for the mcp-env-inject wrapper script.
# Verifies that environment variables are injected into child processes
# and that the wrapper handles edge cases gracefully.
#
# Run: bats tests/mcp-env-inject.bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/mcp-env-inject"

# --- Setup / Teardown ---

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    export MCP_KEYS_ENV_FILE="${TEST_TMPDIR}/mcp-keys.env"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# ==========================================================================
# UNIT TESTS: Script basics
# ==========================================================================

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "no args with empty expansion is a no-op exec" {
    # exec with no arguments is a no-op in bash (returns 0)
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "runs a simple command without env file" {
    # No env file exists — should still exec the command
    rm -f "${MCP_KEYS_ENV_FILE}"
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "passes through exit code from child command" {
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c "exit 42"
    [ "$status" -eq 42 ]
}

# ==========================================================================
# UNIT TESTS: Environment injection
# ==========================================================================

@test "injects single variable into child process" {
    echo "MY_TEST_VAR=hello-from-env" > "${MCP_KEYS_ENV_FILE}"
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'echo "${MY_TEST_VAR}"'
    [ "$status" -eq 0 ]
    [ "$output" = "hello-from-env" ]
}

@test "injects multiple variables into child process" {
    cat > "${MCP_KEYS_ENV_FILE}" <<'EOF'
BRAVE_API_KEY=test-brave-key-123
TAVILY_API_KEY=test-tavily-key-456
EOF
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'echo "${BRAVE_API_KEY}:${TAVILY_API_KEY}"'
    [ "$status" -eq 0 ]
    [ "$output" = "test-brave-key-123:test-tavily-key-456" ]
}

@test "variables are exported (visible to grandchild processes)" {
    echo "DEEP_VAR=deep-value" > "${MCP_KEYS_ENV_FILE}"
    # The variable must be exported so a grandchild script can see it
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'bash -c "echo \${DEEP_VAR}"'
    [ "$status" -eq 0 ]
    [ "$output" = "deep-value" ]
}

@test "does not leak variables when env file is missing" {
    rm -f "${MCP_KEYS_ENV_FILE}"
    run env -u LEAKED_VAR MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'echo "val=${LEAKED_VAR:-empty}"'
    [ "$status" -eq 0 ]
    [ "$output" = "val=empty" ]
}

@test "handles empty env file gracefully" {
    touch "${MCP_KEYS_ENV_FILE}"
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" echo "still-works"
    [ "$status" -eq 0 ]
    [ "$output" = "still-works" ]
}

@test "handles env file with comments" {
    cat > "${MCP_KEYS_ENV_FILE}" <<'EOF'
# This is a comment
BRAVE_API_KEY=key-with-comments
# Another comment
TAVILY_API_KEY=another-key
EOF
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'echo "${BRAVE_API_KEY}:${TAVILY_API_KEY}"'
    [ "$status" -eq 0 ]
    [ "$output" = "key-with-comments:another-key" ]
}

@test "handles keys with special characters (base64-like)" {
    local special_key="ABCdef123+/xyz=="
    echo "SPECIAL_KEY=${special_key}" > "${MCP_KEYS_ENV_FILE}"
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'echo "${SPECIAL_KEY}"'
    [ "$status" -eq 0 ]
    [ "$output" = "${special_key}" ]
}

@test "env file variables override existing environment" {
    echo "OVERRIDE_ME=from-file" > "${MCP_KEYS_ENV_FILE}"
    run env OVERRIDE_ME=from-env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'echo "${OVERRIDE_ME}"'
    [ "$status" -eq 0 ]
    [ "$output" = "from-file" ]
}

# ==========================================================================
# UNIT TESTS: exec replacement (process is replaced, not forked)
# ==========================================================================

@test "exec replaces process (passes all args through)" {
    echo "TEST_VAR=present" > "${MCP_KEYS_ENV_FILE}"
    # Use printf with multiple args to verify all args are passed
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" printf "%s|%s|%s" "a" "b" "c"
    [ "$status" -eq 0 ]
    [ "$output" = "a|b|c" ]
}

# ==========================================================================
# INTEGRATION: Simulates real MCP server launch pattern
# ==========================================================================

@test "integration: simulates MCP server env injection" {
    # This simulates the real use case:
    # claude launches mcp-env-inject npx -y tavily-mcp
    # mcp-env-inject sources keys, then exec's npx
    # The child process (tavily-mcp) gets the API key in its environment
    cat > "${MCP_KEYS_ENV_FILE}" <<'EOF'
TAVILY_API_KEY=tvly-test-integration-key
BRAVE_API_KEY=BSA-test-integration-key
EOF

    # Simulate the MCP server reading its API key from env
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c '
            if [[ -n "${TAVILY_API_KEY}" && -n "${BRAVE_API_KEY}" ]]; then
                echo "PASS: both keys injected"
                echo "TAVILY=${#TAVILY_API_KEY} chars"
                echo "BRAVE=${#BRAVE_API_KEY} chars"
            else
                echo "FAIL: missing keys"
                exit 1
            fi
        '
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: both keys injected"* ]]
    [[ "$output" == *"TAVILY=25 chars"* ]]
    [[ "$output" == *"BRAVE=24 chars"* ]]
}

@test "integration: works from arbitrary working directory" {
    # The whole point: keys are available regardless of cwd
    cat > "${MCP_KEYS_ENV_FILE}" <<'EOF'
TAVILY_API_KEY=tvly-from-any-dir
EOF

    # Run from /tmp (not the repo directory)
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash -c 'cd /tmp && bash '"$SCRIPT"' bash -c "echo \${TAVILY_API_KEY}"'
    [ "$status" -eq 0 ]
    [ "$output" = "tvly-from-any-dir" ]
}

@test "integration: env file permissions are restrictive (600)" {
    echo "SECRET=value" > "${MCP_KEYS_ENV_FILE}"
    chmod 600 "${MCP_KEYS_ENV_FILE}"

    # Should still be readable by the owner
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$SCRIPT" bash -c 'echo "${SECRET}"'
    [ "$status" -eq 0 ]
    [ "$output" = "value" ]

    # Verify the file is mode 600
    local perms
    perms="$(stat -f '%Lp' "${MCP_KEYS_ENV_FILE}" 2>/dev/null || stat -c '%a' "${MCP_KEYS_ENV_FILE}" 2>/dev/null)"
    [ "$perms" = "600" ]
}
