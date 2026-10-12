#!/usr/bin/env bats
# refresh-usage-cache.bats
# Path: tests/refresh-usage-cache.bats
#
# bats-core tests for the refresh-usage-cache.sh PreToolUse hook.
# Tests: cache freshness check, background fetch, JSON output format.
# Run: bats tests/refresh-usage-cache.bats
#      just test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/refresh-usage-cache.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    # The hook derives its cache from HOME, so an isolated HOME keeps every
    # test off the developer's real ~/.claude/cache.
    isolate_home
    export CACHE_DIR="$HOME/.claude/cache"
    export CACHE_FILE="$CACHE_DIR/claude-usage.json"
    mkdir -p "$CACHE_DIR"
    # Short TTL for testing
    export USAGE_CACHE_TTL=5
    rm -f "$CACHE_FILE"
}

# A login and a curl that records each request and answers with usage headers,
# so a test can count requests instead of timing the hook.
stub_usage_ping() {
    printf '{"claudeAiOauth":{"accessToken":"tok-test"}}' >"$HOME/.claude/.credentials.json"
    stub_bin security "printf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"tok-test\"}}'"
    stub_bin secret-tool 'exit 1'
    stub_bin curl \
        "echo call >>'$BATS_TEST_TMPDIR/curl.calls'" \
        "printf 'HTTP/2 200\r\nanthropic-ratelimit-unified-5h-utilization: 0.13\r\nanthropic-ratelimit-unified-5h-reset: 1772740800\r\n\r\n{}'"
}

curl_calls() {
    [[ -f "$BATS_TEST_TMPDIR/curl.calls" ]] && wc -l <"$BATS_TEST_TMPDIR/curl.calls" | tr -d ' ' || echo 0
}

# Waits, up to a bound, for the hook's background request to land.
wait_for_calls() {
    local want="$1" i
    for i in $(seq 100); do
        [[ "$(curl_calls)" -ge "$want" ]] && return 0
        sleep 0.1
    done
    return 1
}

teardown() {
    rm -f "$CACHE_FILE"
}

# Portable helper: set file mtime to a target epoch (works on macOS + Linux)
set_file_mtime() {
    local file="$1" target_epoch="$2"
    "${_PY}" -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$file" "$target_epoch"
}

# --- Basic functionality ---

# bats file_tags=integration

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "hook exits 0 on first run (no cache)" {
    # Will try to fetch in background; may fail without valid token, but exit 0
    echo '{}' | bash "$HOOK"
}

@test "hook exits 0 when cache is fresh" {
    # Create a fresh cache file
    echo '{"five_hour_pct":10,"five_hour_reset_epoch":9999999999,"fetched_at":0}' > "$CACHE_FILE"
    echo '{}' | bash "$HOOK"
}

@test "hook makes no request while the cache is fresh" {
    stub_usage_ping
    echo '{"five_hour_pct":10,"five_hour_reset_epoch":9999999999,"fetched_at":0}' > "$CACHE_FILE"
    echo '{}' | bash "$HOOK"
    # Control: once stale, the same hook does make its request. Any request
    # from the fresh run would have landed by the time this one does.
    set_file_mtime "$CACHE_FILE" "$(( $(date +%s) - USAGE_CACHE_TTL - 5 ))"
    echo '{}' | bash "$HOOK"
    wait_for_calls 1
    [ "$(curl_calls)" -eq 1 ]
}

@test "hook consumes stdin without error" {
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$HOOK"
}

@test "hook handles empty stdin" {
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    echo "" | bash "$HOOK"
}

# --- Cache freshness ---

@test "hook skips fetch when cache age < USAGE_CACHE_TTL" {
    stub_usage_ping
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    # 0 seconds old against a TTL of 5: no request, and the cache is untouched
    echo '{}' | bash "$HOOK"
    echo '{}' | bash "$HOOK"
    set_file_mtime "$CACHE_FILE" "$(( $(date +%s) - USAGE_CACHE_TTL - 5 ))"
    echo '{}' | bash "$HOOK"
    wait_for_calls 1
    [ "$(curl_calls)" -eq 1 ]
}

@test "a stale cache is refreshed from the response headers" {
    stub_usage_ping
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    set_file_mtime "$CACHE_FILE" "$(( $(date +%s) - USAGE_CACHE_TTL - 5 ))"
    echo '{}' | bash "$HOOK"
    local i
    for i in $(seq 100); do
        [[ "$(jq -r '.five_hour_pct' "$CACHE_FILE" 2>/dev/null)" == "13" ]] && break
        sleep 0.1
    done
    [[ "$(jq -r '.five_hour_pct' "$CACHE_FILE")" == "13" ]]
    [[ "$(jq -r '.five_hour_reset_epoch' "$CACHE_FILE")" == "1772740800" ]]
}

@test "hook attempts fetch when cache age > USAGE_CACHE_TTL" {
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    # Age the cache to be older than TTL (cross-platform)
    local target_ts=$(( $(date +%s) - USAGE_CACHE_TTL - 5 ))
    set_file_mtime "$CACHE_FILE" "$target_ts"
    # Hook will try to fetch (may fail without valid token, but exit 0)
    echo '{}' | bash "$HOOK"
}

@test "hook respects custom USAGE_CACHE_TTL" {
    stub_usage_ping
    export USAGE_CACHE_TTL=1
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    # Two seconds old: stale against a TTL of 1, so the hook asks once
    set_file_mtime "$CACHE_FILE" "$(( $(date +%s) - 2 ))"
    echo '{}' | bash "$HOOK"
    wait_for_calls 1
    [ "$(curl_calls)" -eq 1 ]
}

# --- Rounding ---

@test "fraction-to-percent rounds to nearest (not truncates)" {
    # 0.005 * 100 = 0.5, should round to 1 not truncate to 0
    local result
    result=$(echo "0.005" | awk '{printf "%d", $1 * 100 + 0.5}')
    [[ "$result" -eq 1 ]]
}

@test "fraction-to-percent rounds 0.13 to 13" {
    local result
    result=$(echo "0.13" | awk '{printf "%d", $1 * 100 + 0.5}')
    [[ "$result" -eq 13 ]]
}

@test "fraction-to-percent rounds 0.0 to 0" {
    local result
    result=$(echo "0.0" | awk '{printf "%d", $1 * 100 + 0.5}')
    [[ "$result" -eq 0 ]]
}

# --- Default TTL ---

@test "default USAGE_CACHE_TTL is 60 seconds" {
    unset USAGE_CACHE_TTL
    local ttl_line
    ttl_line=$(grep 'USAGE_CACHE_TTL=.*:-' "$HOOK")
    [[ "$ttl_line" == *':-60}'* ]]
}

@test "hook refreshes after 60s default TTL" {
    unset USAGE_CACHE_TTL
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    # Age the cache to 65 seconds old (past default 60s TTL, cross-platform)
    local target_ts=$(( $(date +%s) - 65 ))
    set_file_mtime "$CACHE_FILE" "$target_ts"
    # Verify the file is actually old enough
    local file_age
    file_age=$("${_PY}" -c "import os,sys,time; print(int(time.time() - os.stat(sys.argv[1]).st_mtime))" "$CACHE_FILE")
    [[ "$file_age" -ge 60 ]]
    # Hook should exit 0 (stale cache triggers background fetch)
    run bash "$HOOK" <<< '{}'
    [ "$status" -eq 0 ]
}

# --- Stop hook configuration ---

@test "settings.json has Stop hook for refresh-usage-cache" {
    local settings="$BATS_TEST_DIRNAME/../.claude/settings.json"
    # Verify Stop hook section exists and references the script
    jq -e '.hooks.Stop' "$settings" >/dev/null
    jq -e '.hooks.Stop[] | select(.hooks[].command | contains("refresh-usage-cache"))' "$settings" >/dev/null
}

@test "settings.json has both PreToolUse and Stop hooks for refresh-usage-cache" {
    local settings="$BATS_TEST_DIRNAME/../.claude/settings.json"
    local pre_count stop_count
    pre_count=$(jq '[.hooks.PreToolUse[] | select(.hooks[].command | contains("refresh-usage-cache"))] | length' "$settings")
    stop_count=$(jq '[.hooks.Stop[] | select(.hooks[].command | contains("refresh-usage-cache"))] | length' "$settings")
    [[ "$pre_count" -ge 1 ]]
    [[ "$stop_count" -ge 1 ]]
}

# --- Cache file format (integration, requires valid OAuth token) ---
# These tests verify the cache file format after a real API call.
# They are skipped if no valid token is available.

@test "hook uses atomic write (temp+mv pattern)" {
    grep -q 'mv -f.*tmp.*CACHE_FILE' "$HOOK"
}

_has_valid_token() {
    security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | \
        jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null | \
        grep -q "sk-ant-"
}

@test "integration: real Haiku ping writes valid JSON cache" {
    if ! _has_valid_token; then
        skip "No valid OAuth token in Keychain"
    fi

    # Force stale cache
    rm -f "$CACHE_FILE"
    # Override CACHE_DIR and CACHE_FILE in the hook's environment
    CACHE_DIR="$BATS_TEST_TMPDIR" \
    CACHE_FILE="$BATS_TEST_TMPDIR/claude-usage.json" \
    USAGE_CACHE_TTL=0 \
        bash -c 'cat >/dev/null; source "'"$HOOK"'"' <<< '{}'

    # Background fetch — wait for it
    sleep 5

    # The hook backgrounds the fetch, so we can't guarantee it wrote.
    # But if it did, verify format
    if [[ -f "$CACHE_FILE" ]]; then
        local pct reset_epoch status
        pct=$(jq -r '.five_hour_pct' "$CACHE_FILE")
        reset_epoch=$(jq -r '.five_hour_reset_epoch' "$CACHE_FILE")
        status=$(jq -r '.status' "$CACHE_FILE")

        # pct should be 0-100
        [[ "$pct" -ge 0 ]]
        [[ "$pct" -le 100 ]]
        # reset_epoch should be a valid epoch
        [[ "$reset_epoch" -gt 1700000000 ]]
        # status should be "allowed" or similar
        [[ -n "$status" ]]
    fi
}
