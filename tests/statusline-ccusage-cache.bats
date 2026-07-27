#!/usr/bin/env bats
# statusline-ccusage-cache.bats
# Path: tests/statusline-ccusage-cache.bats
#
# `ccusage blocks --json` walks every session transcript under ~/.claude. That
# cost scales with how long the machine has been used — measured at ~19s here —
# and it ran on every statusline render with no cache. The statusline is drawn
# after every turn, so it was paid continuously.
#
# These tests pin the two properties that fix it: the call is skipped entirely
# when no component consumes it, and a render never waits on it.
#
# Run: bats tests/statusline-ccusage-cache.bats

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home

    _TMP_DIR="$BATS_TEST_TMPDIR/tmp"
    mkdir -p "$_TMP_DIR"
    PLATFORM="$(detect_test_platform)"

    CALL_LOG="$BATS_TEST_TMPDIR/ccusage-calls.log"
    export CALL_LOG
    : >"$CALL_LOG"

    debug() { :; }
    debug_var() { :; }

    source "$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/cache.sh"
    source "$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/data.sh"

    CONF_COMPONENTS="model,usage,tokens_in,tokens_out,cost,burn_rate,email"
}

# A ccusage that records every invocation and returns one active block.
stub_ccusage() {
    stub_bin ccusage 'echo "CALLED" >>"$CALL_LOG"
cat <<JSON
{"blocks":[{"isActive":true,"costUSD":1.25,"tokenCounts":{"inputTokens":11,"outputTokens":22,"cacheReadInputTokens":33},"burnRate":{"costPerHour":4.5}}]}
JSON'
}

# `grep -c` prints 0 AND exits 1 when there are no matches, so a bare
# `|| echo 0` emits the count twice. Capture, then default.
calls() {
    local n
    n=$(grep -c CALLED "$CALL_LOG" 2>/dev/null) || n=0
    printf '%s\n' "${n:-0}"
}

# --- The component gate ------------------------------------------------------

# bats test_tags=unit,statusline
@test "ccusage is not invoked when no component consumes it" {
    stub_ccusage
    CONF_COMPONENTS="model,email,cc_status"

    run get_ccusage_block
    [ "$status" -ne 0 ]
    sleep 1
    [ "$(calls)" -eq 0 ] || {
        echo "ccusage ran for a statusline that displays none of its values"
        false
    }
}

# bats test_tags=unit,statusline
@test "each ccusage-fed component on its own is enough to enable it" {
    local c
    for c in tokens_in tokens_out tokens_cache cost burn_rate; do
        CONF_COMPONENTS="model,${c},email"
        _ccusage_needed || {
            echo "component ${c} did not enable ccusage"
            false
        }
    done
}

# --- Non-blocking ------------------------------------------------------------

# bats test_tags=integration,statusline
@test "a cold render does not wait for ccusage" {
    # The regression: a multi-second scan ran inline on every render.
    stub_bin ccusage 'echo "CALLED" >>"$CALL_LOG"; sleep 20; echo "{}"'

    local start end
    start=$(date +%s)
    run get_ccusage_block
    end=$(date +%s)

    [ $((end - start)) -lt 5 ] || {
        echo "get_ccusage_block blocked for $((end - start))s"
        false
    }
}

# bats test_tags=integration,statusline
@test "a warm render serves the cache without invoking ccusage" {
    stub_ccusage
    _refresh_ccusage_cache
    [ -f "$CCUSAGE_CACHE_FILE" ]
    local before
    before=$(calls)

    run get_ccusage_block
    [ "$status" -eq 0 ]
    [[ "$output" == *'"costUSD":1.25'* ]] || [[ "$output" == *'1.25'* ]]
    [ "$(calls)" -eq "$before" ] || {
        echo "a fresh cache still shelled out to ccusage"
        false
    }
}

# --- Cache mechanics ---------------------------------------------------------

# bats test_tags=integration,statusline
@test "stale cache is served immediately and refreshed in the background" {
    stub_ccusage
    printf '%s\n' '{"costUSD":9.99,"tokenCounts":{"inputTokens":1,"outputTokens":2,"cacheReadInputTokens":3},"burnRate":{"costPerHour":1}}' >"$CCUSAGE_CACHE_FILE"
    # Older than TTL, younger than MAX_STALE.
    "${_PY}" -c "import os,sys,time; t=int(time.time())-300; os.utime(sys.argv[1],(t,t))" "$CCUSAGE_CACHE_FILE"

    run get_ccusage_block
    [ "$status" -eq 0 ]
    [[ "$output" == *"9.99"* ]] || {
        echo "did not serve the stale value: $output"
        false
    }
    # The background refresh should replace it with the stub's value.
    wait_for_content "$CCUSAGE_CACHE_FILE" '1.25' 15
}

# bats test_tags=integration,statusline
@test "the cache write is atomic — no partial file is ever served" {
    stub_ccusage
    _refresh_ccusage_cache
    # A complete JSON document, not a truncated one.
    run jq -e '.costUSD' "$CCUSAGE_CACHE_FILE"
    [ "$status" -eq 0 ]
    run bash -c "ls '${CCUSAGE_CACHE_FILE}'.tmp.* 2>/dev/null | wc -l"
    [ "$(echo "$output" | tr -d ' ')" -eq 0 ]
}

# bats test_tags=integration,statusline
@test "a held lock stops a second refresh from starting" {
    stub_ccusage
    mkdir -p "$CCUSAGE_LOCK_DIR"
    local before
    before=$(calls)

    run _refresh_ccusage_cache
    [ "$status" -ne 0 ]
    [ "$(calls)" -eq "$before" ] || {
        echo "refreshed while another process held the lock"
        false
    }
    rmdir "$CCUSAGE_LOCK_DIR"
}

# bats test_tags=integration,statusline
@test "a stale lock from a killed process is reclaimed" {
    stub_ccusage
    mkdir -p "$CCUSAGE_LOCK_DIR"
    "${_PY}" -c "import os,sys,time; t=int(time.time())-$((CCUSAGE_LOCK_MAX_AGE + 60)); os.utime(sys.argv[1],(t,t))" "$CCUSAGE_LOCK_DIR"

    run _refresh_ccusage_cache
    [ "$status" -eq 0 ]
    [ -f "$CCUSAGE_CACHE_FILE" ]
}

# bats test_tags=unit,statusline
@test "a missing ccusage binary is not an error" {
    PATH="/usr/bin:/bin" run _refresh_ccusage_cache
    [ "$status" -ne 0 ]
}
