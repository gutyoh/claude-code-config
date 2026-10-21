#!/usr/bin/env bats
# statusline-session-usage.bats
# Path: tests/statusline-session-usage.bats
#
# Tokens, cost and burn rate come from the JSON Claude Code sends on stdin:
# the session's live context, its cache reads and its list-price cost. Nothing
# scans transcripts and no ccusage runs, even where it is installed. Fields
# Claude Code has not sent yet, or sends as null or garbage, render as zero
# without breaking the line.

STATUSLINE="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    # Never the real Keychain: a lookup there can raise an administrator
    # prompt or read a real login.
    stub_bin security 'exit 44'
    stub_bin curl 'exit 7'
    export TMPDIR="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.claude"
    CALLS="$BATS_TEST_TMPDIR/ccusage-calls"
    # An installed ccusage that records any call: none may happen.
    stub_bin ccusage "echo called >>'${CALLS}'; echo '{\"blocks\":[]}'"
    conf 'tokens_in,tokens_out,tokens_cache,cost'
}

conf() { # <components> [compact: true|false]
    printf 'components=%s\ntheme=none\ncompact=%s\n' "$1" "${2:-true}" >"$HOME/.claude/statusline.conf"
}

render() { # <stdin json> [COLUMNS]
    run env COLUMNS="${2:-80}" bash "$STATUSLINE" <<<"$1"
}

FULL='{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"session_id":"s1","cost":{"total_cost_usd":3.75,"total_duration_ms":5400000},"context_window":{"total_input_tokens":155500,"total_output_tokens":1200,"context_window_size":1000000,"current_usage":{"input_tokens":8500,"output_tokens":1200,"cache_creation_input_tokens":5000,"cache_read_input_tokens":142000}}}'

# bats test_tags=unit
@test "tokens and cost are the session's own, from stdin" {
    render "$FULL"
    [ "$status" -eq 0 ]
    [ "$output" = "155.5k/1.2k/142.0k | \$3.75" ]
}

# bats test_tags=unit
@test "ccusage is never run, even installed and with every component shown" {
    conf 'tokens_in,tokens_out,tokens_cache,cost,burn_rate'
    for _ in 1 2 3; do render "$FULL" 200; done
    sleep 1 # a background refresh would have written by now
    [ ! -e "$CALLS" ] || {
        echo "ccusage ran $(wc -l <"$CALLS") times"
        false
    }
}

# bats test_tags=unit
@test "the burn rate is the session's cost per hour" {
    conf 'cost,burn_rate' false
    render "$FULL" 200
    [ "$status" -eq 0 ]
    [[ "$output" == *'$3.75'*'($2.50/hr)'* ]] || {
        echo "$output"
        false
    }
}

# bats test_tags=unit
@test "under a minute of session time the burn rate stays zero, no division blowup" {
    conf 'cost,burn_rate' false
    render '{"model":{"id":"claude-opus-5-5"},"cost":{"total_cost_usd":0.4,"total_duration_ms":2000}}' 200
    [ "$status" -eq 0 ]
    [[ "$output" == *'$0.40'*'($0.00/hr)'* ]] || {
        echo "$output"
        false
    }
}

# bats test_tags=unit
@test "before the first response (no context_window, no cost) it renders zeros" {
    render '{"model":{"id":"claude-opus-5-5"},"session_id":"s1"}'
    [ "$status" -eq 0 ]
    [ "$output" = "0/0/0 | \$0.00" ]
}

# bats test_tags=unit
@test "after /compact (current_usage null) the cache reads zero, totals stay" {
    render '{"model":{"id":"claude-opus-5-5"},"cost":{"total_cost_usd":1.5},"context_window":{"total_input_tokens":20000,"total_output_tokens":300,"current_usage":null}}'
    [ "$status" -eq 0 ]
    [ "$output" = "20.0k/300/0 | \$1.50" ]
}

# bats test_tags=unit
@test "garbage in the numeric fields renders as zero, never a printf error" {
    render '{"model":{"id":"claude-opus-5-5"},"cost":{"total_cost_usd":"lots","total_duration_ms":"x"},"context_window":{"total_input_tokens":"1e9; rm -rf /","total_output_tokens":-5,"current_usage":{"cache_read_input_tokens":3.7}}}' 200
    [ "$status" -eq 0 ]
    [[ "$output" != *"invalid"* && "$output" != *"printf"* ]]
    [[ "$output" == *'0/0/0'*'$0.00'* ]] || {
        echo "$output"
        false
    }
}

# bats test_tags=unit
@test "a cost in scientific notation is read as a number" {
    conf cost
    render '{"model":{"id":"claude-opus-5-5"},"cost":{"total_cost_usd":1.2e-05}}'
    [ "$status" -eq 0 ]
    [ "$output" = "\$0.00" ]
}

# bats test_tags=unit
@test "a million-token context reads in millions" {
    conf tokens_in
    render '{"model":{"id":"claude-opus-5-5"},"context_window":{"total_input_tokens":1000000}}'
    [ "$output" = "1.0M" ]
}

# bats test_tags=unit
@test "a session on a routed GPT model shows its own figures the same way" {
    render '{"model":{"id":"gpt-6-astra","display_name":"gpt-6-astra"},"cost":{"total_cost_usd":0.12},"context_window":{"total_input_tokens":4100,"total_output_tokens":250,"current_usage":{"cache_read_input_tokens":3000}}}'
    [ "$status" -eq 0 ]
    [ "$output" = "4.1k/250/3.0k | \$0.12" ]
}

# bats test_tags=unit
@test "the plan's usage still comes from rate_limits, untouched by token counts" {
    conf usage
    now=$(date +%s)
    render "{\"model\":{\"id\":\"claude-opus-5-5\"},\"session_id\":\"s1\",\"context_window\":{\"total_input_tokens\":900000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":32.4,\"resets_at\":$((now + 3600))}}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"32%"* ]] || {
        echo "$output"
        false
    }
}
