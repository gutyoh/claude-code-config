#!/usr/bin/env bats
# statusline-cache.bats
# Path: tests/statusline-cache.bats
#
# bats-core tests for statusline cache module:
# global lock (mkdir atomic), exponential backoff with jitter, stale-while-error.
#
# Strategy: source individual modules (cache.sh, data.sh) directly — NOT
# statusline.sh — to avoid readonly constant conflicts. Define our own
# test-scoped constants that point to $BATS_TEST_TMPDIR for full isolation.
#
# Run: bats tests/statusline-cache.bats
#      make test

MODULES_DIR="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline"

setup() {
    # Test-scoped constants (replaces readonly from statusline.sh)
    CACHE_FILE="$BATS_TEST_TMPDIR/cache"
    LOCK_DIR="$BATS_TEST_TMPDIR/lock"
    BACKOFF_FILE="$BATS_TEST_TMPDIR/backoff"
    CACHE_TTL=30
    LOCK_MAX_AGE_S=30
    BACKOFF_INITIAL_S=30
    BACKOFF_MAX_S=300
    PLATFORM="macos"

    # Source only the modules under test (no readonly declarations)
    source "$MODULES_DIR/cache.sh"

    # Stub for collect_service_status (defined in status.sh, called by data.sh)
    # Not needed in cache-focused tests; avoids sourcing status.sh readonly vars
    collect_service_status() { :; }
    DATA_CC_STATUS=""

    # Clean slate
    rm -f "$CACHE_FILE" "$BACKOFF_FILE"
    rm -rf "$LOCK_DIR"
}

teardown() {
    rm -f "$CACHE_FILE" "$BACKOFF_FILE"
    rm -rf "$LOCK_DIR"
}

# Portable helper: set file mtime to a target epoch (works on macOS + Linux)
set_file_mtime() {
    local file="$1" target_epoch="$2"
    python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$file" "$target_epoch"
}

# Helper: write a cache file aged N seconds in the past
write_cache_aged() {
    local content="$1"
    local age_seconds="$2"
    printf "%s" "$content" > "$CACHE_FILE"
    local target_ts=$(( $(date +%s) - age_seconds ))
    set_file_mtime "$CACHE_FILE" "$target_ts"
}

# Helper: mock API success
mock_api_success() {
    local data="$1"
    eval "get_api_session_data() { printf '%s' '$data'; }"
}

# Helper: mock API failure (429 / network error)
mock_api_failure() {
    eval 'get_api_session_data() { return 1; }'
}

# =========================================================================
# get_file_age
# =========================================================================

@test "get_file_age: returns 0-2 for freshly created file" {
    touch "$CACHE_FILE"
    local age
    age=$(get_file_age "$CACHE_FILE")
    [[ "$age" -le 2 ]]
}

@test "get_file_age: fails for nonexistent file" {
    run get_file_age "$BATS_TEST_TMPDIR/does-not-exist"
    [[ "$status" -ne 0 ]]
}

# =========================================================================
# try_acquire_lock / release_lock
# =========================================================================

@test "try_acquire_lock: succeeds when no lock exists" {
    try_acquire_lock
    [[ -d "$LOCK_DIR" ]]
}

@test "try_acquire_lock: fails when lock already held (fresh)" {
    mkdir "$LOCK_DIR"
    run try_acquire_lock
    [[ "$status" -ne 0 ]]
}

@test "try_acquire_lock: recovers stale lock older than LOCK_MAX_AGE_S" {
    mkdir "$LOCK_DIR"
    local target_ts=$(( $(date +%s) - LOCK_MAX_AGE_S - 5 ))
    touch -t "$(date -r "$target_ts" "+%Y%m%d%H%M.%S" 2>/dev/null)" "$LOCK_DIR" 2>/dev/null
    try_acquire_lock
    [[ -d "$LOCK_DIR" ]]
}

@test "release_lock: removes lock directory" {
    mkdir "$LOCK_DIR"
    release_lock
    [[ ! -d "$LOCK_DIR" ]]
}

@test "release_lock: no-op when no lock exists" {
    release_lock  # Should not error
}

# =========================================================================
# Exponential Backoff with Decorrelated Jitter
# =========================================================================

@test "should_backoff: false when no backoff file exists" {
    run should_backoff
    [[ "$status" -ne 0 ]]
}

@test "increase_backoff: first call sets BACKOFF_INITIAL_S delay" {
    increase_backoff
    [[ -f "$BACKOFF_FILE" ]]
    local delay
    delay=$(cut -f2 "$BACKOFF_FILE")
    [[ "$delay" -eq "$BACKOFF_INITIAL_S" ]]
}

@test "increase_backoff: subsequent calls produce delay in [base, min(cap, prev*3)]" {
    increase_backoff  # 30 (initial, no jitter)
    increase_backoff  # jitter range: [30, min(300, 90)] = [30, 90]
    local delay
    delay=$(cut -f2 "$BACKOFF_FILE")
    [[ "$delay" -ge "$BACKOFF_INITIAL_S" ]]
    [[ "$delay" -le 90 ]]
}

@test "increase_backoff: never exceeds BACKOFF_MAX_S" {
    # Force a large current_delay by writing directly
    local future=$(( $(date +%s) + 999 ))
    printf "%s\t%s" "$future" "200" > "$BACKOFF_FILE"
    increase_backoff  # jitter_max = min(300, 600) = 300; range [30, 300]
    local delay
    delay=$(cut -f2 "$BACKOFF_FILE")
    [[ "$delay" -le "$BACKOFF_MAX_S" ]]
}

@test "should_backoff: true during active backoff window" {
    increase_backoff
    should_backoff
}

@test "should_backoff: false after backoff window expires" {
    local expired_ts=$(( $(date +%s) - 5 ))
    printf "%s\t%s" "$expired_ts" "30" > "$BACKOFF_FILE"
    run should_backoff
    [[ "$status" -ne 0 ]]
}

@test "reset_backoff: clears backoff state" {
    increase_backoff
    [[ -f "$BACKOFF_FILE" ]]
    reset_backoff
    [[ ! -f "$BACKOFF_FILE" ]]
}

# =========================================================================
# get_cached_api_data — Fresh cache
# =========================================================================

@test "fresh cache: serves data without calling API" {
    mock_api_failure  # API broken — shouldn't matter for fresh cache
    printf "11.0\t2026-03-05T20:00:00Z\t\t" > "$CACHE_FILE"

    local result
    result=$(get_cached_api_data)
    [[ "$result" == "11.0"* ]]
}

# =========================================================================
# get_cached_api_data — Stale cache + API success
# =========================================================================

@test "stale cache + API success: refreshes and returns new data" {
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60
    mock_api_success "11.0\t2026-03-05T20:00:00Z\t\t"

    local result
    result=$(get_cached_api_data)
    [[ "$result" == "11.0"* ]]
}

@test "stale cache + API success: resets backoff" {
    # Set expired backoff so fetch proceeds
    local expired_ts=$(( $(date +%s) - 5 ))
    printf "%s\t%s" "$expired_ts" "30" > "$BACKOFF_FILE"

    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60
    mock_api_success "11.0\t2026-03-05T20:00:00Z\t\t"

    get_cached_api_data >/dev/null
    [[ ! -f "$BACKOFF_FILE" ]]
}

@test "stale cache + API success: updates cache file" {
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60
    mock_api_success "11.0\t2026-03-05T20:00:00Z\t\t"

    get_cached_api_data >/dev/null
    local cached
    cached=$(cat "$CACHE_FILE")
    [[ "$cached" == "11.0"* ]]
}

# =========================================================================
# get_cached_api_data — Stale-while-error (THE CORE BUG FIX)
# =========================================================================

@test "stale cache + API failure: serves stale cache (stale-while-error)" {
    write_cache_aged "7.0\t2026-03-05T19:00:00Z\t\t" 60
    mock_api_failure

    local result
    result=$(get_cached_api_data)
    [[ "$result" == "7.0"* ]]
}

@test "2-hour-old cache + API failure: STILL serves stale cache" {
    write_cache_aged "1.0\t2026-03-05T15:00:00Z\t\t" 7200
    mock_api_failure

    local result
    result=$(get_cached_api_data)
    [[ "$result" == "1.0"* ]]
}

@test "8-hour-old cache + API failure: STILL serves stale cache" {
    write_cache_aged "3.0\t2026-03-05T10:00:00Z\t\t" 28800
    mock_api_failure

    local result
    result=$(get_cached_api_data)
    [[ "$result" == "3.0"* ]]
}

@test "stale cache + API failure: increases backoff" {
    write_cache_aged "7.0\t2026-03-05T19:00:00Z\t\t" 60
    mock_api_failure

    get_cached_api_data >/dev/null
    [[ -f "$BACKOFF_FILE" ]]
    local delay
    delay=$(cut -f2 "$BACKOFF_FILE")
    [[ "$delay" -eq "$BACKOFF_INITIAL_S" ]]
}

# =========================================================================
# get_cached_api_data — Active backoff skips API
# =========================================================================

@test "active backoff: skips API and serves stale cache" {
    write_cache_aged "3.0\t2026-03-05T17:00:00Z\t\t" 120
    increase_backoff  # Active backoff window

    # API would return different data if called
    mock_api_success "99.0\t2026-03-05T23:00:00Z\t\t"

    local result
    result=$(get_cached_api_data)
    # Should get stale cache "3.0", not "99.0" from API
    [[ "$result" == "3.0"* ]]
}

# =========================================================================
# get_cached_api_data — Global lock prevents concurrent fetches
# =========================================================================

@test "lock held by another process: serves stale cache" {
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60
    mkdir "$LOCK_DIR"  # Simulate another process holding lock
    mock_api_success "99.0\t2026-03-05T23:00:00Z\t\t"

    local result
    result=$(get_cached_api_data)
    [[ "$result" == "5.0"* ]]
}

# =========================================================================
# get_cached_api_data — Cold start (no cache ever existed)
# =========================================================================

@test "cold start + API success: fetches, caches, and returns data" {
    mock_api_success "9.0\t2026-03-05T20:00:00Z\t\t"

    local result
    result=$(get_cached_api_data)
    [[ "$result" == "9.0"* ]]
    [[ -f "$CACHE_FILE" ]]
}

@test "cold start + API failure: returns failure (exit 1)" {
    mock_api_failure

    run get_cached_api_data
    [[ "$status" -ne 0 ]]
}

# =========================================================================
# Lock cleanup
# =========================================================================

@test "lock released after successful API fetch" {
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60
    mock_api_success "11.0\t2026-03-05T20:00:00Z\t\t"

    get_cached_api_data >/dev/null
    [[ ! -d "$LOCK_DIR" ]]
}

@test "lock released after failed API fetch" {
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60
    mock_api_failure

    get_cached_api_data >/dev/null
    [[ ! -d "$LOCK_DIR" ]]
}

# =========================================================================
# Integration: data.sh — no more garbage ccusage fallback
# =========================================================================

@test "no API + no cache + ccusage available: DATA_SESSION_PCT stays -- (no garbage estimation)" {
    # Source data.sh too for collect_data
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    # Ensure hook cache doesn't interfere
    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/nonexistent-hook.json"
    mock_api_failure
    # Mock ccusage returning a block with high token count
    eval 'get_ccusage_block() { echo "{\"totalTokens\":14000000,\"tokenCounts\":{\"inputTokens\":5000,\"outputTokens\":40000,\"cacheReadInputTokens\":13000000},\"costUSD\":10.0,\"burnRate\":{\"costPerHour\":2.5}}"; }'

    DATA_SESSION_PCT="--"
    local json='{"model":{"display_name":"Claude Opus 4.5"},"version":"1.0","cost":{}}'
    collect_data "$json"

    # MUST be "--", NOT 81% from garbage token estimation
    [[ "$DATA_SESSION_PCT" == "--" ]]
}

@test "stale API cache + ccusage: shows real API pct, not token estimation" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    # Ensure hook cache doesn't interfere
    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/nonexistent-hook.json"
    write_cache_aged "11.0\t2026-03-05T20:00:00Z\t\t" 7200
    mock_api_failure
    eval 'get_ccusage_block() { echo "{\"totalTokens\":14000000,\"tokenCounts\":{\"inputTokens\":5000,\"outputTokens\":40000,\"cacheReadInputTokens\":13000000},\"costUSD\":10.0,\"burnRate\":{\"costPerHour\":2.5}}"; }'

    DATA_SESSION_PCT="--"
    DATA_TIME_LEFT="--"
    local json='{"model":{"display_name":"Claude Opus 4.5"},"version":"1.0","cost":{}}'
    collect_data "$json"

    # Should be 11 (from stale-while-error cache), NOT 81 (from token estimation)
    [[ "$DATA_SESSION_PCT" == "11" ]]
}

# =========================================================================
# Priority chain: native stdin > hook cache > OAuth API
# =========================================================================

@test "priority 1: native stdin rate_limit wins over everything" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    # Hook cache says 14%
    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/hook-cache.json"
    echo '{"five_hour_pct":14,"five_hour_reset_epoch":1772740800}' > "$HOOK_USAGE_CACHE"

    # OAuth cache says 11%
    write_cache_aged "11.0\t2026-03-05T20:00:00Z\t\t" 0
    mock_api_failure

    DATA_SESSION_PCT="--"
    # Stdin JSON has native rate_limit (future Anthropic feature)
    local json='{"model":{"display_name":"Opus 4.6"},"version":"1.0","cost":{},"rate_limit":{"five_hour_percentage":25,"five_hour_reset_seconds":7200}}'
    collect_data "$json"

    # Should be 25 (from stdin native), not 14 (hook) or 11 (OAuth)
    [[ "$DATA_SESSION_PCT" == "25" ]]
}

@test "priority 2: hook cache wins over OAuth API" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    # Hook cache says 14%
    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/hook-cache.json"
    echo '{"five_hour_pct":14,"five_hour_reset_epoch":1772740800}' > "$HOOK_USAGE_CACHE"

    # OAuth cache says 11%
    write_cache_aged "11.0\t2026-03-05T20:00:00Z\t\t" 0
    mock_api_failure

    DATA_SESSION_PCT="--"
    local json='{"model":{"display_name":"Opus 4.6"},"version":"1.0","cost":{}}'
    collect_data "$json"

    # Should be 14 (from hook cache), not 11 (OAuth)
    [[ "$DATA_SESSION_PCT" == "14" ]]
}

@test "priority 3: OAuth API used when no hook cache exists" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    # No hook cache
    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/nonexistent.json"

    # OAuth cache says 11%
    write_cache_aged "11.0\t2026-03-05T20:00:00Z\t\t" 0

    DATA_SESSION_PCT="--"
    local json='{"model":{"display_name":"Opus 4.6"},"version":"1.0","cost":{}}'
    collect_data "$json"

    # Should be 11 (from OAuth)
    [[ "$DATA_SESSION_PCT" == "11" ]]
}

@test "no data sources: DATA_SESSION_PCT stays --" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/nonexistent.json"
    mock_api_failure

    DATA_SESSION_PCT="--"
    local json='{"model":{"display_name":"Opus 4.6"},"version":"1.0","cost":{}}'
    collect_data "$json"

    [[ "$DATA_SESSION_PCT" == "--" ]]
}

# =========================================================================
# Fix 1: Atomic writes (temp + mv)
# =========================================================================

@test "atomic write: cache file written via temp+mv (no partial reads)" {
    mock_api_success "22.0\t2026-03-06T20:00:00Z\t\t"
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60

    get_cached_api_data >/dev/null

    # Cache should contain the new data (22.0), not partial/corrupt
    local result
    result=$(cat "$CACHE_FILE")
    [[ "$result" == "22.0"* ]]
}

@test "atomic write: no leftover .tmp files after successful write" {
    mock_api_success "22.0\t2026-03-06T20:00:00Z\t\t"
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60

    get_cached_api_data >/dev/null

    # No .tmp files should remain
    local tmp_count
    tmp_count=$(ls "$BATS_TEST_TMPDIR"/cache.tmp.* 2>/dev/null | wc -l)
    [[ "$tmp_count" -eq 0 ]]
}

@test "atomic write: backoff file written via temp+mv" {
    mock_api_failure
    write_cache_aged "5.0\t2026-03-05T18:00:00Z\t\t" 60

    get_cached_api_data >/dev/null

    # Backoff file should exist and be valid
    [[ -f "$BACKOFF_FILE" ]]
    local content
    content=$(cat "$BACKOFF_FILE")
    # Should have format: epoch<TAB>delay
    [[ "$content" =~ ^[0-9]+$'\t'[0-9]+$ ]]

    # No leftover .tmp files
    local tmp_count
    tmp_count=$(ls "$BATS_TEST_TMPDIR"/backoff.tmp.* 2>/dev/null | wc -l)
    [[ "$tmp_count" -eq 0 ]]
}

# =========================================================================
# Fix 2: Staleness indicator (~prefix when hook cache > 5 min old)
# =========================================================================

@test "staleness: fresh hook cache sets DATA_SESSION_PCT_STALE=0" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/hook-cache.json"
    echo '{"five_hour_pct":14,"five_hour_reset_epoch":1772740800}' > "$HOOK_USAGE_CACHE"

    DATA_SESSION_PCT="--"
    DATA_SESSION_PCT_STALE=0
    local json='{"model":{"display_name":"Opus 4.6"},"version":"1.0","cost":{}}'
    collect_data "$json"

    # Fresh cache: numeric value, stale flag off
    [[ "$DATA_SESSION_PCT" == "14" ]]
    [[ "$DATA_SESSION_PCT_STALE" == "0" ]]
}

@test "staleness: hook cache older than 5 min sets DATA_SESSION_PCT_STALE=1" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/hook-cache.json"
    echo '{"five_hour_pct":14,"five_hour_reset_epoch":1772740800}' > "$HOOK_USAGE_CACHE"
    # Age the cache to 310 seconds (past 300s threshold, cross-platform)
    local target_ts=$(( $(date +%s) - 310 ))
    set_file_mtime "$HOOK_USAGE_CACHE" "$target_ts"

    export HOOK_STALE_THRESHOLD=300
    DATA_SESSION_PCT="--"
    DATA_SESSION_PCT_STALE=0
    local json='{"model":{"display_name":"Opus 4.6"},"version":"1.0","cost":{}}'
    collect_data "$json"

    # Stale cache: numeric value preserved, stale flag set
    [[ "$DATA_SESSION_PCT" == "14" ]]
    [[ "$DATA_SESSION_PCT_STALE" == "1" ]]
}

@test "staleness: custom HOOK_STALE_THRESHOLD respected" {
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    export HOOK_USAGE_CACHE="$BATS_TEST_TMPDIR/hook-cache.json"
    echo '{"five_hour_pct":7,"five_hour_reset_epoch":1772740800}' > "$HOOK_USAGE_CACHE"
    # Age the cache to 15 seconds (cross-platform)
    local target_ts=$(( $(date +%s) - 15 ))
    set_file_mtime "$HOOK_USAGE_CACHE" "$target_ts"

    export HOOK_STALE_THRESHOLD=10
    DATA_SESSION_PCT="--"
    DATA_SESSION_PCT_STALE=0
    local json='{"model":{"display_name":"Opus 4.6"},"version":"1.0","cost":{}}'
    collect_data "$json"

    # 15s > 10s threshold: stale flag set, value still numeric
    [[ "$DATA_SESSION_PCT" == "7" ]]
    [[ "$DATA_SESSION_PCT_STALE" == "1" ]]
}

# =========================================================================
# Fix 3: User-specific /tmp paths (prevents symlink attacks)
# =========================================================================

@test "statusline.sh uses UID-scoped /tmp directory" {
    local statusline="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"
    # Verify _TMP_DIR includes $UID
    grep -q 'claude-statusline-\${UID}' "$statusline"
}

@test "cache, lock, and backoff paths are under UID-scoped dir" {
    local statusline="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"
    # All three should reference _TMP_DIR, not /tmp directly
    grep -q 'CACHE_FILE="\${_TMP_DIR}/' "$statusline"
    grep -q 'LOCK_DIR="\${_TMP_DIR}/' "$statusline"
    grep -q 'BACKOFF_FILE="\${_TMP_DIR}/' "$statusline"
}
