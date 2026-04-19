#!/usr/bin/env bats
# rate-limit-brave-search.bats
# Path: tests/rate-limit-brave-search.bats
#
# bats-core tests for the rate-limit-brave-search.sh PreToolUse hook.
# Run: bats tests/rate-limit-brave-search.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/rate-limit-brave-search.sh"
DUMMY_INPUT='{"tool_name":"mcp__brave-search__brave_web_search","tool_input":{"query":"test"}}'

now_ms() {
    "${_PY}" -c "import time; print(int(time.time() * 1000))"
}

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    # Isolate test state into BATS_TEST_TMPDIR so tests never touch the
    # developer's real /tmp/brave-search-* files.
    export BRAVE_RATE_LIMIT_STATE_DIR="${BATS_TEST_TMPDIR}"
    LOCK_DIR="${BATS_TEST_TMPDIR}/brave-search-rate-limit.lock"
    TIMESTAMP_FILE="${BATS_TEST_TMPDIR}/brave-search-last-call"
    rm -rf "$LOCK_DIR"
    rm -f "$TIMESTAMP_FILE"
}

teardown() {
    rm -rf "$LOCK_DIR"
    rm -f "$TIMESTAMP_FILE"
}

# --- Basic functionality ---

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "first call exits 0 (no prior state)" {
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=1100 bash "$HOOK"
}

@test "first call completes quickly (< 500ms)" {
    local start
    start=$(now_ms)
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=1100 bash "$HOOK"
    local end
    end=$(now_ms)
    local elapsed=$((end - start))
    # Windows Git Bash process spawning is slower than Unix
    local threshold=500
    local _uname; _uname="$(uname -s)"
    if [[ "$_uname" == MINGW* || "$_uname" == MSYS* || "$_uname" == CYGWIN* || "$_uname" == *_NT* ]]; then
        threshold=5000
    fi
    [ "$elapsed" -lt "$threshold" ]
}

# --- Rate limiting ---

@test "second rapid call is delayed by rate limit" {
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=800 bash "$HOOK"

    local start
    start=$(now_ms)
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=800 bash "$HOOK"
    local end
    end=$(now_ms)
    local elapsed=$((end - start))
    [ "$elapsed" -ge 500 ]
}

@test "second call still exits 0 (allows, just delays)" {
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=500 bash "$HOOK"
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=500 bash "$HOOK"
}

@test "respects custom BRAVE_API_RATE_LIMIT_MS (short)" {
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK"

    local start
    start=$(now_ms)
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK"
    local end
    end=$(now_ms)
    local elapsed=$((end - start))
    # Windows Git Bash process spawning is slower than Unix
    local threshold=400
    local _uname; _uname="$(uname -s)"
    if [[ "$_uname" == MINGW* || "$_uname" == MSYS* || "$_uname" == CYGWIN* || "$_uname" == *_NT* ]]; then
        threshold=5000
    fi
    [ "$elapsed" -lt "$threshold" ]
}

# --- Lock and timestamp management ---

@test "lock directory is cleaned up after execution" {
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK"
    [ ! -d "$LOCK_DIR" ]
}

@test "timestamp file is created after call" {
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK"
    [ -f "$TIMESTAMP_FILE" ]
}

@test "timestamp file contains valid millisecond value" {
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK"
    local ts
    ts=$(cat "$TIMESTAMP_FILE")
    local now
    now=$(now_ms)
    local diff=$((now - ts))
    [ "$diff" -lt 5000 ]
    [ "$diff" -ge 0 ]
}

# --- Edge cases ---

@test "recovers from stale lock directory" {
    mkdir -p "$LOCK_DIR"

    local start
    start=$(now_ms)
    echo "$DUMMY_INPUT" | BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK"
    local end
    end=$(now_ms)
    local elapsed=$((end - start))
    # Windows Git Bash process spawning is slower than Unix
    local threshold=10000
    local _uname; _uname="$(uname -s)"
    if [[ "$_uname" == MINGW* || "$_uname" == MSYS* || "$_uname" == CYGWIN* || "$_uname" == *_NT* ]]; then
        threshold=30000
    fi
    [ "$elapsed" -lt "$threshold" ]
}

@test "handles empty stdin gracefully" {
    echo "" | BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK"
}

@test "handles no stdin gracefully" {
    BRAVE_API_RATE_LIMIT_MS=100 bash "$HOOK" < /dev/null
}

@test "default rate limit works without env var" {
    # Unset the variable — should default to 1100ms
    unset BRAVE_API_RATE_LIMIT_MS
    echo "$DUMMY_INPUT" | bash "$HOOK"
}

# --- State isolation ---

@test "BRAVE_RATE_LIMIT_STATE_DIR isolates state to a custom directory" {
    # Run the hook against a custom dir; timestamp file must land there, not /tmp
    local custom_dir="${BATS_TEST_TMPDIR}/isolated"
    mkdir -p "$custom_dir"
    BRAVE_RATE_LIMIT_STATE_DIR="$custom_dir" BRAVE_API_RATE_LIMIT_MS=100 \
        bash -c "echo '$DUMMY_INPUT' | bash '$HOOK'"
    [ -f "${custom_dir}/brave-search-last-call" ]
}

@test "does not touch /tmp/brave-search-last-call when state dir is overridden" {
    # Regression: the bats suite used to clobber /tmp state. Make sure
    # overriding the env var keeps /tmp untouched.
    local custom_dir="${BATS_TEST_TMPDIR}/isolated2"
    mkdir -p "$custom_dir"
    local real_tmp="/tmp/brave-search-last-call"
    # Snapshot real tmp content (if any) so we can assert it's unchanged.
    local snapshot=""
    if [[ -f "$real_tmp" ]]; then
        snapshot=$(cat "$real_tmp" 2>/dev/null || echo "")
    fi

    BRAVE_RATE_LIMIT_STATE_DIR="$custom_dir" BRAVE_API_RATE_LIMIT_MS=100 \
        bash -c "echo '$DUMMY_INPUT' | bash '$HOOK'"

    if [[ -n "$snapshot" ]]; then
        # File existed before the test; must still exist with same content.
        [ -f "$real_tmp" ]
        [ "$(cat "$real_tmp" 2>/dev/null || echo "")" = "$snapshot" ]
    fi
    # File that the hook wrote must be in our custom dir
    [ -f "${custom_dir}/brave-search-last-call" ]
}

# --- Concurrency / serialization ---

@test "concurrent invocations serialize (~2× rate limit for 3 parallel calls)" {
    # Launch 3 parallel invocations with a 200ms limit. If the lock serializes
    # correctly, total wall time for the LAST call to start is ≥ 2×200ms after
    # the first. We measure the elapsed time from first-launch to all-done and
    # assert ≥ 400ms (= 2 × 200ms rate limit, because the first call is free).
    local limit=200
    local start end elapsed

    start=$(now_ms)
    (
        BRAVE_API_RATE_LIMIT_MS="$limit" bash -c "echo '$DUMMY_INPUT' | bash '$HOOK'"
    ) &
    local pid1=$!
    (
        BRAVE_API_RATE_LIMIT_MS="$limit" bash -c "echo '$DUMMY_INPUT' | bash '$HOOK'"
    ) &
    local pid2=$!
    (
        BRAVE_API_RATE_LIMIT_MS="$limit" bash -c "echo '$DUMMY_INPUT' | bash '$HOOK'"
    ) &
    local pid3=$!

    wait "$pid1" "$pid2" "$pid3"
    end=$(now_ms)
    elapsed=$((end - start))

    # Expect at least 2 × limit (first call is free, 2nd waits limit,
    # 3rd waits ~2×limit). Some slack for slow CI.
    local minimum=$(( limit * 2 - 50 ))
    [ "$elapsed" -ge "$minimum" ]
}
