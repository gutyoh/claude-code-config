#!/usr/bin/env bats
# mcp-key-rotate.bats
# Path: tests/mcp-key-rotate.bats
#
# Unit + integration tests for the mcp-key-rotate script.
# Covers both backends (doppler mock, dotenv real), all commands,
# and edge cases.
#
# Run: bats tests/mcp-key-rotate.bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/mcp-key-rotate"

# --- Test fixtures ---
KEY_A="test-key-AAAA-1111"
KEY_B="test-key-BBBB-2222"
KEY_C="test-key-CCCC-3333"
SHORT_KEY="abc"

# --- Setup / Teardown ---

setup() {
    # Create a temp dir for each test
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_DOTENV="${TEST_TMPDIR}/.env"

    # Create a mock doppler script in temp dir
    export MOCK_DOPPLER="${TEST_TMPDIR}/doppler"
    export MOCK_DOPPLER_STORE="${TEST_TMPDIR}/doppler_store"
    mkdir -p "${MOCK_DOPPLER_STORE}"

    cat > "${MOCK_DOPPLER}" <<'MOCK_EOF'
#!/usr/bin/env bash
# Mock doppler CLI that reads/writes from flat files in MOCK_DOPPLER_STORE
set -euo pipefail

# Parse: doppler secrets get <name> --plain -p <project> -c <config>
# Parse: doppler secrets set <name>=<value> -p <project> -c <config>
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
        # Parse NAME=VALUE from $3
        local_pair="${3:-}"
        local_name="${local_pair%%=*}"
        local_value="${local_pair#*=}"
        echo -n "${local_value}" > "${MOCK_DOPPLER_STORE}/${local_name}"
    fi
fi
MOCK_EOF
    chmod +x "${MOCK_DOPPLER}"

    # Put mock doppler first in PATH
    export PATH="${TEST_TMPDIR}:${PATH}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# --- Helper: seed doppler mock store ---
doppler_seed() {
    local name="$1" value="$2"
    echo -n "${value}" > "${MOCK_DOPPLER_STORE}/${name}"
}

# --- Helper: read doppler mock store ---
doppler_read() {
    local name="$1"
    cat "${MOCK_DOPPLER_STORE}/${name}" 2>/dev/null
}

# --- Helper: seed .env file ---
dotenv_seed() {
    local name="$1" value="$2"
    echo "${name}=${value}" >> "${TEST_DOTENV}"
}

# ==========================================================================
# UNIT TESTS: Script basics
# ==========================================================================

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "no args prints usage and exits 1" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: mcp-key-rotate"* ]]
}

@test "service --help exits 0 with usage" {
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" testservice --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mcp-key-rotate"* ]]
    [[ "$output" == *"Backends:"* ]]
}

@test "unknown option exits 1" {
    doppler_seed "TEST_API_KEY" "${KEY_A}"
    doppler_seed "TEST_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=doppler \
        KEY_ROTATE_DOPPLER_PROJECT=mock KEY_ROTATE_DOPPLER_CONFIG=mock \
        bash "$SCRIPT" test --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "--add without key argument exits 1" {
    doppler_seed "TEST_API_KEY" "${KEY_A}"
    doppler_seed "TEST_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" test --add
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: mcp-key-rotate"* ]]
}

# ==========================================================================
# UNIT TESTS: Key masking
# ==========================================================================

@test "status masks long keys as first6...last4" {
    doppler_seed "FAKE_API_KEY" "${KEY_A}"
    doppler_seed "FAKE_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" fake --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-k...1111"* ]]
}

@test "status masks short keys (< 12 chars) as first3***" {
    doppler_seed "TINY_API_KEY" "${SHORT_KEY}"
    doppler_seed "TINY_API_KEY_POOL" "${SHORT_KEY}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" tiny --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"abc***"* ]]
}

# ==========================================================================
# UNIT TESTS: Service name normalization
# ==========================================================================

@test "service name is case-insensitive (brave == BRAVE)" {
    doppler_seed "BRAVE_API_KEY" "${KEY_A}"
    doppler_seed "BRAVE_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" brave --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Service: brave"* ]]
    [[ "$output" == *"Pool: 2 keys"* ]]
}

@test "mixed case service name works (Tavily)" {
    doppler_seed "TAVILY_API_KEY" "${KEY_A}"
    doppler_seed "TAVILY_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" Tavily --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Service: Tavily"* ]]
}

# ==========================================================================
# DOPPLER BACKEND: Status
# ==========================================================================

@test "doppler: --status shows pool with active marker" {
    doppler_seed "MYSERVICE_API_KEY" "${KEY_B}"
    doppler_seed "MYSERVICE_API_KEY_POOL" "${KEY_A},${KEY_B},${KEY_C}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" myservice --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"backend: doppler"* ]]
    [[ "$output" == *"Pool: 3 keys"* ]]
    [[ "$output" == *"> [2]"* ]]
}

@test "doppler: --status with empty pool exits 1" {
    doppler_seed "EMPTY_API_KEY" "${KEY_A}"
    doppler_seed "EMPTY_API_KEY_POOL" ""
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" empty --status
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pool found"* ]]
}

# ==========================================================================
# DOPPLER BACKEND: Rotate
# ==========================================================================

@test "doppler: rotate advances to next key" {
    doppler_seed "SVC_API_KEY" "${KEY_A}"
    doppler_seed "SVC_API_KEY_POOL" "${KEY_A},${KEY_B},${KEY_C}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" svc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated svc"* ]]

    # Verify the active key changed
    local new_key
    new_key="$(doppler_read "SVC_API_KEY")"
    [ "${new_key}" = "${KEY_B}" ]
}

@test "doppler: rotate wraps around from last to first" {
    doppler_seed "SVC_API_KEY" "${KEY_C}"
    doppler_seed "SVC_API_KEY_POOL" "${KEY_A},${KEY_B},${KEY_C}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" svc
    [ "$status" -eq 0 ]
    [[ "$output" == *"key [1] of 3"* ]]

    local new_key
    new_key="$(doppler_read "SVC_API_KEY")"
    [ "${new_key}" = "${KEY_A}" ]
}

@test "doppler: rotate with single key exits 1" {
    doppler_seed "SOLO_API_KEY" "${KEY_A}"
    doppler_seed "SOLO_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" solo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Only 1 key"* ]]
}

@test "doppler: rotate when current key not in pool advances to index 0" {
    doppler_seed "DRIFT_API_KEY" "unknown-key-not-in-pool"
    doppler_seed "DRIFT_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" drift
    [ "$status" -eq 0 ]

    # current_idx=-1, next=((-1+1)%2)=0 → KEY_A
    local new_key
    new_key="$(doppler_read "DRIFT_API_KEY")"
    [ "${new_key}" = "${KEY_A}" ]
}

# ==========================================================================
# DOPPLER BACKEND: Add
# ==========================================================================

@test "doppler: --add appends key to pool" {
    doppler_seed "ADD_API_KEY" "${KEY_A}"
    doppler_seed "ADD_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" add --add "${KEY_B}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added"* ]]
    [[ "$output" == *"2 keys"* ]]

    local pool
    pool="$(doppler_read "ADD_API_KEY_POOL")"
    [ "${pool}" = "${KEY_A},${KEY_B}" ]
}

@test "doppler: --add rejects duplicate key" {
    doppler_seed "DUP_API_KEY" "${KEY_A}"
    doppler_seed "DUP_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" dup --add "${KEY_A}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already in"* ]]
}

@test "doppler: --add initializes empty pool" {
    # Pool exists but is empty
    doppler_seed "NEW_API_KEY" ""
    doppler_seed "NEW_API_KEY_POOL" ""
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" new --add "${KEY_A}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Initialized"* ]]

    local pool
    pool="$(doppler_read "NEW_API_KEY_POOL")"
    [ "${pool}" = "${KEY_A}" ]
    local active
    active="$(doppler_read "NEW_API_KEY")"
    [ "${active}" = "${KEY_A}" ]
}

# ==========================================================================
# DOTENV BACKEND: Status
# ==========================================================================

@test "dotenv: --status reads from .env file" {
    dotenv_seed "MYTEST_API_KEY" "${KEY_A}"
    dotenv_seed "MYTEST_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" mytest --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"backend: dotenv"* ]]
    [[ "$output" == *"Pool: 2 keys"* ]]
    [[ "$output" == *"> [1]"* ]]
}

@test "dotenv: --status with missing pool exits 1" {
    dotenv_seed "NOPOOL_API_KEY" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" nopool --status
    [ "$status" -eq 1 ]
    [[ "$output" == *"No pool found"* ]]
}

# ==========================================================================
# DOTENV BACKEND: Rotate
# ==========================================================================

@test "dotenv: rotate updates .env file in place" {
    dotenv_seed "DOT_API_KEY" "${KEY_A}"
    dotenv_seed "DOT_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" dot
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated dot"* ]]

    # Verify .env was updated
    local new_key
    new_key="$(grep "^DOT_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${new_key}" = "${KEY_B}" ]
}

@test "dotenv: rotate wraps around" {
    dotenv_seed "WRAP_API_KEY" "${KEY_B}"
    dotenv_seed "WRAP_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" wrap
    [ "$status" -eq 0 ]
    [[ "$output" == *"key [1] of 2"* ]]

    local new_key
    new_key="$(grep "^WRAP_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${new_key}" = "${KEY_A}" ]
}

@test "dotenv: rotate preserves other .env entries" {
    dotenv_seed "UNRELATED_VAR" "keep-this"
    dotenv_seed "ROT_API_KEY" "${KEY_A}"
    dotenv_seed "ROT_API_KEY_POOL" "${KEY_A},${KEY_B}"
    dotenv_seed "ANOTHER_VAR" "also-keep"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" rot
    [ "$status" -eq 0 ]

    # Other vars intact
    grep -q "^UNRELATED_VAR=keep-this" "${TEST_DOTENV}"
    grep -q "^ANOTHER_VAR=also-keep" "${TEST_DOTENV}"
}

@test "dotenv: single key pool exits 1" {
    dotenv_seed "SINGLE_API_KEY" "${KEY_A}"
    dotenv_seed "SINGLE_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" single
    [ "$status" -eq 1 ]
    [[ "$output" == *"Only 1 key"* ]]
}

# ==========================================================================
# DOTENV BACKEND: Add
# ==========================================================================

@test "dotenv: --add appends to pool in .env" {
    dotenv_seed "DADD_API_KEY" "${KEY_A}"
    dotenv_seed "DADD_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" dadd --add "${KEY_B}"
    [ "$status" -eq 0 ]

    local pool
    pool="$(grep "^DADD_API_KEY_POOL=" "${TEST_DOTENV}" | tail -1 | cut -d'=' -f2-)"
    [ "${pool}" = "${KEY_A},${KEY_B}" ]
}

@test "dotenv: --add rejects duplicate" {
    dotenv_seed "DDUP_API_KEY" "${KEY_A}"
    dotenv_seed "DDUP_API_KEY_POOL" "${KEY_A},${KEY_B}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" ddup --add "${KEY_A}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already in"* ]]
}

@test "dotenv: --add creates .env entries when pool is missing" {
    # Empty .env, no pool var at all
    touch "${TEST_DOTENV}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" fresh --add "${KEY_A}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Initialized"* ]]

    grep -q "^FRESH_API_KEY_POOL=${KEY_A}" "${TEST_DOTENV}"
    grep -q "^FRESH_API_KEY=${KEY_A}" "${TEST_DOTENV}"
}

# ==========================================================================
# DOTENV BACKEND: Special characters in keys
# ==========================================================================

@test "dotenv: rotate handles keys with pipes and slashes" {
    local special_a="key|with/pipes+slashes=and_equals"
    local special_b="another|key/here"
    dotenv_seed "SPECIAL_API_KEY" "${special_a}"
    dotenv_seed "SPECIAL_API_KEY_POOL" "${special_a},${special_b}"
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" special
    [ "$status" -eq 0 ]

    local new_key
    new_key="$(grep "^SPECIAL_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${new_key}" = "${special_b}" ]
}

# ==========================================================================
# DOTENV BACKEND: Environment variable fallback
# ==========================================================================

@test "dotenv: reads pool from environment when not in .env" {
    touch "${TEST_DOTENV}"
    dotenv_seed "ENVONLY_API_KEY" "${KEY_A}"
    # Pool is in environment, not in .env
    run env ENVONLY_API_KEY_POOL="${KEY_A},${KEY_B}" \
        KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" envonly --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pool: 2 keys"* ]]
}

# ==========================================================================
# BACKEND DETECTION
# ==========================================================================

@test "backend override: KEY_ROTATE_BACKEND=dotenv forces dotenv" {
    dotenv_seed "FORCE_API_KEY" "${KEY_A}"
    dotenv_seed "FORCE_API_KEY_POOL" "${KEY_A},${KEY_B}"
    # Even though mock doppler is in PATH, dotenv is forced
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" force --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"backend: dotenv"* ]]
}

@test "backend detection: fails gracefully when no backend available" {
    # Remove mock doppler from PATH, no .env file
    run env -i PATH="/usr/bin:/bin" HOME="${TEST_TMPDIR}" \
        KEY_ROTATE_BACKEND=auto KEY_ROTATE_DOTENV="${TEST_TMPDIR}/nonexistent.env" \
        bash "$SCRIPT" ghost --status
    [ "$status" -eq 1 ]
    [[ "$output" == *"No backend available"* ]]
}

# ==========================================================================
# INTEGRATION: Full rotation cycle (dotenv)
# ==========================================================================

@test "integration: full add-rotate-rotate-rotate cycle with dotenv" {
    touch "${TEST_DOTENV}"

    # Initialize with first key
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" integ --add "${KEY_A}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Initialized"* ]]

    # Add second key
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" integ --add "${KEY_B}"
    [ "$status" -eq 0 ]

    # Add third key
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" integ --add "${KEY_C}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 keys"* ]]

    # Status shows 3 keys, A is active
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" integ --status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pool: 3 keys"* ]]
    [[ "$output" == *"> [1]"* ]]

    # Rotate A -> B
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" integ
    [ "$status" -eq 0 ]
    local key
    key="$(grep "^INTEG_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${key}" = "${KEY_B}" ]

    # Rotate B -> C
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" integ
    [ "$status" -eq 0 ]
    key="$(grep "^INTEG_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${key}" = "${KEY_C}" ]

    # Rotate C -> A (wrap around)
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" integ
    [ "$status" -eq 0 ]
    key="$(grep "^INTEG_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${key}" = "${KEY_A}" ]
}

# ==========================================================================
# INTEGRATION: Multiple services in same .env
# ==========================================================================

@test "integration: two services coexist in same .env without interference" {
    dotenv_seed "BRAVE_API_KEY" "${KEY_A}"
    dotenv_seed "BRAVE_API_KEY_POOL" "${KEY_A},${KEY_B}"
    dotenv_seed "TAVILY_API_KEY" "${KEY_C}"
    dotenv_seed "TAVILY_API_KEY_POOL" "${KEY_C},${KEY_A}"

    # Rotate brave: A -> B
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" brave
    [ "$status" -eq 0 ]

    # Verify brave changed
    local brave_key
    brave_key="$(grep "^BRAVE_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${brave_key}" = "${KEY_B}" ]

    # Verify tavily untouched
    local tavily_key
    tavily_key="$(grep "^TAVILY_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${tavily_key}" = "${KEY_C}" ]

    # Now rotate tavily: C -> A
    run env KEY_ROTATE_BACKEND=dotenv KEY_ROTATE_DOTENV="${TEST_DOTENV}" \
        bash "$SCRIPT" tavily
    [ "$status" -eq 0 ]

    # Both updated independently
    brave_key="$(grep "^BRAVE_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${brave_key}" = "${KEY_B}" ]
    tavily_key="$(grep "^TAVILY_API_KEY=" "${TEST_DOTENV}" | head -1 | cut -d'=' -f2-)"
    [ "${tavily_key}" = "${KEY_A}" ]
}

# ==========================================================================
# INTEGRATION: Full cycle with doppler mock
# ==========================================================================

@test "integration: full rotate cycle with doppler backend" {
    doppler_seed "MOCK_API_KEY" "${KEY_A}"
    doppler_seed "MOCK_API_KEY_POOL" "${KEY_A},${KEY_B},${KEY_C}"

    # Rotate A -> B
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" mock
    [ "$status" -eq 0 ]
    [ "$(doppler_read "MOCK_API_KEY")" = "${KEY_B}" ]

    # Rotate B -> C
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" mock
    [ "$status" -eq 0 ]
    [ "$(doppler_read "MOCK_API_KEY")" = "${KEY_C}" ]

    # Rotate C -> A (wrap)
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" mock
    [ "$status" -eq 0 ]
    [ "$(doppler_read "MOCK_API_KEY")" = "${KEY_A}" ]
}

# ==========================================================================
# QUOTA: Tavily (mock curl)
# ==========================================================================

# Helper: create a mock curl that returns Tavily usage JSON
create_tavily_curl_mock() {
    local used="$1" limit="$2"
    local mock_curl="${TEST_TMPDIR}/curl"
    cat > "${mock_curl}" <<CURL_EOF
#!/usr/bin/env bash
# Mock curl for Tavily /usage endpoint
# Returns usage JSON + http code on last line (simulating -w "%{http_code}")
echo '{"key":{"usage":${used},"limit":${limit},"search_usage":${used},"extract_usage":0,"crawl_usage":0,"map_usage":0,"research_usage":0},"account":{"current_plan":"free","plan_usage":${used},"plan_limit":${limit},"paygo_usage":0,"paygo_limit":0,"search_usage":${used},"extract_usage":0,"crawl_usage":0,"map_usage":0,"research_usage":0}}'
echo "200"
CURL_EOF
    chmod +x "${mock_curl}"
}

@test "quota: tavily shows per-key usage" {
    doppler_seed "TAVILY_API_KEY" "${KEY_A}"
    doppler_seed "TAVILY_API_KEY_POOL" "${KEY_A},${KEY_B}"
    create_tavily_curl_mock 150 1000
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${TEST_TMPDIR}/cache" \
        bash "$SCRIPT" tavily --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"150/1000 used"* ]]
    [[ "$output" == *"850 remaining"* ]]
}

@test "quota: tavily shows zero usage for fresh key" {
    doppler_seed "TAVILY_API_KEY" "${KEY_A}"
    doppler_seed "TAVILY_API_KEY_POOL" "${KEY_A}"
    create_tavily_curl_mock 0 1000
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${TEST_TMPDIR}/cache" \
        bash "$SCRIPT" tavily --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"0/1000 used"* ]]
    [[ "$output" == *"1000 remaining"* ]]
}

@test "quota: tavily handles API error gracefully" {
    doppler_seed "TAVILY_API_KEY" "${KEY_A}"
    doppler_seed "TAVILY_API_KEY_POOL" "${KEY_A}"
    # Create a mock curl that returns 401
    local mock_curl="${TEST_TMPDIR}/curl"
    cat > "${mock_curl}" <<'CURL_EOF'
#!/usr/bin/env bash
echo '{"error":"unauthorized"}'
echo "401"
CURL_EOF
    chmod +x "${mock_curl}"
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${TEST_TMPDIR}/cache" \
        bash "$SCRIPT" tavily --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"HTTP 401"* ]]
}

@test "quota: tavily uses cache on second call" {
    doppler_seed "TAVILY_API_KEY" "${KEY_A}"
    doppler_seed "TAVILY_API_KEY_POOL" "${KEY_A}"
    create_tavily_curl_mock 100 1000
    local cache_dir="${TEST_TMPDIR}/cache"

    # First call — populates cache
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${cache_dir}" \
        bash "$SCRIPT" tavily --quota
    [ "$status" -eq 0 ]

    # Replace mock with one that returns different data
    create_tavily_curl_mock 999 1000

    # Second call — should still show cached data (100, not 999)
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${cache_dir}" \
        bash "$SCRIPT" tavily --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"100/1000 used"* ]]
}

@test "quota: cache expires after TTL" {
    doppler_seed "TAVILY_API_KEY" "${KEY_A}"
    doppler_seed "TAVILY_API_KEY_POOL" "${KEY_A}"
    create_tavily_curl_mock 100 1000
    local cache_dir="${TEST_TMPDIR}/cache"

    # First call
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${cache_dir}" \
        MCP_KEY_ROTATE_CACHE_TTL=0 \
        bash "$SCRIPT" tavily --quota
    [ "$status" -eq 0 ]

    # Replace mock with updated data
    create_tavily_curl_mock 200 1000

    # With TTL=0, cache is always expired → should fetch fresh
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${cache_dir}" \
        MCP_KEY_ROTATE_CACHE_TTL=0 \
        bash "$SCRIPT" tavily --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"200/1000 used"* ]]
}

# ==========================================================================
# QUOTA: Brave (mock curl)
# ==========================================================================

# Helper: create a mock curl that returns Brave rate limit headers
create_brave_curl_mock() {
    local remaining="$1" limit="$2" reset="$3"
    local mock_curl="${TEST_TMPDIR}/curl"
    cat > "${mock_curl}" <<CURL_EOF
#!/usr/bin/env bash
# Mock curl for Brave Search API (returns headers via -D -)
echo "HTTP/2 200"
echo "x-ratelimit-limit: 1, ${limit}"
echo "x-ratelimit-remaining: 1, ${remaining}"
echo "x-ratelimit-reset: 1, ${reset}"
echo ""
CURL_EOF
    chmod +x "${mock_curl}"
}

@test "quota: brave shows per-key usage from headers" {
    doppler_seed "BRAVE_API_KEY" "${KEY_A}"
    doppler_seed "BRAVE_API_KEY_POOL" "${KEY_A}"
    create_brave_curl_mock 1500 2000 86400
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${TEST_TMPDIR}/cache" \
        bash "$SCRIPT" brave --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"500/2000 used"* ]]
    [[ "$output" == *"1500 remaining"* ]]
}

@test "quota: brave shows exhausted key" {
    doppler_seed "BRAVE_API_KEY" "${KEY_A}"
    doppler_seed "BRAVE_API_KEY_POOL" "${KEY_A}"
    create_brave_curl_mock 0 2000 43200
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${TEST_TMPDIR}/cache" \
        bash "$SCRIPT" brave --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"2000/2000 used"* ]]
    [[ "$output" == *"0 remaining"* ]]
    [[ "$output" == *"resets in"* ]]
}

@test "quota: brave handles missing headers gracefully" {
    doppler_seed "BRAVE_API_KEY" "${KEY_A}"
    doppler_seed "BRAVE_API_KEY_POOL" "${KEY_A}"
    # Create a mock curl that returns no rate limit headers
    local mock_curl="${TEST_TMPDIR}/curl"
    cat > "${mock_curl}" <<'CURL_EOF'
#!/usr/bin/env bash
echo "HTTP/2 500"
echo ""
CURL_EOF
    chmod +x "${mock_curl}"
    run env KEY_ROTATE_BACKEND=doppler \
        CURL_CMD="${TEST_TMPDIR}/curl" \
        MCP_KEY_ROTATE_CACHE_DIR="${TEST_TMPDIR}/cache" \
        bash "$SCRIPT" brave --quota
    [ "$status" -eq 0 ]
    [[ "$output" == *"no rate limit headers"* ]]
}

# ==========================================================================
# QUOTA: Unsupported service
# ==========================================================================

@test "quota: unsupported service exits 1" {
    doppler_seed "CUSTOM_API_KEY" "${KEY_A}"
    doppler_seed "CUSTOM_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" custom --quota
    [ "$status" -eq 1 ]
    [[ "$output" == *"No quota provider"* ]]
}

# ==========================================================================
# INTEGRATION: Option E — skill, CLAUDE.md, setup.sh
# ==========================================================================

REPO_ROOT="$BATS_TEST_DIRNAME/.."

@test "option-e: skill file exists" {
    [ -f "${REPO_ROOT}/.claude/skills/mcp-key-rotate/SKILL.md" ]
}

@test "option-e: skill references mcp-key-rotate script" {
    grep -q "mcp-key-rotate" "${REPO_ROOT}/.claude/skills/mcp-key-rotate/SKILL.md"
}

@test "option-e: skill documents --quota flag" {
    grep -q "\-\-quota" "${REPO_ROOT}/.claude/skills/mcp-key-rotate/SKILL.md"
}

@test "option-e: skill documents restart requirement" {
    grep -qi "restart" "${REPO_ROOT}/.claude/skills/mcp-key-rotate/SKILL.md"
}

@test "option-e: CLAUDE.md has 429 handling instructions" {
    grep -q "429" "${REPO_ROOT}/CLAUDE.md"
    grep -q "mcp-key-rotate" "${REPO_ROOT}/CLAUDE.md"
}

@test "option-e: CLAUDE.md mentions restart after rotation" {
    grep -qi "restart claude code" "${REPO_ROOT}/CLAUDE.md"
}

@test "option-e: CLAUDE.md lists /mcp-key-rotate command" {
    grep -q "/mcp-key-rotate" "${REPO_ROOT}/CLAUDE.md"
}

@test "option-e: CLAUDE.md mentions web-search as 429 fallback" {
    grep -q "web-search.*fallback" "${REPO_ROOT}/CLAUDE.md"
}

@test "option-e: setup.sh installs mcp-key-rotate to ~/.local/bin" {
    grep -q "mcp-key-rotate" "${REPO_ROOT}/setup.sh"
    grep -q "local/bin" "${REPO_ROOT}/setup.sh"
}

@test "option-e: bin/mcp-key-rotate is executable" {
    [ -x "${REPO_ROOT}/bin/mcp-key-rotate" ]
}

@test "option-e: help output lists all subcommands" {
    doppler_seed "BRAVE_API_KEY" "${KEY_A}"
    doppler_seed "BRAVE_API_KEY_POOL" "${KEY_A}"
    run env KEY_ROTATE_BACKEND=doppler \
        bash "$SCRIPT" brave --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--status"* ]]
    [[ "$output" == *"--quota"* ]]
    [[ "$output" == *"--add"* ]]
    [[ "$output" == *"--help"* ]]
}
