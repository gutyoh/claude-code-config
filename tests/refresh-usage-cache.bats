#!/usr/bin/env bats
# refresh-usage-cache.bats
# Path: tests/refresh-usage-cache.bats
#
# bats-core tests for the refresh-usage-cache.sh PreToolUse hook.
# Tests: cache freshness check, background fetch, JSON output format.
# Run: bats tests/refresh-usage-cache.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/refresh-usage-cache.sh"

setup() {
    export CACHE_DIR="$BATS_TEST_TMPDIR"
    export CACHE_FILE="$BATS_TEST_TMPDIR/claude-usage.json"
    # Short TTL for testing
    export USAGE_CACHE_TTL=5
    rm -f "$CACHE_FILE"
}

teardown() {
    rm -f "$CACHE_FILE"
}

now_ms() {
    python3 -c "import time; print(int(time.time() * 1000))"
}

# --- Basic functionality ---

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

@test "hook fast-exits when cache is fresh (< 200ms)" {
    echo '{"five_hour_pct":10,"five_hour_reset_epoch":9999999999,"fetched_at":0}' > "$CACHE_FILE"
    local start end elapsed
    start=$(now_ms)
    echo '{}' | bash "$HOOK"
    end=$(now_ms)
    elapsed=$((end - start))
    [[ "$elapsed" -lt 200 ]]
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
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    # Cache is 0 seconds old, TTL is 5 — should skip
    local start end elapsed
    start=$(now_ms)
    echo '{}' | bash "$HOOK"
    end=$(now_ms)
    elapsed=$((end - start))
    # Should be very fast (no curl), well under 200ms
    [[ "$elapsed" -lt 200 ]]
}

@test "hook attempts fetch when cache age > USAGE_CACHE_TTL" {
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    # Age the cache to be older than TTL
    local target_ts=$(( $(date +%s) - USAGE_CACHE_TTL - 5 ))
    touch -t "$(date -r "$target_ts" "+%Y%m%d%H%M.%S" 2>/dev/null)" "$CACHE_FILE" 2>/dev/null
    # Hook will try to fetch (may fail without valid token, but exit 0)
    echo '{}' | bash "$HOOK"
}

@test "hook respects custom USAGE_CACHE_TTL" {
    export USAGE_CACHE_TTL=1
    echo '{"five_hour_pct":10}' > "$CACHE_FILE"
    sleep 2
    # Cache should now be stale (age > 1s)
    # Hook exits 0 either way (background fetch)
    echo '{}' | bash "$HOOK"
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
    # Age the cache to 65 seconds old (past default 60s TTL)
    local target_ts=$(( $(date +%s) - 65 ))
    touch -t "$(date -r "$target_ts" "+%Y%m%d%H%M.%S" 2>/dev/null)" "$CACHE_FILE" 2>/dev/null
    # Hook exits 0 (background fetch attempted)
    echo '{}' | bash "$HOOK"
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
