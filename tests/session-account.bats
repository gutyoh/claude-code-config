#!/usr/bin/env bats
# session-account.bats
# Path: tests/session-account.bats
#
# Tests for the session-account.sh SessionStart hook: the record of the
# account each session runs as, and the warning when a resume changes it.
#
# Run: bats tests/session-account.bats

bats_require_minimum_version 1.5.0

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/session-account.sh"
REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SID="3f2a9c1e-7b4d-4e8a-9c6f-1a2b3c4d5e6f"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd jq
    isolate_home
    unset CLAUDE_CONFIG_DIR
    export XDG_STATE_HOME="${HOME}/.local/state"
    LEDGER="${XDG_STATE_HOME}/claude-as/sessions"
    mkdir -p "${HOME}/.claude" "${HOME}/.claude-home"
    jq -n '{oauthAccount: {emailAddress: "me@work.example"}}' >"${HOME}/.claude.json"
    jq -n '{oauthAccount: {emailAddress: "me@home.example"}}' >"${HOME}/.claude-home/.claude.json"
}

# start <source> [home]: the hook as Claude Code runs it at a session start
# in <home> (default ~/.claude, with CLAUDE_CONFIG_DIR unset).
start() {
    local body
    body=$(jq -nc --arg id "${SID}" --arg s "$1" \
        '{session_id: $id, hook_event_name: "SessionStart", source: $s, cwd: "/x"}')
    if [[ -n ${2:-} ]]; then
        run env CLAUDE_CONFIG_DIR="$2" bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" "${body}"
    else
        run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" "${body}"
    fi
}

@test "every start records the session's home and prints nothing" {
    start startup
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ $(cat "${LEDGER}") == "${SID}"$'\t'"${HOME}/.claude"$'\t'[0-9]* ]]
    start compact "${HOME}/.claude-home/"
    [ -z "$output" ]
    [ "$(tail -n 1 "${LEDGER}" | cut -f2)" = "${HOME}/.claude-home" ]
}

@test "a resume as another account names both and the way back" {
    start startup
    start resume "${HOME}/.claude-home"
    [ "$status" -eq 0 ]
    msg=$(jq -r .systemMessage <<<"$output")
    [ "$msg" = "This session last ran as me@work.example and now runs as me@home.example. To go back: /exit, then claude-as me@work.example -r ${SID}" ]
}

@test "a resume in the same home, or a first-seen session, says nothing" {
    start resume
    [ -z "$output" ]
    start resume
    [ -z "$output" ]
}

@test "two homes signed in to one account are not a switch" {
    jq -n '{oauthAccount: {emailAddress: "me@work.example"}}' >"${HOME}/.claude-home/.claude.json"
    start startup
    start resume "${HOME}/.claude-home"
    [ -z "$output" ]
}

@test "the latest start wins when a session moved more than once" {
    start startup "${HOME}/.claude-home"
    start resume
    [[ $output == *"last ran as me@home.example"* ]]
    start resume
    [ -z "$output" ]
}

@test "bad input never blocks a session" {
    for body in '' 'not json' '{"session_id":"../../x","source":"resume"}' '{"source":"resume"}'; do
        run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" "${body}"
        [ "$status" -eq 0 ]
        [ -z "$output" ]
    done
    [ ! -e "${LEDGER}" ]
}

@test "an unwritable record never blocks a session" {
    mkdir -p "${XDG_STATE_HOME}"
    : >"${XDG_STATE_HOME}/claude-as"
    start startup
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "the record is trimmed to its newest lines once it grows past a megabyte" {
    mkdir -p "${LEDGER%/*}"
    awk 'BEGIN { for (i = 0; i < 30000; i++) printf "%036d\t/h\t1\n", i }' >"${LEDGER}"
    start startup
    [ "$(wc -l <"${LEDGER}" | tr -d ' ')" -eq 4000 ]
    [ "$(tail -n 1 "${LEDGER}" | cut -f1)" = "${SID}" ]
}

@test "the repo settings run it on every session start" {
    [ "$(jq -r '.hooks.SessionStart[] | select(.matcher == "") | .hooks[0].command' "${REPO_DIR}/.claude/settings.json")" = "~/.claude/hooks/session-account.sh" ]
}
