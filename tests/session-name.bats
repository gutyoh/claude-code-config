#!/usr/bin/env bats
# session-name.bats
# Path: tests/session-name.bats
#
# Tests for the session-name.sh SessionStart/UserPromptSubmit hook, the
# statusline's model record it reads, and the merge-mode installer entries.
#
# Run: bats tests/session-name.bats
#      just test

bats_require_minimum_version 1.5.0

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/session-name.sh"
REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SID="0ed0b890-9116-4571-8ae6-17a3d0013f8c"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd jq
    isolate_home
    unset CLAUDE_SESSION_NAME CLAUDE_SESSION_NAME_TZ XDG_STATE_HOME
    STATE="${HOME}/.local/state/claude-code/session-names"
}

# hook <start|prompt> <json>: runs the hook as that event and leaves the title
# it set in $title. Input that is not a JSON object is passed through as is.
hook() {
    local event body
    case "$1" in
        start) event=SessionStart ;;
        prompt) event=UserPromptSubmit ;;
        *) event="$1" ;;
    esac
    body=$(jq -c --arg e "${event}" '. + {hook_event_name: $e}' <<<"$2" 2>/dev/null) || body="$2"
    [[ "${body}" == "{"* ]] || body="$2"
    run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" "${body}"
    title=$(jq -r '.hookSpecificOutput.sessionTitle // empty' <<<"${output}" 2>/dev/null || true)
}

input() {
    jq -nc --arg title "${1:-}" --arg model "${2:-}" --arg sid "${3:-$SID}" \
        '{session_id: $sid, session_title: $title, model: $model}
         | with_entries(select(.value != ""))'
}

# age <file> <days>: backdates a file; BSD touch has no relative -d.
age() {
    "${_PY}" -c 'import os, sys, time; t = time.time() - int(sys.argv[2]) * 86400; os.utime(sys.argv[1], (t, t))' "$1" "$2"
}

record_model() {
    mkdir -p "${STATE}"
    printf '%s\n' "$1" >"${STATE}/${SID}.model"
}

# --- start ------------------------------------------------------------------

# bats test_tags=unit
@test "start records the start time in UTC and prints nothing" {
    hook start "$(input "" claude-opus-5-5)"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    [[ "$(cat "${STATE}/${SID}.start")" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
}

# bats test_tags=unit
@test "a time zone override records its offset instead of Z" {
    CLAUDE_SESSION_NAME_TZ=America/Panama hook start "$(input "" claude-opus-5-5)"
    [[ "$(cat "${STATE}/${SID}.start")" =~ ^[0-9]{8}T[0-9]{6}-0500$ ]]
}

# bats test_tags=unit
@test "start records the start model unless the statusline already did" {
    hook start "$(input "" gpt-6.1-sol)"
    [ "$(cat "${STATE}/${SID}.model")" = "gpt-6.1-sol" ]

    record_model muse-spark-1.3
    hook start "$(input "" gpt-6.1-sol)"
    [ "$(cat "${STATE}/${SID}.model")" = "muse-spark-1.3" ]
}

# bats test_tags=unit
@test "start leaves a titled session alone" {
    hook start "$(input my-work claude-opus-5-5)"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    [ ! -e "${STATE}/${SID}.start" ]
}

# bats test_tags=unit
@test "start prunes state older than 30 days" {
    record_model claude-opus-5-5
    age "${STATE}/${SID}.model" 40
    printf 'x\n' >"${STATE}/fresh.model"
    hook start "$(input titled)"
    [ ! -e "${STATE}/${SID}.model" ]
    [ -e "${STATE}/fresh.model" ]
}

# --- prompt -----------------------------------------------------------------

# bats test_tags=unit
@test "the first prompt names the session with its start time and model" {
    hook start "$(input "" claude-opus-5-5)"
    stamp=$(cat "${STATE}/${SID}.start")
    hook prompt "$(input)"
    [ "${title}" = "claude-${stamp}" ]
    [ "$(jq -r .hookSpecificOutput.hookEventName <<<"${output}")" = "UserPromptSubmit" ]
}

# bats test_tags=unit
@test "the provider comes from the model id" {
    for pair in gpt-6.1-sol:gpt muse-spark-1.3:muse claude-haiku-5-5:claude opus:claude; do
        record_model "${pair%%:*}"
        hook prompt "$(input)"
        [[ "${title}" =~ ^${pair#*:}-[0-9]{8}T[0-9]{6}Z$ ]]
    done
}

# bats test_tags=unit
@test "an untitled prompt without state is named now, as claude" {
    hook prompt "$(input)"
    [[ "${title}" =~ ^claude-[0-9]{8}T[0-9]{6}Z$ ]]
    CLAUDE_SESSION_NAME_TZ=America/Panama hook prompt "$(input)"
    [[ "${title}" =~ ^claude-[0-9]{8}T[0-9]{6}-0500$ ]]
}

# bats test_tags=unit
@test "prompt swaps the provider prefix and keeps the timestamp" {
    record_model muse-spark-1.3
    hook prompt "$(input claude-20261011T193012Z)"
    [ "${title}" = "muse-20261011T193012Z" ]

    record_model gpt-6.1-sol
    hook prompt "$(input muse-20261011T143012-0500)"
    [ "${title}" = "gpt-20261011T143012-0500" ]
}

# bats test_tags=unit
@test "prompt stays quiet while the provider is unchanged" {
    record_model claude-opus-5-5
    hook prompt "$(input claude-20261011T193012Z)"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    hook prompt "$(input claude-20261011T193012Z sonnet)"
    [ -z "${output}" ]
}

# bats test_tags=unit
@test "prompt never touches a manual name" {
    record_model muse-spark-1.3
    for name in my-manual auth-refactor claude-20261011 claude-20261011T1930Z; do
        hook prompt "$(input "${name}")"
        [ "$status" -eq 0 ]
        [ -z "${output}" ]
    done
}

# bats test_tags=unit
@test "prompt without a recorded model leaves a name alone" {
    hook prompt "$(input claude-20261011T193012Z)"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

# --- safety -----------------------------------------------------------------

# bats test_tags=unit
@test "CLAUDE_SESSION_NAME=off disables both modes" {
    CLAUDE_SESSION_NAME=off hook start "$(input "" claude-opus-5-5)"
    [ ! -e "${STATE}/${SID}.start" ]
    record_model muse-spark-1.3
    CLAUDE_SESSION_NAME=off hook prompt "$(input claude-20261011T193012Z)"
    [ -z "${output}" ]
    CLAUDE_SESSION_NAME=off hook prompt "$(input)"
    [ -z "${output}" ]
}

# bats test_tags=unit
@test "malformed or empty input exits 0 silently" {
    for bad in 'not json' '' '{}' '{"session_id":"../escape"}'; do
        hook prompt "${bad}"
        [ "$status" -eq 0 ]
        [ -z "${output}" ]
        hook start "${bad}"
        [ "$status" -eq 0 ]
        [ -z "${output}" ]
    done
}

# bats test_tags=unit
@test "another event does nothing" {
    hook Stop "$(input "" claude-opus-5-5)"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

# --- statusline record ------------------------------------------------------

statusline_record() {
    # shellcheck disable=SC2016
    run bash -c 'debug() { :; }; debug_var() { :; }; source "$1"; record_session_model "$2"' \
        _ "${REPO_DIR}/.claude/scripts/lib/statusline/data.sh" "$1"
}

# bats test_tags=unit
@test "the statusline records the current model per session" {
    statusline_record "{\"session_id\":\"${SID}\",\"model\":{\"id\":\"gpt-6.1-sol\"}}"
    [ "$status" -eq 0 ]
    [ "$(cat "${STATE}/${SID}.model")" = "gpt-6.1-sol" ]
    statusline_record "{\"session_id\":\"${SID}\",\"model\":{\"id\":\"muse-spark-1.3\"}}"
    [ "$(cat "${STATE}/${SID}.model")" = "muse-spark-1.3" ]
}

# bats test_tags=unit
@test "the statusline skips an unchanged model and odd session ids" {
    record_model gpt-6.1-sol
    age "${STATE}/${SID}.model" 2
    before=$(stat -c %Y "${STATE}/${SID}.model" 2>/dev/null || stat -f %m "${STATE}/${SID}.model")
    statusline_record "{\"session_id\":\"${SID}\",\"model\":{\"id\":\"gpt-6.1-sol\"}}"
    after=$(stat -c %Y "${STATE}/${SID}.model" 2>/dev/null || stat -f %m "${STATE}/${SID}.model")
    [ "${before}" = "${after}" ]

    statusline_record '{"session_id":"../x","model":{"id":"gpt-6.1-sol"}}'
    [ ! -e "${HOME}/.local/state/claude-code/x.model" ]
}

# --- installer --------------------------------------------------------------

# bats test_tags=unit
@test "merge mode adds both hook entries once and keeps existing hooks" {
    require_cmd python3
    export SETTINGS_JSON="${BATS_TEST_TMPDIR}/settings.json"
    printf '%s\n' '{"hooks":{"SessionStart":[{"matcher":"resume","hooks":[{"type":"command","command":"other.sh"}]}]}}' >"${SETTINGS_JSON}"
    # shellcheck source=../lib/setup/settings.sh
    source "${REPO_DIR}/lib/setup/settings.sh"

    run configure_session_name_hooks
    [ "$status" -eq 0 ]
    run configure_session_name_hooks
    [ "$status" -eq 0 ]
    [[ "${output}" == *"already configured"* ]]

    [ "$(jq '.hooks.SessionStart | length' "${SETTINGS_JSON}")" -eq 2 ]
    [ "$(jq -r '.hooks.SessionStart[1].matcher' "${SETTINGS_JSON}")" = "startup" ]
    [ "$(jq -r '.hooks.SessionStart[1].hooks[0].command' "${SETTINGS_JSON}")" = "~/.claude/hooks/session-name.sh" ]
    [ "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "${SETTINGS_JSON}")" = "~/.claude/hooks/session-name.sh" ]
    [ "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "${SETTINGS_JSON}")" = "other.sh" ]
}

# bats test_tags=unit
@test "the repo settings wire both modes" {
    local settings="${REPO_DIR}/.claude/settings.json"
    [ "$(jq -r '.hooks.SessionStart[] | select(.matcher == "startup") | .hooks[].command' "${settings}")" = "~/.claude/hooks/session-name.sh" ]
    [ "$(jq -r '.hooks.UserPromptSubmit[].hooks[].command' "${settings}")" = "~/.claude/hooks/session-name.sh" ]
}
