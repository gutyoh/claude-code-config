#!/usr/bin/env bats
# proxy-start-codex.bats
# Path: tests/proxy-start-codex.bats
#
# Integration tests for bin/proxy-start-codex.sh. Each test runs the real
# script in dry-run mode against an isolated sandbox (fake CLI_PROXY_DIR,
# fake ~/.codex/auth.json, per-test CLI_PROXY_AUTH_DIR). No real CLIProxyAPI
# binary is built or started.
#
# Run: bats tests/proxy-start-codex.bats
#      make test

SCRIPT="$BATS_TEST_DIRNAME/../bin/proxy-start-codex.sh"

# Sample Codex CLI auth.json shape — matches what `codex login` writes.
SAMPLE_CODEX_AUTH_JSON='{
    "last_refresh": "2026-04-19T12:00:00.000000Z",
    "tokens": {
        "access_token": "sk-source-access-AAAA",
        "refresh_token": "sk-source-refresh-BBBB",
        "id_token": "eyJ-id-token-CCCC",
        "account_id": "acct-source-1234"
    }
}'

# Counterpart — imagine CLIProxyAPI auto-refreshed the token and wrote it
# back. This is what must NOT be overwritten on a re-run.
REFRESHED_IMPORT_JSON='{
    "type": "codex",
    "access_token": "sk-REFRESHED-access-ZZZZ",
    "refresh_token": "sk-REFRESHED-refresh-YYYY",
    "id_token": "eyJ-REFRESHED-id-token",
    "account_id": "acct-source-1234",
    "last_refresh": "2026-04-19T18:00:00.000000Z",
    "email": "chatgpt"
}'

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq required"

    SANDBOX="$(mktemp -d)"
    export SANDBOX

    # File the port-preflight test writes its listener PID to, so teardown
    # can kill it even if the test body crashes.
    LISTENER_PID_FILE="${SANDBOX}/listener.pid"
    export LISTENER_PID_FILE

    # Fake CLIProxyAPI repo dir (just needs to exist and be `cd`-able)
    export CLI_PROXY_DIR="${SANDBOX}/cli-proxy-api-repo"
    mkdir -p "$CLI_PROXY_DIR"
    # A stub binary so ensure_binary_current (if run) finds something
    echo '#!/usr/bin/env bash' >"$CLI_PROXY_DIR/cli-proxy-api"
    chmod +x "$CLI_PROXY_DIR/cli-proxy-api"

    # Fake Codex auth source
    export CODEX_AUTH_JSON="${SANDBOX}/codex-auth.json"
    echo "$SAMPLE_CODEX_AUTH_JSON" >"$CODEX_AUTH_JSON"

    # Isolated auth-dir (so we never touch ~/.cli-proxy-api)
    export CLI_PROXY_AUTH_DIR="${SANDBOX}/cli-proxy-auth"

    # Dry-run so we never exec cli-proxy-api or run `go build`
    export PROXY_START_CODEX_DRY_RUN=1
    export PROXY_START_CODEX_SKIP_BINARY_CHECK=1

    # Fresh port to avoid colliding with the real dev proxy
    export PORT="27317"
    export HOST="127.0.0.1"
    export API_KEY="sk-test-dummy"
}

teardown() {
    # Force-kill any listener leaked by the port-preflight test so bats can
    # exit cleanly even if a test body crashed before its inline cleanup ran.
    if [[ -f "${LISTENER_PID_FILE:-}" ]]; then
        local lpid
        lpid=$(cat "$LISTENER_PID_FILE" 2>/dev/null || true)
        if [[ -n "$lpid" ]]; then
            kill -KILL "$lpid" 2>/dev/null || true
        fi
    fi
    rm -rf "$SANDBOX"
}

# --- Helpers ---

# Expected config file that the script writes inside CLI_PROXY_DIR
config_file() {
    echo "${CLI_PROXY_DIR}/config.local.yaml"
}

# Expected import file in the isolated auth-dir
import_file() {
    echo "${CLI_PROXY_AUTH_DIR}/codex-import.json"
}

# ============================================================================
# Codex auth import behavior (OpenAI CI/CD guidance: seed only if missing)
# ============================================================================

@test "first run: creates codex-import.json from source auth.json" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    local imp
    imp="$(import_file)"
    [ -f "$imp" ]

    # Verify content matches source
    local access
    access=$(jq -r '.access_token' "$imp")
    [ "$access" = "sk-source-access-AAAA" ]

    # Verify type tag applied
    local type
    type=$(jq -r '.type' "$imp")
    [ "$type" = "codex" ]

    # Verify email constant applied
    local email
    email=$(jq -r '.email' "$imp")
    [ "$email" = "chatgpt" ]
}

@test "second run: does NOT overwrite an already-imported codex-import.json" {
    # First run creates import
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # Simulate CLIProxyAPI refreshing the token and writing back
    echo "$REFRESHED_IMPORT_JSON" >"$(import_file)"

    # Change the source to a DIFFERENT content to prove we're not re-copying
    local stale_source='{"last_refresh":"2020-01-01T00:00:00Z","tokens":{"access_token":"sk-STALE","refresh_token":"r","id_token":"i","account_id":"a"}}'
    echo "$stale_source" >"$CODEX_AUTH_JSON"

    # Second run
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # Assert the refreshed token is intact
    local access
    access=$(jq -r '.access_token' "$(import_file)")
    [ "$access" = "sk-REFRESHED-access-ZZZZ" ]
}

@test "CODEX_FORCE_REIMPORT=1 overwrites an existing codex-import.json" {
    # Put a refreshed token in place
    mkdir -p "$CLI_PROXY_AUTH_DIR"
    echo "$REFRESHED_IMPORT_JSON" >"$(import_file)"

    # Source has a different access token
    local new_source='{"last_refresh":"2026-04-20T00:00:00Z","tokens":{"access_token":"sk-NEW-LOGIN","refresh_token":"r","id_token":"i","account_id":"a"}}'
    echo "$new_source" >"$CODEX_AUTH_JSON"

    CODEX_FORCE_REIMPORT=1 run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    local access
    access=$(jq -r '.access_token' "$(import_file)")
    [ "$access" = "sk-NEW-LOGIN" ]

    # Stderr should tell the user what happened
    [[ "$output" == *"CODEX_FORCE_REIMPORT=1"* ]]
}

@test "codex-import.json has 0600 permissions" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local mode
    # stat -f on macOS, stat -c on Linux
    if [[ "$(uname -s)" == "Darwin" ]]; then
        mode=$(stat -f "%Lp" "$(import_file)")
    else
        mode=$(stat -c "%a" "$(import_file)")
    fi
    [ "$mode" = "600" ]
}

# ============================================================================
# config.local.yaml behavior (write only if missing)
# ============================================================================

@test "first run: creates config.local.yaml" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$(config_file)" ]
}

@test "first run: config.local.yaml contains env var values" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    local cf
    cf="$(config_file)"
    grep -q "host: \"127.0.0.1\"" "$cf"
    grep -q "port: 27317" "$cf"
    grep -q "sk-test-dummy" "$cf"
}

@test "second run: does NOT overwrite hand-edited config.local.yaml" {
    # First run
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # Simulate the user hand-editing the config
    local cf
    cf="$(config_file)"
    {
        echo "# MY MANUAL EDITS"
        echo "request-retry: 5"
        echo "disable-cooling: true"
    } >>"$cf"

    # Second run (change env to prove we're NOT regenerating)
    PORT="99999" API_KEY="different-key" run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # Manual edits must persist
    grep -q "MY MANUAL EDITS" "$cf"
    grep -q "request-retry: 5" "$cf"
    grep -q "disable-cooling: true" "$cf"

    # Original env values must persist (not regenerated)
    grep -q "port: 27317" "$cf"
    grep -q "sk-test-dummy" "$cf"
}

@test "deleting config.local.yaml triggers fresh regeneration" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    local cf
    cf="$(config_file)"
    [ -f "$cf" ]

    rm -f "$cf"

    PORT="33333" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -f "$cf" ]
    grep -q "port: 33333" "$cf"
}

# ============================================================================
# Port collision preflight
# ============================================================================

@test "port preflight: exits 1 when PORT is already listening" {
    command -v lsof >/dev/null 2>&1 || skip "lsof not installed"

    # Find a free ephemeral port, then start a listener on it that stays up
    # for the duration of the test. We use python's http.server as a reliable
    # cross-platform listener.
    local busy_port=28801
    while lsof -iTCP:"$busy_port" -sTCP:LISTEN -Pn 2>/dev/null | grep -q LISTEN; do
        busy_port=$((busy_port + 1))
    done

    # Start a listener in the background, record its PID where teardown()
    # can find it and force-kill even on test-body failure.
    "${_PY}" -m http.server "$busy_port" --bind 127.0.0.1 >/dev/null 2>&1 &
    local listener_pid=$!
    echo "$listener_pid" >"$LISTENER_PID_FILE"

    # Poll briefly for the listener to bind (faster than a fixed sleep)
    local tries=0
    while [ "$tries" -lt 20 ]; do
        if lsof -iTCP:"$busy_port" -sTCP:LISTEN -Pn 2>/dev/null | grep -q LISTEN; then
            break
        fi
        sleep 0.1
        tries=$((tries + 1))
    done

    if ! lsof -iTCP:"$busy_port" -sTCP:LISTEN -Pn 2>/dev/null | grep -q LISTEN; then
        kill -KILL "$listener_pid" 2>/dev/null || true
        skip "could not start test listener on $busy_port"
    fi

    # Run script targeting the busy port
    PORT="$busy_port" run bash "$SCRIPT"

    # Kill the listener NOW (teardown is a safety net)
    kill -KILL "$listener_pid" 2>/dev/null || true

    [ "$status" -eq 1 ]
    [[ "$output" == *"port ${busy_port} is already in use"* ]]
}

@test "port preflight: passes when PORT is free" {
    command -v lsof >/dev/null 2>&1 || skip "lsof not installed"

    # Find a free port (27317 from setup(), but double-check)
    local free_port=27317
    while lsof -iTCP:"$free_port" -sTCP:LISTEN -Pn 2>/dev/null | grep -q LISTEN; do
        free_port=$((free_port + 1))
    done

    PORT="$free_port" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

# ============================================================================
# Input validation
# ============================================================================

@test "missing CODEX_AUTH_JSON source exits 1 with helpful message" {
    rm -f "$CODEX_AUTH_JSON"
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Not found"* ]]
    [[ "$output" == *"Codex CLI"* ]]
}

@test "missing CLI_PROXY_DIR exits 1 with clone instruction" {
    rm -rf "$CLI_PROXY_DIR"
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Not found"* ]]
    [[ "$output" == *"git clone"* ]]
}

# ============================================================================
# Dry-run + env var plumbing
# ============================================================================

@test "dry-run: prints env var instructions to stdout" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ANTHROPIC_BASE_URL=http://127.0.0.1:27317"* ]]
    [[ "$output" == *"ANTHROPIC_DEFAULT_OPUS_MODEL"* ]]
    [[ "$output" == *"claude"* ]]
}

@test "dry-run: does NOT exec cli-proxy-api" {
    # If dry-run were broken, this test would hang or time out because
    # cli-proxy-api would try to listen on the port.
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
}

@test "custom MODEL env is used in output instructions" {
    MODEL='gpt-5.2-codex(medium)' run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gpt-5.2-codex(medium)"* ]]
}
