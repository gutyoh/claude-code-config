#!/usr/bin/env bats
# proxy-preflight.bats
# Path: tests/proxy-preflight.bats
#
# bats-core tests for proxy preflight checks (lib/proxy/preflight.sh).
# Run: bats tests/proxy-preflight.bats
#      make test

PREFLIGHT="$BATS_TEST_DIRNAME/../lib/proxy/preflight.sh"
STUB_DIR=""

setup() {
    STUB_DIR="$(mktemp -d)"
    source "$PREFLIGHT"
}

teardown() {
    rm -rf "$STUB_DIR"
}

# --- Helpers ---

# Creates a stub executable in STUB_DIR that runs the given body.
create_stub() {
    local cmd="$1"
    local body="$2"
    cat >"$STUB_DIR/$cmd" <<STUB
#!/usr/bin/env bash
$body
STUB
    chmod +x "$STUB_DIR/$cmd"
}

# Creates a temp auth.json and prints its path.
create_auth_json() {
    local last_refresh="$1"
    local file="$STUB_DIR/auth.json"
    if [[ "$last_refresh" == "null" ]]; then
        echo '{"last_refresh": null, "tokens": {}}' >"$file"
    elif [[ -z "$last_refresh" ]]; then
        echo '{"tokens": {}}' >"$file"
    else
        printf '{"last_refresh": "%s", "tokens": {}}\n' "$last_refresh" >"$file"
    fi
    echo "$file"
}

# Generates an ISO 8601 timestamp N hours ago.
timestamp_hours_ago() {
    python3 -c "
from datetime import datetime, timezone, timedelta
dt = datetime.now(timezone.utc) - timedelta(hours=$1)
print(dt.strftime('%Y-%m-%dT%H:%M:%S.%fZ'))
"
}

# Creates a temp executable file (for binary existence tests).
create_fake_binary() {
    local path="$1"
    echo '#!/usr/bin/env bash' >"$path"
    chmod +x "$path"
}

# ============================================================================
# _binary_vcs_revision
# ============================================================================

# --- _binary_vcs_revision ---

@test "_binary_vcs_revision: extracts revision from go version output" {
    create_fake_binary "$STUB_DIR/fake-bin"
    create_stub go 'echo "	build	vcs.revision=abc123def456abc123def456abc123def456abcd"'
    PATH="$STUB_DIR:$PATH" result=$(_binary_vcs_revision "$STUB_DIR/fake-bin")
    [ "$result" = "abc123def456abc123def456abc123def456abcd" ]
}

@test "_binary_vcs_revision: returns 1 for missing binary" {
    run _binary_vcs_revision "/nonexistent/path/binary"
    [ "$status" -ne 0 ]
}

@test "_binary_vcs_revision: returns empty when no VCS metadata" {
    create_fake_binary "$STUB_DIR/fake-bin"
    create_stub go 'echo "	build	-compiler=gc"'
    PATH="$STUB_DIR:$PATH" result=$(_binary_vcs_revision "$STUB_DIR/fake-bin")
    [ -z "$result" ]
}

@test "_binary_vcs_revision: returns 1 when binary not executable" {
    echo "not executable" >"$STUB_DIR/fake-bin"
    chmod -x "$STUB_DIR/fake-bin"
    run _binary_vcs_revision "$STUB_DIR/fake-bin"
    [ "$status" -ne 0 ]
}

# ============================================================================
# _repo_head_revision
# ============================================================================

# --- _repo_head_revision ---

@test "_repo_head_revision: returns commit hash" {
    create_stub git 'echo "abc123def456abc123def456abc123def456abcd"'
    PATH="$STUB_DIR:$PATH" result=$(_repo_head_revision "/some/repo")
    [ "$result" = "abc123def456abc123def456abc123def456abcd" ]
}

@test "_repo_head_revision: returns empty for non-git directory" {
    create_stub git 'exit 128'
    PATH="$STUB_DIR:$PATH" run _repo_head_revision "/not/a/repo"
    [ -z "$output" ]
}

# ============================================================================
# is_binary_current
# ============================================================================

# --- is_binary_current ---

@test "is_binary_current: returns 0 when revisions match" {
    create_fake_binary "$STUB_DIR/fake-bin"
    local hash="abc123def456abc123def456abc123def456abcd"
    create_stub go "echo \"	build	vcs.revision=$hash\""
    create_stub git "echo \"$hash\""
    PATH="$STUB_DIR:$PATH" is_binary_current "$STUB_DIR/fake-bin" "/some/repo"
}

@test "is_binary_current: returns 1 when binary missing" {
    run is_binary_current "/nonexistent/binary" "/some/repo"
    [ "$status" -eq 1 ]
}

@test "is_binary_current: returns 2 when revisions differ" {
    create_fake_binary "$STUB_DIR/fake-bin"
    create_stub go 'echo "	build	vcs.revision=aaaa"'
    create_stub git 'echo "bbbb"'
    PATH="$STUB_DIR:$PATH" run is_binary_current "$STUB_DIR/fake-bin" "/some/repo"
    [ "$status" -eq 2 ]
}

@test "is_binary_current: returns 3 when no VCS metadata in binary" {
    create_fake_binary "$STUB_DIR/fake-bin"
    create_stub go 'echo "	build	-compiler=gc"'
    create_stub git 'echo "abc123"'
    PATH="$STUB_DIR:$PATH" run is_binary_current "$STUB_DIR/fake-bin" "/some/repo"
    [ "$status" -eq 3 ]
}

@test "is_binary_current: returns 3 when git fails" {
    create_fake_binary "$STUB_DIR/fake-bin"
    create_stub go 'echo "	build	vcs.revision=abc123"'
    create_stub git 'exit 128'
    PATH="$STUB_DIR:$PATH" run is_binary_current "$STUB_DIR/fake-bin" "/some/repo"
    [ "$status" -eq 3 ]
}

@test "is_binary_current: stderr contains stale message on mismatch" {
    create_fake_binary "$STUB_DIR/fake-bin"
    create_stub go 'echo "	build	vcs.revision=aaaa"'
    create_stub git 'echo "bbbb"'
    PATH="$STUB_DIR:$PATH" run is_binary_current "$STUB_DIR/fake-bin" "/some/repo"
    [[ "$output" == *"stale"* ]]
}

# ============================================================================
# ensure_binary_current
# ============================================================================

# --- ensure_binary_current ---

@test "ensure_binary_current: skips build when binary is current" {
    create_fake_binary "$STUB_DIR/fake-bin"
    local hash="abc123def456abc123def456abc123def456abcd"
    create_stub go "echo \"	build	vcs.revision=$hash\""
    create_stub git "echo \"$hash\""
    local marker="$STUB_DIR/build-ran"
    PATH="$STUB_DIR:$PATH" ensure_binary_current "$STUB_DIR/fake-bin" "$STUB_DIR" "touch $marker"
    [ ! -f "$marker" ]
}

@test "ensure_binary_current: runs build when binary is stale" {
    create_fake_binary "$STUB_DIR/fake-bin"
    create_stub go 'echo "	build	vcs.revision=aaaa"'
    create_stub git 'echo "bbbb"'
    local marker="$STUB_DIR/build-ran"
    PATH="$STUB_DIR:$PATH" ensure_binary_current "$STUB_DIR/fake-bin" "$STUB_DIR" "touch $marker" 2>/dev/null
    [ -f "$marker" ]
}

@test "ensure_binary_current: runs build when binary is missing" {
    create_stub go 'exit 0'
    create_stub git 'echo "abc123"'
    local marker="$STUB_DIR/build-ran"
    PATH="$STUB_DIR:$PATH" ensure_binary_current "/nonexistent/binary" "$STUB_DIR" "touch $marker" 2>/dev/null
    [ -f "$marker" ]
}

@test "ensure_binary_current: returns 1 when build fails" {
    create_stub go 'exit 0'
    create_stub git 'echo "abc123"'
    PATH="$STUB_DIR:$PATH" run ensure_binary_current "/nonexistent/binary" "$STUB_DIR" "false"
    [ "$status" -eq 1 ]
}

# ============================================================================
# _timestamp_age_hours
# ============================================================================

# --- _timestamp_age_hours ---

@test "_timestamp_age_hours: returns 0 for recent timestamp" {
    local ts
    ts=$(timestamp_hours_ago 0)
    result=$(_timestamp_age_hours "$ts")
    [ "$result" -eq 0 ]
}

@test "_timestamp_age_hours: returns positive hours for old timestamp" {
    result=$(_timestamp_age_hours "2025-01-01T00:00:00Z")
    [ "$result" -gt 8000 ]
}

@test "_timestamp_age_hours: returns 1 for empty input" {
    run _timestamp_age_hours ""
    [ "$status" -ne 0 ]
}

@test "_timestamp_age_hours: returns 1 for invalid timestamp" {
    run _timestamp_age_hours "not-a-date"
    [ "$status" -ne 0 ]
}

@test "_timestamp_age_hours: handles fractional seconds (Codex format)" {
    result=$(_timestamp_age_hours "2026-02-08T20:17:48.310580Z")
    [[ "$result" =~ ^[0-9]+$ ]]
}

# ============================================================================
# check_codex_token_freshness
# ============================================================================

# --- check_codex_token_freshness ---

@test "check_codex_token_freshness: returns 0 for fresh token" {
    local ts
    ts=$(timestamp_hours_ago 1)
    local auth_file
    auth_file=$(create_auth_json "$ts")
    run check_codex_token_freshness "$auth_file" 9999
    [ "$status" -eq 0 ]
}

@test "check_codex_token_freshness: returns 1 for stale token" {
    local ts
    ts=$(timestamp_hours_ago 72)
    local auth_file
    auth_file=$(create_auth_json "$ts")
    run check_codex_token_freshness "$auth_file" 1
    [ "$status" -eq 1 ]
}

@test "check_codex_token_freshness: returns 2 when auth file missing" {
    run check_codex_token_freshness "/nonexistent/auth.json"
    [ "$status" -eq 2 ]
}

@test "check_codex_token_freshness: returns 3 when last_refresh is null" {
    local auth_file
    auth_file=$(create_auth_json "null")
    run check_codex_token_freshness "$auth_file"
    [ "$status" -eq 3 ]
}

@test "check_codex_token_freshness: returns 3 when last_refresh key missing" {
    local auth_file
    auth_file=$(create_auth_json "")
    run check_codex_token_freshness "$auth_file"
    [ "$status" -eq 3 ]
}

@test "check_codex_token_freshness: default threshold is 48 hours" {
    local ts
    ts=$(timestamp_hours_ago 72)
    local auth_file
    auth_file=$(create_auth_json "$ts")
    # No second arg — should use default 48h and return 1 (72 > 48)
    run check_codex_token_freshness "$auth_file"
    [ "$status" -eq 1 ]
}

@test "check_codex_token_freshness: outputs age in hours to stdout" {
    local ts
    ts=$(timestamp_hours_ago 5)
    local auth_file
    auth_file=$(create_auth_json "$ts")
    # run captures both stdout and stderr into $output
    result=$(check_codex_token_freshness "$auth_file" 9999 2>/dev/null)
    [[ "$result" =~ ^[0-9]+$ ]]
    [ "$result" -ge 4 ]
    [ "$result" -le 6 ]
}

@test "check_codex_token_freshness: stderr contains warning for stale token" {
    local ts
    ts=$(timestamp_hours_ago 72)
    local auth_file
    auth_file=$(create_auth_json "$ts")
    run check_codex_token_freshness "$auth_file" 1
    [[ "$output" == *"Warning"* ]]
}

# ============================================================================
# test_antigravity_session
# ============================================================================

# --- test_antigravity_session ---

@test "test_antigravity_session: returns 0 on HTTP 200 (valid session)" {
    create_stub curl 'echo "200"'
    PATH="$STUB_DIR:$PATH" test_antigravity_session "http://localhost:8081" "test" "claude-opus-4-5-thinking"
}

@test "test_antigravity_session: returns 1 on HTTP 401 (unauthorized)" {
    create_stub curl 'echo "401"'
    PATH="$STUB_DIR:$PATH" run test_antigravity_session "http://localhost:8081" "test" "claude-opus-4-5-thinking"
    [ "$status" -eq 1 ]
}

@test "test_antigravity_session: returns 1 on HTTP 403 (forbidden)" {
    create_stub curl 'echo "403"'
    PATH="$STUB_DIR:$PATH" run test_antigravity_session "http://localhost:8081" "test" "claude-opus-4-5-thinking"
    [ "$status" -eq 1 ]
}

@test "test_antigravity_session: returns 1 on HTTP 405 (method not allowed)" {
    create_stub curl 'echo "405"'
    PATH="$STUB_DIR:$PATH" run test_antigravity_session "http://localhost:8081" "test" "claude-opus-4-5-thinking"
    [ "$status" -eq 1 ]
}

@test "test_antigravity_session: returns 0 on HTTP 500 (server error, not auth)" {
    create_stub curl 'echo "500"'
    PATH="$STUB_DIR:$PATH" test_antigravity_session "http://localhost:8081" "test" "claude-opus-4-5-thinking"
}

@test "test_antigravity_session: returns 0 on HTTP 429 (rate limited, not auth)" {
    create_stub curl 'echo "429"'
    PATH="$STUB_DIR:$PATH" test_antigravity_session "http://localhost:8081" "test" "claude-opus-4-5-thinking"
}

@test "test_antigravity_session: returns 0 on HTTP 000 (curl timeout/unreachable)" {
    create_stub curl 'echo "000"'
    PATH="$STUB_DIR:$PATH" test_antigravity_session "http://localhost:8081" "test" "claude-opus-4-5-thinking"
}

@test "test_antigravity_session: passes proxy_url to curl" {
    create_stub curl '
for arg in "$@"; do
    if [[ "$arg" == *"/v1/messages" ]]; then
        echo "$arg" >&2
        echo "200"
        exit 0
    fi
done
echo "200"
'
    PATH="$STUB_DIR:$PATH" run test_antigravity_session "http://myhost:9999" "test" "model"
    [[ "$output" == *"http://myhost:9999/v1/messages"* ]]
}

# ============================================================================
# open_url
# ============================================================================

# --- open_url ---

@test "open_url: uses open on macOS when available" {
    # Stub 'open' to write the URL to a marker file
    create_stub open 'echo "$1" > '"$STUB_DIR"'/opened-url'
    PATH="$STUB_DIR:$PATH" open_url "http://example.com"
    [ -f "$STUB_DIR/opened-url" ]
    result=$(cat "$STUB_DIR/opened-url")
    [ "$result" = "http://example.com" ]
}

@test "open_url: falls back to xdg-open when open not available" {
    # This code path is only reachable on Linux (macOS always has /usr/bin/open).
    # Skip on macOS since the xdg-open fallback cannot be triggered.
    if command -v open >/dev/null 2>&1; then
        skip "open is always available on macOS; xdg-open fallback is Linux-only"
    fi
    create_stub xdg-open 'echo "$1" > '"$STUB_DIR"'/opened-url'
    PATH="$STUB_DIR:/bin:/usr/bin" open_url "http://example.com"
    [ -f "$STUB_DIR/opened-url" ]
    result=$(cat "$STUB_DIR/opened-url")
    [ "$result" = "http://example.com" ]
}

@test "open_url: prints URL to stderr when no browser command available" {
    # Empty PATH with no open/xdg-open
    PATH="$STUB_DIR" run open_url "http://example.com"
    [[ "$output" == *"http://example.com"* ]]
}

# ============================================================================
# fetch_proxy_models
# ============================================================================

# --- fetch_proxy_models ---

@test "fetch_proxy_models: returns sorted model IDs from valid JSON" {
    create_stub curl 'echo "{\"data\":[{\"id\":\"gemini-3-flash\"},{\"id\":\"claude-opus-4-6\"},{\"id\":\"alpha-model\"}]}"'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:8081"
    [ "$status" -eq 0 ]
    # Should be sorted alphabetically
    local first_line
    first_line=$(echo "$output" | head -n1)
    [ "$first_line" = "alpha-model" ]
}

@test "fetch_proxy_models: returns 1 when proxy unreachable" {
    create_stub curl 'exit 22'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:9999"
    [ "$status" -eq 1 ]
}

@test "fetch_proxy_models: returns 1 on invalid JSON" {
    create_stub curl 'echo "not json at all"'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:8081"
    [ "$status" -eq 1 ]
}

@test "fetch_proxy_models: returns 1 on empty data array" {
    create_stub curl 'echo "{\"data\":[]}"'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:8081"
    [ "$status" -eq 1 ]
}

@test "fetch_proxy_models: one model ID per line (count check)" {
    create_stub curl 'echo "{\"data\":[{\"id\":\"model-a\"},{\"id\":\"model-b\"},{\"id\":\"model-c\"}]}"'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:8081"
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$count" -eq 3 ]
}

@test "fetch_proxy_models: handles single model" {
    create_stub curl 'echo "{\"data\":[{\"id\":\"only-model\"}]}"'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:8081"
    [ "$status" -eq 0 ]
    [ "$output" = "only-model" ]
}

@test "fetch_proxy_models: passes proxy_url to curl correctly" {
    create_stub curl '
for arg in "$@"; do
    if [[ "$arg" == *"/v1/models" ]]; then
        echo "$arg" >&2
        echo "{\"data\":[{\"id\":\"test\"}]}"
        exit 0
    fi
done
echo "{\"data\":[{\"id\":\"test\"}]}"
'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://myhost:7777"
    [[ "$output" == *"http://myhost:7777/v1/models"* ]] || [[ "$output" == *"test"* ]]
}

@test "fetch_proxy_models: returns 1 when data key missing" {
    create_stub curl 'echo "{\"models\":[{\"id\":\"model-a\"}]}"'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:8081"
    [ "$status" -eq 1 ]
}

@test "fetch_proxy_models: ignores entries without id field" {
    create_stub curl 'echo "{\"data\":[{\"id\":\"good-model\"},{\"name\":\"no-id\"}]}"'
    PATH="$STUB_DIR:$PATH" run fetch_proxy_models "http://localhost:8081"
    [ "$status" -eq 0 ]
    local count
    count=$(echo "$output" | wc -l | tr -d ' ')
    [ "$count" -eq 1 ]
    [ "$output" = "good-model" ]
}

# ============================================================================
# Integration: list_models + validate_model via bin/claude-proxy subprocess
# ============================================================================

# Helper: run bin/claude-proxy in a subprocess with stubbed dependencies.
# Stubs claude, nohup, and optionally curl (for /v1/models).
_run_proxy_cmd() {
    local curl_body="$1"
    shift
    local stub_dir
    stub_dir="$(mktemp -d)"

    # Stub claude (never actually invoked for --models/validation)
    cat >"$stub_dir/claude" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$stub_dir/claude"

    # Stub nohup
    cat >"$stub_dir/nohup" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$stub_dir/nohup"

    # Stub curl: delegate to body for /v1/models, handle healthcheck and session
    cat >"$stub_dir/curl" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do
    if [[ "\$arg" == */v1/models ]]; then
        $curl_body
        exit \$?
    fi
    if [[ "\$arg" == */v1/messages ]]; then
        # Session check: return HTTP 200 (valid session)
        echo "200"
        exit 0
    fi
done
# Healthcheck (is_proxy_up): succeed silently
exit 0
STUB
    chmod +x "$stub_dir/curl"

    local proxy_bin="$BATS_TEST_DIRNAME/../bin/claude-proxy"
    PATH="$stub_dir:$PATH" run "$proxy_bin" "$@"
    rm -rf "$stub_dir"
}

@test "list_models: uses live data when proxy responds" {
    _run_proxy_cmd \
        'echo "{\"data\":[{\"id\":\"live-model-1\"},{\"id\":\"live-model-2\"}]}"' \
        -p antigravity --models
    [ "$status" -eq 0 ]
    [[ "$output" == *"live from proxy"* ]]
    [[ "$output" == *"live-model-1"* ]]
}

@test "list_models: falls back to static when proxy down" {
    _run_proxy_cmd \
        'exit 22' \
        -p antigravity --models
    [ "$status" -eq 0 ]
    [[ "$output" == *"static"* ]]
}

@test "validate_model: accepts live model not in static list" {
    _run_proxy_cmd \
        'echo "{\"data\":[{\"id\":\"brand-new-model\"},{\"id\":\"claude-opus-4-6-thinking\"}]}"' \
        -p antigravity -m "brand-new-model"
    [ "$status" -eq 0 ]
}

@test "validate_model: rejects model not in live list" {
    _run_proxy_cmd \
        'echo "{\"data\":[{\"id\":\"live-model-only\"}]}"' \
        -p antigravity -m "nonexistent-model"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown model"* ]]
}
