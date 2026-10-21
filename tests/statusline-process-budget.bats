#!/usr/bin/env bats
# statusline-process-budget.bats -- How many processes one render starts.
#
# Claude Code redraws the status line after every event and on a timer, once per
# open session, and starting a process is the slow part: hundreds of times the
# cost of a builtin under Git Bash, and mise's shims start mise for every call.
# A warm render must stay within a small, fixed number of external commands.

STATUSLINE="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"
COUNTED="jq cat stat date tr awk sed head cut wc uname dirname basename mkdir mv rm cksum"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    # Never the real Keychain: a lookup there can raise an administrator
    # prompt or read a real login.
    stub_bin security 'exit 44'
    export XDG_STATE_HOME="$HOME/.local/state" TMPDIR="$BATS_TEST_TMPDIR/tmp"
    local tmp="$TMPDIR/claude-statusline-$(id -u)"
    mkdir -p "$HOME/.claude" "$tmp"
    printf 'components=model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,email,cc_status\ncc_status_position=newline\nweekly_show_reset=true\n' \
        >"$HOME/.claude/statusline.conf"
    printf '{"oauthAccount":{"emailAddress":"user@example.com"}}' >"$HOME/.claude.json"
    # Warm caches, as in a running session.
    echo on >"$tmp/status-cache"
    : >"$BATS_TEST_TMPDIR/transcript.jsonl"
    local now
    now=$(date +%s)
    INPUT=$(printf '{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"session_id":"s1","transcript_path":"%s","rate_limits":{"five_hour":{"used_percentage":32.4,"resets_at":%d},"seven_day":{"used_percentage":71.6,"resets_at":%d}}}' \
        "$BATS_TEST_TMPDIR/transcript.jsonl" "$((now + 480))" "$((now + 141120))")
}

# The first executable named $1 on PATH that is not a mise shim, which would
# look the command up again and find the counting shim.
real_command() {
    local dir
    local IFS=:
    for dir in ${PATH}; do
        [[ "${dir}" == */mise/shims || "${dir}" == "$BATS_TEST_TMPDIR/count" ]] && continue
        [[ -x "${dir}/$1" ]] && printf '%s' "${dir}/$1" && return 0
    done
    for dir in "${MISE_DATA_DIR:-$HOME/.local/share/mise}"/installs/"$1"/*/"$1"; do
        [[ -x "${dir}" ]] && printf '%s' "${dir}" && return 0
    done
    command -v "$1"
}

# Renders once through counting shims; CALLS holds one line per command run.
render_counted() {
    local c real dir="$BATS_TEST_TMPDIR/count"
    mkdir -p "$dir"
    for c in ${COUNTED}; do
        real=$(real_command "$c") || continue
        printf '#!/bin/sh\necho %s >>"%s/calls"\nexec "%s" "$@"\n' "$c" "$BATS_TEST_TMPDIR" "$real" >"$dir/$c"
        chmod +x "$dir/$c"
    done
    : >"$BATS_TEST_TMPDIR/calls"
    run env PATH="$dir:$PATH" COLUMNS=200 NO_COLOR=1 bash "$STATUSLINE" <<<"$INPUT"
    CALLS=$(sort "$BATS_TEST_TMPDIR/calls" | uniq -c)
}

@test "process budget: a warm render runs at most 8 external commands" {
    COLUMNS=200 bash "$STATUSLINE" <<<"$INPUT" >/dev/null
    render_counted
    [ "$status" -eq 0 ]
    [[ "$output" == "opus-5.5 | 32%/72% (39h11m) | "* ]]
    local total
    total=$(wc -l <"$BATS_TEST_TMPDIR/calls")
    ((total <= 8)) || {
        echo "external commands: ${total}" >&2
        echo "${CALLS}" >&2
        false
    }
}

@test "process budget: stdin is parsed by one jq, and no text tool runs" {
    COLUMNS=200 bash "$STATUSLINE" <<<"$INPUT" >/dev/null
    render_counted
    [ "$status" -eq 0 ]
    local jq_calls
    jq_calls=$(grep -c '^jq$' "$BATS_TEST_TMPDIR/calls" || true)
    ((jq_calls <= 3)) || {
        echo "${CALLS}" >&2
        false
    }
    ! grep -qE '^(tr|awk|sed|head|cut|wc|uname|dirname|basename|cat)$' "$BATS_TEST_TMPDIR/calls" || {
        echo "${CALLS}" >&2
        false
    }
}

@test "process budget: an unchanged account reading is not rewritten" {
    COLUMNS=200 bash "$STATUSLINE" <<<"$INPUT" >/dev/null
    render_counted
    [ "$status" -eq 0 ]
    ! grep -qE '^(mkdir|mv)$' "$BATS_TEST_TMPDIR/calls" || {
        echo "${CALLS}" >&2
        false
    }
}
