#!/usr/bin/env bats
# rate-limit-brave-search.bats
# Path: tests/rate-limit-brave-search.bats
#
# bats-core tests for the rate-limit-brave-search.sh PreToolUse hook.
# Run: bats tests/rate-limit-brave-search.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/rate-limit-brave-search.sh"
LOCK_DIR="/tmp/brave-search-rate-limit.lock"
TIMESTAMP_FILE="/tmp/brave-search-last-call"
DUMMY_INPUT='{"tool_name":"mcp__brave-search__brave_web_search","tool_input":{"query":"test"}}'

now_ms() {
    "${_PY}" -c "import time; print(int(time.time() * 1000))"
}

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
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
    [ "$elapsed" -lt 500 ]
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
    [ "$elapsed" -lt 400 ]
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
    [ "$elapsed" -lt 10000 ]
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
