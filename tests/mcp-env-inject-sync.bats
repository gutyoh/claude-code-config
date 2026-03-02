#!/usr/bin/env bats
# mcp-env-inject-sync.bats
# Path: tests/mcp-env-inject-sync.bats
#
# Tests for mcp-key-rotate --sync and auto-sync after rotation.
# Also tests detect_mcp_backend() in lib/setup/mcp.sh.
#
# Run: bats tests/mcp-env-inject-sync.bats

ROTATE_SCRIPT="$BATS_TEST_DIRNAME/../bin/mcp-key-rotate"
INJECT_SCRIPT="$BATS_TEST_DIRNAME/../bin/mcp-env-inject"
MCP_SH="$BATS_TEST_DIRNAME/../lib/setup/mcp.sh"

# --- Test fixtures ---
KEY_A="test-key-AAAA-1111"
KEY_B="test-key-BBBB-2222"
KEY_C="test-key-CCCC-3333"

# --- Setup / Teardown ---

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_DOTENV="${TEST_TMPDIR}/.env"
    export MCP_KEYS_ENV_FILE="${TEST_TMPDIR}/mcp-keys.env"

    # Create a mock doppler script in temp dir
    export MOCK_DOPPLER="${TEST_TMPDIR}/doppler"
    export MOCK_DOPPLER_STORE="${TEST_TMPDIR}/doppler_store"
    mkdir -p "${MOCK_DOPPLER_STORE}"

    cat > "${MOCK_DOPPLER}" <<'MOCK_EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "secrets" ]]; then
    if [[ "${2:-}" == "get" ]]; then
        local_name="${3:-}"
        store_file="${MOCK_DOPPLER_STORE}/${local_name}"
        if [[ -f "${store_file}" ]]; then
            cat "${store_file}"
        else
            exit 1
        fi
    elif [[ "${2:-}" == "set" ]]; then
        local_pair="${3:-}"
        local_name="${local_pair%%=*}"
        local_value="${local_pair#*=}"
        echo -n "${local_value}" > "${MOCK_DOPPLER_STORE}/${local_name}"
    fi
fi
MOCK_EOF
    chmod +x "${MOCK_DOPPLER}"

    export PATH="${TEST_TMPDIR}:${PATH}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# --- Helpers ---
doppler_seed() {
    local name="$1" value="$2"
    echo -n "${value}" > "${MOCK_DOPPLER_STORE}/${name}"
}

dotenv_seed() {
    local name="$1" value="$2"
    echo "${name}=${value}" >> "${TEST_DOTENV}"
}

# ==========================================================================
# UNIT TESTS: --sync command
# ==========================================================================

@test "sync: creates entry in mcp-keys.env" {
    dotenv_seed "BRAVE_API_KEY" "${KEY_A}"
    dotenv_seed "BRAVE_API_KEY_POOL" "${KEY_A}"
    touch "${MCP_KEYS_ENV_FILE}"

    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" brave --sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"Synced brave"* ]]

    # Verify the env file has the key
    grep -q "^BRAVE_API_KEY=${KEY_A}" "${MCP_KEYS_ENV_FILE}"
}

@test "sync: updates existing entry in mcp-keys.env" {
    dotenv_seed "TAVILY_API_KEY" "${KEY_B}"
    dotenv_seed "TAVILY_API_KEY_POOL" "${KEY_A},${KEY_B}"
    echo "TAVILY_API_KEY=${KEY_A}" > "${MCP_KEYS_ENV_FILE}"

    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" tavily --sync
    [ "$status" -eq 0 ]

    # Should be updated to KEY_B (the current active key in .env)
    local val
    val="$(grep "^TAVILY_API_KEY=" "${MCP_KEYS_ENV_FILE}" | cut -d'=' -f2-)"
    [ "${val}" = "${KEY_B}" ]
}

@test "sync: preserves other keys in mcp-keys.env" {
    dotenv_seed "BRAVE_API_KEY" "${KEY_B}"
    dotenv_seed "BRAVE_API_KEY_POOL" "${KEY_A},${KEY_B}"
    cat > "${MCP_KEYS_ENV_FILE}" <<EOF
TAVILY_API_KEY=${KEY_C}
BRAVE_API_KEY=${KEY_A}
OTHER_VAR=keep-me
EOF

    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" brave --sync
    [ "$status" -eq 0 ]

    # Brave updated
    local brave_val
    brave_val="$(grep "^BRAVE_API_KEY=" "${MCP_KEYS_ENV_FILE}" | cut -d'=' -f2-)"
    [ "${brave_val}" = "${KEY_B}" ]

    # Others preserved
    grep -q "^TAVILY_API_KEY=${KEY_C}" "${MCP_KEYS_ENV_FILE}"
    grep -q "^OTHER_VAR=keep-me" "${MCP_KEYS_ENV_FILE}"
}

@test "sync: sets file permissions to 600" {
    dotenv_seed "BRAVE_API_KEY" "${KEY_A}"
    dotenv_seed "BRAVE_API_KEY_POOL" "${KEY_A}"
    touch "${MCP_KEYS_ENV_FILE}"
    chmod 644 "${MCP_KEYS_ENV_FILE}"

    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" brave --sync
    [ "$status" -eq 0 ]

    local perms
    perms="$(stat -f '%Lp' "${MCP_KEYS_ENV_FILE}" 2>/dev/null || stat -c '%a' "${MCP_KEYS_ENV_FILE}" 2>/dev/null)"
    [ "$perms" = "600" ]
}

@test "sync: help output lists --sync command" {
    dotenv_seed "BRAVE_API_KEY" "${KEY_A}"
    dotenv_seed "BRAVE_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$ROTATE_SCRIPT" brave --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--sync"* ]]
}

# ==========================================================================
# UNIT TESTS: Auto-sync after rotation (dotenv backend)
# ==========================================================================

@test "auto-sync: rotation updates mcp-keys.env (dotenv)" {
    dotenv_seed "SVC_API_KEY" "${KEY_A}"
    dotenv_seed "SVC_API_KEY_POOL" "${KEY_A},${KEY_B}"
    echo "SVC_API_KEY=${KEY_A}" > "${MCP_KEYS_ENV_FILE}"

    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" svc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated svc"* ]]
    [[ "$output" == *"Synced SVC_API_KEY"* ]]

    # Verify mcp-keys.env was updated to KEY_B
    local val
    val="$(grep "^SVC_API_KEY=" "${MCP_KEYS_ENV_FILE}" | cut -d'=' -f2-)"
    [ "${val}" = "${KEY_B}" ]
}

@test "auto-sync: rotation does NOT sync for doppler backend" {
    doppler_seed "SVC_API_KEY" "${KEY_A}"
    doppler_seed "SVC_API_KEY_POOL" "${KEY_A},${KEY_B}"
    touch "${MCP_KEYS_ENV_FILE}"

    run env KEY_ROTATE_BACKEND=doppler \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" svc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated svc"* ]]
    # Should NOT contain "Synced" — Doppler injects keys live
    [[ "$output" != *"Synced"* ]]

    # mcp-keys.env should be empty (untouched)
    [ ! -s "${MCP_KEYS_ENV_FILE}" ]
}

@test "auto-sync: skipped if mcp-keys.env does not exist" {
    dotenv_seed "SVC_API_KEY" "${KEY_A}"
    dotenv_seed "SVC_API_KEY_POOL" "${KEY_A},${KEY_B}"
    rm -f "${MCP_KEYS_ENV_FILE}"

    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" svc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated svc"* ]]
    # Should NOT have created the file (sync only updates existing files)
    [ ! -f "${MCP_KEYS_ENV_FILE}" ]
}

# ==========================================================================
# INTEGRATION: Full rotate + sync + inject cycle
# ==========================================================================

@test "integration: rotate syncs key, then mcp-env-inject reads it" {
    # Setup: 2 keys in pool, KEY_A active
    dotenv_seed "BRAVE_API_KEY" "${KEY_A}"
    dotenv_seed "BRAVE_API_KEY_POOL" "${KEY_A},${KEY_B}"
    echo "BRAVE_API_KEY=${KEY_A}" > "${MCP_KEYS_ENV_FILE}"

    # Step 1: Verify mcp-env-inject reads KEY_A
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$INJECT_SCRIPT" bash -c 'echo "${BRAVE_API_KEY}"'
    [ "$status" -eq 0 ]
    [ "$output" = "${KEY_A}" ]

    # Step 2: Rotate (A -> B), auto-syncs to mcp-keys.env
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" brave
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated brave"* ]]

    # Step 3: Verify mcp-env-inject now reads KEY_B
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$INJECT_SCRIPT" bash -c 'echo "${BRAVE_API_KEY}"'
    [ "$status" -eq 0 ]
    [ "$output" = "${KEY_B}" ]
}

@test "integration: multi-service rotate + sync + inject" {
    # Setup: both services
    dotenv_seed "BRAVE_API_KEY" "${KEY_A}"
    dotenv_seed "BRAVE_API_KEY_POOL" "${KEY_A},${KEY_B}"
    dotenv_seed "TAVILY_API_KEY" "${KEY_C}"
    dotenv_seed "TAVILY_API_KEY_POOL" "${KEY_C},${KEY_A}"
    cat > "${MCP_KEYS_ENV_FILE}" <<EOF
BRAVE_API_KEY=${KEY_A}
TAVILY_API_KEY=${KEY_C}
EOF

    # Rotate brave: A -> B
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" brave
    [ "$status" -eq 0 ]

    # Rotate tavily: C -> A
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$ROTATE_SCRIPT" tavily
    [ "$status" -eq 0 ]

    # Verify mcp-env-inject reads both updated keys
    run env MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash "$INJECT_SCRIPT" bash -c 'echo "${BRAVE_API_KEY}:${TAVILY_API_KEY}"'
    [ "$status" -eq 0 ]
    [ "$output" = "${KEY_B}:${KEY_A}" ]
}

# ==========================================================================
# UNIT TESTS: detect_mcp_backend (from lib/setup/mcp.sh)
# ==========================================================================

@test "detect_mcp_backend: returns doppler when doppler is available" {
    # Mock doppler is already in PATH and BRAVE_API_KEY is seeded
    doppler_seed "BRAVE_API_KEY" "${KEY_A}"

    run bash -c '
        source "'"${MCP_SH}"'"
        detect_mcp_backend
    '
    [ "$status" -eq 0 ]
    [ "$output" = "doppler" ]
}

@test "detect_mcp_backend: returns envfile when doppler is not available" {
    # Build a minimal PATH with only system dirs, excluding mock doppler AND real doppler
    # We need basic commands (bash, grep, etc.) but no doppler anywhere
    local minimal_path="/usr/bin:/bin:/usr/sbin:/sbin"

    run env PATH="${minimal_path}" bash -c '
        source "'"${MCP_SH}"'"
        detect_mcp_backend
    '
    [ "$status" -eq 0 ]
    [ "$output" = "envfile" ]
}

@test "detect_mcp_backend: returns envfile when doppler project is inaccessible" {
    # Mock doppler is in PATH but no secrets are seeded (secrets get will fail)
    run bash -c '
        source "'"${MCP_SH}"'"
        detect_mcp_backend
    '
    [ "$status" -eq 0 ]
    [ "$output" = "envfile" ]
}

# ==========================================================================
# UNIT TESTS: _create_mcp_keys_env respects INSTALL_MCP_SERVERS (not MCP_SERVER_KEYS)
# ==========================================================================

@test "_create_mcp_keys_env: only writes keys for selected servers (tavily only)" {
    # Simulate: user selected only tavily, not brave-search
    export TAVILY_API_KEY="${KEY_A}"

    local env_file="${TEST_TMPDIR}/mcp-keys-subset.env"

    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        TAVILY_API_KEY="${KEY_A}" \
        MCP_KEYS_ENV_FILE="${env_file}" \
        REPO_DIR="${TEST_TMPDIR}" \
        bash -c '
            INSTALL_MCP_SERVERS=("tavily")
            source "'"${MCP_SH}"'"
            _create_mcp_keys_env
        '
    [ "$status" -eq 0 ]

    # tavily key should be written
    grep -q "^TAVILY_API_KEY=${KEY_A}" "${env_file}"

    # brave key should NOT be written (not in INSTALL_MCP_SERVERS)
    ! grep -q "^BRAVE_API_KEY=" "${env_file}"

    # Output should NOT warn about BRAVE_API_KEY
    [[ "$output" != *"BRAVE_API_KEY"* ]]
}

@test "_create_mcp_keys_env: only writes keys for selected servers (brave-search only)" {
    local env_file="${TEST_TMPDIR}/mcp-keys-subset2.env"

    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        BRAVE_API_KEY="${KEY_B}" \
        MCP_KEYS_ENV_FILE="${env_file}" \
        REPO_DIR="${TEST_TMPDIR}" \
        bash -c '
            INSTALL_MCP_SERVERS=("brave-search")
            source "'"${MCP_SH}"'"
            _create_mcp_keys_env
        '
    [ "$status" -eq 0 ]

    # brave key should be written
    grep -q "^BRAVE_API_KEY=${KEY_B}" "${env_file}"

    # tavily key should NOT be written
    ! grep -q "^TAVILY_API_KEY=" "${env_file}"

    # Output should NOT mention TAVILY_API_KEY
    [[ "$output" != *"TAVILY_API_KEY"* ]]
}

@test "_create_mcp_keys_env: writes all keys when all servers selected" {
    local env_file="${TEST_TMPDIR}/mcp-keys-all.env"

    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        BRAVE_API_KEY="${KEY_A}" \
        TAVILY_API_KEY="${KEY_B}" \
        MCP_KEYS_ENV_FILE="${env_file}" \
        REPO_DIR="${TEST_TMPDIR}" \
        bash -c '
            INSTALL_MCP_SERVERS=("brave-search" "tavily")
            source "'"${MCP_SH}"'"
            _create_mcp_keys_env
        '
    [ "$status" -eq 0 ]

    grep -q "^BRAVE_API_KEY=${KEY_A}" "${env_file}"
    grep -q "^TAVILY_API_KEY=${KEY_B}" "${env_file}"
}

# ==========================================================================
# UNIT TESTS: check_mcp_env_vars respects INSTALL_MCP_SERVERS (not MCP_SERVER_KEYS)
# ==========================================================================

@test "check_mcp_env_vars: only checks selected servers (tavily only)" {
    # Create env file with only tavily key
    echo "TAVILY_API_KEY=${KEY_A}" > "${MCP_KEYS_ENV_FILE}"

    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash -c '
            INSTALL_MCP_SERVERS=("tavily")
            source "'"${MCP_SH}"'"
            check_mcp_env_vars
        '
    [ "$status" -eq 0 ]

    # Should report tavily found
    [[ "$output" == *"TAVILY_API_KEY found"* ]]

    # Should NOT warn about brave (not in INSTALL_MCP_SERVERS)
    [[ "$output" != *"BRAVE_API_KEY"* ]]
}

@test "check_mcp_env_vars: only checks selected servers (brave-search only)" {
    # Create env file with only brave key
    echo "BRAVE_API_KEY=${KEY_B}" > "${MCP_KEYS_ENV_FILE}"

    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash -c '
            INSTALL_MCP_SERVERS=("brave-search")
            source "'"${MCP_SH}"'"
            check_mcp_env_vars
        '
    [ "$status" -eq 0 ]

    # Should report brave found
    [[ "$output" == *"BRAVE_API_KEY found"* ]]

    # Should NOT warn about tavily
    [[ "$output" != *"TAVILY_API_KEY"* ]]
}

@test "check_mcp_env_vars: warns about missing key only for selected server" {
    # Create env file with NO keys
    touch "${MCP_KEYS_ENV_FILE}"

    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE}" \
        bash -c '
            INSTALL_MCP_SERVERS=("tavily")
            source "'"${MCP_SH}"'"
            check_mcp_env_vars
        '
    [ "$status" -eq 0 ]

    # Should warn about tavily being missing
    [[ "$output" == *"TAVILY_API_KEY missing"* ]]

    # Should NOT warn about brave (not selected)
    [[ "$output" != *"BRAVE_API_KEY"* ]]
}

# ==========================================================================
# INTEGRATION: Repo structure validation
# ==========================================================================

REPO_ROOT="$BATS_TEST_DIRNAME/.."

@test "repo: bin/mcp-env-inject exists and is executable" {
    [ -x "${REPO_ROOT}/bin/mcp-env-inject" ]
}

@test "repo: setup.sh references mcp-env-inject" {
    grep -q "mcp-env-inject" "${REPO_ROOT}/setup.sh"
}

@test "repo: lib/setup/mcp.sh has detect_mcp_backend function" {
    grep -q "detect_mcp_backend" "${REPO_ROOT}/lib/setup/mcp.sh"
}

@test "repo: lib/setup/mcp.sh references doppler run wrapper" {
    grep -q "doppler run" "${REPO_ROOT}/lib/setup/mcp.sh"
}

@test "repo: lib/setup/mcp.sh references mcp-env-inject wrapper" {
    grep -q "mcp-env-inject" "${REPO_ROOT}/lib/setup/mcp.sh"
}

@test "repo: mcp-key-rotate has --sync command" {
    grep -q "cmd_sync" "${REPO_ROOT}/bin/mcp-key-rotate"
    grep -q "\-\-sync" "${REPO_ROOT}/bin/mcp-key-rotate"
}

@test "repo: mcp-key-rotate has sync_mcp_keys_env function" {
    grep -q "sync_mcp_keys_env" "${REPO_ROOT}/bin/mcp-key-rotate"
}
