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
    unset CLAUDE_SESSION_NAME CLAUDE_SESSION_NAME_TZ XDG_STATE_HOME CLAUDE_SESSION_NAME_REFRESH
    unset HERDR_ENV HERDR_TAB_ID HERDR_PANE_ID HERDR_BIN_PATH HERDR_SOCKET_PATH HERDR_WORKSPACE_ID
    export CLAUDE_CODE_ENTRYPOINT=cli
    # Topics need a model run; the topic tests below turn them on with a stub.
    export CLAUDE_SESSION_NAME_TOPIC=off
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
    CLAUDE_SESSION_NAME_TZ=Asia/Tokyo hook start "$(input "" claude-opus-5-5)"
    [[ "$(cat "${STATE}/${SID}.start")" =~ ^[0-9]{8}T[0-9]{6}\+0900$ ]]
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
@test "a non-interactive run is never named" {
    export CLAUDE_CODE_ENTRYPOINT=sdk-cli
    hook start "$(input "" claude-opus-5-5)"
    [ ! -e "${STATE}/${SID}.start" ]
    hook prompt "$(input)"
    [ -z "${title}" ]
    [ -z "${output}" ]
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
    CLAUDE_SESSION_NAME_TZ=Asia/Tokyo hook prompt "$(input)"
    [[ "${title}" =~ ^claude-[0-9]{8}T[0-9]{6}\+0900$ ]]
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

# --- topic ------------------------------------------------------------------

# A claude that records how it was called and answers with $ANSWER.
stub_claude() {
    stub_bin claude \
        "env | grep -E '^(HERDR_|CLAUDE_SESSION_NAME=)' | sort >'${BATS_TEST_TMPDIR}/claude.env'" \
        "printf '%s\\n' \"\$@\" >'${BATS_TEST_TMPDIR}/claude.args'" \
        "${1:-printf '%s\\n' 'postgresql-btree-page-splits'}"
    unset CLAUDE_SESSION_NAME_TOPIC
}

# Waits, up to a bound, for a file the background topic writes.
wait_for() {
    local i
    for i in $(seq 100); do
        [[ -s "$1" ]] && return 0
        sleep 0.1
    done
    return 1
}

prompt_input() { # <title> <prompt> [transcript]
    jq -nc --arg title "$1" --arg prompt "$2" --arg sid "$SID" --arg tp "${3:-}" \
        '{session_id: $sid, session_title: $title, prompt: $prompt, transcript_path: $tp}
         | with_entries(select(.value != ""))'
}

# bats test_tags=unit
@test "topic: the first prompt names the session now and writes its topic in the background" {
    stub_claude
    record_model claude-opus-5-5
    hook prompt "$(prompt_input "" "Explain how PostgreSQL B-tree indexes handle page splits")"
    [[ "${title}" =~ ^claude-[0-9]{8}T[0-9]{6}Z$ ]]
    wait_for "${STATE}/${SID}.topic"
    [ "$(cat "${STATE}/${SID}.topic")" = "postgresql-btree-page-splits" ]
    grep -qx -- '--setting-sources' "${BATS_TEST_TMPDIR}/claude.args"
    grep -qx -- '--no-session-persistence' "${BATS_TEST_TMPDIR}/claude.args"
    grep -qx -- '--strict-mcp-config' "${BATS_TEST_TMPDIR}/claude.args"
    grep -q 'page splits' "${BATS_TEST_TMPDIR}/claude.args"
}

# bats test_tags=unit
@test "topic: the model run is cut off from herdr and from naming itself" {
    stub_claude
    export HERDR_ENV=1 HERDR_TAB_ID=w1:t9 HERDR_PANE_ID=w1:p9 HERDR_SOCKET_PATH=/tmp/x
    hook prompt "$(prompt_input "" "anything at all")"
    wait_for "${BATS_TEST_TMPDIR}/claude.env"
    ! grep -q '^HERDR_' "${BATS_TEST_TMPDIR}/claude.env"
    grep -qx 'CLAUDE_SESSION_NAME=off' "${BATS_TEST_TMPDIR}/claude.env"
}

# bats test_tags=unit
@test "topic: the next prompt adds it to the name" {
    record_model claude-opus-5-5
    mkdir -p "${STATE}"
    echo postgresql-btree-page-splits >"${STATE}/${SID}.topic"
    hook prompt "$(prompt_input claude-20261012T141205Z "next")"
    [ "${title}" = "claude-20261012T141205Z-postgresql-btree-page-splits" ]
}

# bats test_tags=unit
@test "topic: a provider switch keeps the time and the topic" {
    record_model gpt-6.1-sol
    hook prompt "$(prompt_input claude-20261012T141205Z-btree-splits "next")"
    [ "${title}" = "gpt-20261012T141205Z-btree-splits" ]
}

# bats test_tags=unit
@test "topic: a suffix Claude Code added for a taken name is left alone" {
    record_model claude-opus-5-5
    mkdir -p "${STATE}"
    echo btree-splits >"${STATE}/${SID}.topic"
    hook prompt "$(prompt_input claude-20261012T141205Z-btree-splits-groovy-coral "next")"
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
}

# bats test_tags=unit
@test "topic: refreshed every CLAUDE_SESSION_NAME_REFRESH prompts, from the transcript" {
    stub_claude "printf '%s\\n' 'pancake-recipe'"
    record_model claude-opus-5-5
    local tp="${BATS_TEST_TMPDIR}/t.jsonl"
    printf '%s\n' '{"type":"user","message":{"content":"how do I make fluffy pancakes"}}' \
        '{"type":"user","message":{"content":[{"type":"tool_result","content":"ignored"}]}}' >"$tp"
    export CLAUDE_SESSION_NAME_REFRESH=3
    mkdir -p "${STATE}"
    echo 1 >"${STATE}/${SID}.prompts"
    hook prompt "$(prompt_input claude-20261012T141205Z "second" "$tp")"
    [ ! -e "${BATS_TEST_TMPDIR}/claude.args" ]
    hook prompt "$(prompt_input claude-20261012T141205Z "third" "$tp")"
    wait_for "${STATE}/${SID}.topic"
    [ "$(cat "${STATE}/${SID}.topic")" = "pancake-recipe" ]
    grep -q 'fluffy pancakes' "${BATS_TEST_TMPDIR}/claude.args"
    ! grep -q 'ignored' "${BATS_TEST_TMPDIR}/claude.args"
}

# bats test_tags=unit
@test "topic: CLAUDE_SESSION_NAME_REFRESH=0 keeps the first topic" {
    stub_claude
    export CLAUDE_SESSION_NAME_REFRESH=0
    mkdir -p "${STATE}"
    echo 9 >"${STATE}/${SID}.prompts"
    hook prompt "$(prompt_input claude-20261012T141205Z "tenth")"
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/claude.args" ]
}

# bats test_tags=unit
@test "topic: a failed model run falls back to the prompt's first words" {
    stub_claude "exit 1"
    hook prompt "$(prompt_input "" "Análisis de pricing agregado para octubre")"
    wait_for "${STATE}/${SID}.topic"
    [ "$(cat "${STATE}/${SID}.topic")" = "analisis-de-pricing-agregado" ]
}

# bats test_tags=unit
@test "topic: the model's answer is made an address: ASCII, lowercase, hyphens" {
    stub_claude "printf '%s\\n' '**Análisis — Pricing: Cartera**' 'second line'"
    hook prompt "$(prompt_input "" "x")"
    wait_for "${STATE}/${SID}.topic"
    [ "$(cat "${STATE}/${SID}.topic")" = "analisis-pricing-cartera" ]
}

# bats test_tags=unit
@test "topic: off, or an empty prompt, asks no model" {
    stub_claude
    CLAUDE_SESSION_NAME_TOPIC=off hook prompt "$(prompt_input "" "a real prompt")"
    hook prompt "$(prompt_input "" "   ")"
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/claude.args" ]
}

# bats test_tags=unit
@test "topic: the prompt never waits for the model" {
    stub_claude "sleep 30"
    run timeout 10 bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
        "$(jq -c '. + {hook_event_name: "UserPromptSubmit"}' <<<"$(prompt_input "" "slow model")")"
    [ "$status" -eq 0 ]
    [[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"${output}")" =~ ^claude- ]]
}

# bats test_tags=unit
@test "topic: no prompt text is kept in the state directory" {
    stub_claude
    hook prompt "$(prompt_input "" "secret-marker-7731 do the thing")"
    wait_for "${STATE}/${SID}.topic"
    ! grep -rq 'secret-marker-7731' "${STATE}"
}

# --- herdr tab ----------------------------------------------------------------

# A herdr whose tab has <label> and <panes>, recording renames.
stub_herdr() {
    stub_bin herdr \
        'case "$1 $2" in' \
        "  'tab get') printf '{\"result\":{\"tab\":{\"label\":\"%s\",\"pane_count\":%s}}}' '$1' '${2:-1}' ;;" \
        "  'tab rename') shift 3; printf '%s\\n' \"\$*\" >'${BATS_TEST_TMPDIR}/rename' ;;" \
        'esac'
    export HERDR_ENV=1 HERDR_TAB_ID=w1:t5
}

conf_icons() {
    mkdir -p "${HOME}/.claude"
    printf 'icon=A\\\nicon_openai=OAI\nicon_muse=INF\n' >"${HOME}/.claude/statusline.conf"
}

# bats test_tags=unit
@test "tab: a numbered tab gets the plan's icon and the topic" {
    stub_claude
    stub_herdr 5
    conf_icons
    record_model gpt-6.1-sol
    hook prompt "$(prompt_input "" "page splits")"
    wait_for "${BATS_TEST_TMPDIR}/rename"
    [ "$(cat "${BATS_TEST_TMPDIR}/rename")" = "OAI postgresql-btree-page" ]
}

# bats test_tags=unit
@test "tab: without a plan icon the provider's name stands in" {
    stub_claude
    stub_herdr 3
    record_model muse-spark-1.3
    hook prompt "$(prompt_input "" "page splits")"
    wait_for "${BATS_TEST_TMPDIR}/rename"
    [ "$(cat "${BATS_TEST_TMPDIR}/rename")" = "muse postgresql-btree-page" ]
}

# bats test_tags=unit
@test "tab: a tab named by hand, or holding several panes, is left alone" {
    stub_claude
    stub_herdr "my-own-name"
    hook prompt "$(prompt_input "" "page splits")"
    wait_for "${STATE}/${SID}.topic"
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/rename" ]

    rm -f "${STATE}/${SID}.topic"
    stub_herdr 4 2
    hook prompt "$(prompt_input "" "page splits")"
    wait_for "${STATE}/${SID}.topic"
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/rename" ]
}

# bats test_tags=unit
@test "tab: a name this hook gave follows a provider switch" {
    stub_herdr "OAI btree-splits"
    conf_icons
    mkdir -p "${STATE}"
    echo "OAI btree-splits" >"${STATE}/${SID}.tab"
    echo btree-splits >"${STATE}/${SID}.topic"
    record_model claude-opus-5-5
    hook prompt "$(prompt_input gpt-20261012T141205Z-btree-splits "next")"
    [ "${title}" = "claude-20261012T141205Z-btree-splits" ]
    wait_for "${BATS_TEST_TMPDIR}/rename"
    [ "$(cat "${BATS_TEST_TMPDIR}/rename")" = 'A\ btree-splits' ]
}

# bats test_tags=unit
@test "tab: outside herdr nothing is renamed" {
    stub_claude
    stub_herdr 5
    unset HERDR_ENV
    hook prompt "$(prompt_input "" "page splits")"
    wait_for "${STATE}/${SID}.topic"
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/rename" ]
}
