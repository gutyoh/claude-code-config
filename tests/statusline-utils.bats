#!/usr/bin/env bats
# statusline-utils.bats
# Path: tests/statusline-utils.bats
#
# bats-core tests for statusline utility functions.
# Sources statusline.sh (source guard prevents main from running).
# Run: bats tests/statusline-utils.bats
#      make test

STATUSLINE="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"

setup() {
    source "$STATUSLINE"
}

# --- format_num ---

@test "format_num: values below 1000 return plain integer" {
    result=$(format_num 42)
    [ "$result" = "42" ]
}

@test "format_num: zero returns 0" {
    result=$(format_num 0)
    [ "$result" = "0" ]
}

@test "format_num: 1000 returns 1.0k" {
    result=$(format_num 1000)
    [ "$result" = "1.0k" ]
}

@test "format_num: 15400 returns 15.4k" {
    result=$(format_num 15400)
    [ "$result" = "15.4k" ]
}

@test "format_num: 1000000 returns 1.0M" {
    result=$(format_num 1000000)
    [ "$result" = "1.0M" ]
}

@test "format_num: 6200000 returns 6.2M" {
    result=$(format_num 6200000)
    [ "$result" = "6.2M" ]
}

@test "format_num: empty input defaults to 0" {
    result=$(format_num "")
    [ "$result" = "0" ]
}

# --- format_duration_ms ---

@test "format_duration_ms: 0 returns 0m" {
    result=$(format_duration_ms 0)
    [ "$result" = "0m" ]
}

@test "format_duration_ms: 60000 (1 min) returns 1m" {
    result=$(format_duration_ms 60000)
    [ "$result" = "1m" ]
}

@test "format_duration_ms: 3600000 (1 hour) returns 1h0m" {
    result=$(format_duration_ms 3600000)
    [ "$result" = "1h0m" ]
}

@test "format_duration_ms: 5400000 (1h30m) returns 1h30m" {
    result=$(format_duration_ms 5400000)
    [ "$result" = "1h30m" ]
}

@test "format_duration_ms: 2220000 (37m) returns 37m" {
    result=$(format_duration_ms 2220000)
    [ "$result" = "37m" ]
}

# --- iso8601_to_epoch ---

@test "iso8601_to_epoch: converts valid timestamp to epoch" {
    result=$(iso8601_to_epoch "2025-01-01T00:00:00.000Z")
    [ -n "$result" ]
    # Should be a numeric value
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "iso8601_to_epoch: returns non-zero for invalid input" {
    run iso8601_to_epoch "not-a-date"
    # Should either fail or return empty
    [ -z "$output" ] || [[ "$status" -ne 0 ]]
}
