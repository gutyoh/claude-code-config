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
    unset HERDR_ENV HERDR_TAB_ID HERDR_PANE_ID HERDR_BIN_PATH HERDR_SOCKET_PATH HERDR_WORKSPACE_ID
    export CLAUDE_CODE_ENTRYPOINT=cli
    # Topics need a model run; the topic tests below turn them on with a stub.
    export CLAUDE_SESSION_NAME_TOPIC=off
    # The machine's name is the runner's; the host tests below set their own.
    export CLAUDE_HOST_ALIAS=off
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
@test "start records the start time in UTC, as month, day and time, and prints nothing" {
    before=$(TZ=UTC date +%m%dT%H%M)
    hook start "$(input "" claude-opus-5-5)"
    after=$(TZ=UTC date +%m%dT%H%M)
    [ "$status" -eq 0 ]
    [ -z "${output}" ]
    stamp=$(cat "${STATE}/${SID}.start")
    [[ "${stamp}" =~ ^[0-9]{4}T[0-9]{4}$ ]]
    [[ "${stamp}" == "${before}" || "${stamp}" == "${after}" ]]
}

# bats test_tags=unit
@test "a time zone override moves the clock, and the name carries no zone" {
    before=$(TZ=Asia/Tokyo date +%m%dT%H%M)
    CLAUDE_SESSION_NAME_TZ=Asia/Tokyo hook start "$(input "" claude-opus-5-5)"
    after=$(TZ=Asia/Tokyo date +%m%dT%H%M)
    stamp=$(cat "${STATE}/${SID}.start")
    [[ "${stamp}" == "${before}" || "${stamp}" == "${after}" ]]
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
    [ "${title}" = "claude-${stamp}-${SID:0:8}" ]
    [ "$(jq -r .hookSpecificOutput.hookEventName <<<"${output}")" = "UserPromptSubmit" ]
}

# bats test_tags=unit
@test "the machine's short name follows the provider" {
    hook start "$(input "" claude-opus-5-5)"
    stamp=$(cat "${STATE}/${SID}.start")
    CLAUDE_HOST_ALIAS=dev hook prompt "$(input)"
    [ "${title}" = "claude-dev-${stamp}-${SID:0:8}" ]
    CLAUDE_HOST_ALIAS="Mac Book!" hook prompt "$(input)"
    [ "${title}" = "claude-mac-book-${stamp}-${SID:0:8}" ]
}

# bats test_tags=unit
@test "the short name comes from the statusline files, the last one set winning" {
    unset CLAUDE_HOST_ALIAS
    mkdir -p "${HOME}/.claude/statusline.d"
    printf 'host_alias=wrong\n' >"${HOME}/.claude/statusline.conf"
    printf '# managed\nstyle.host=bold fg:#C74634\nhost_alias = lap \n' >"${HOME}/.claude/statusline.d/workstation.conf"
    hook prompt "$(input)"
    [[ "${title}" =~ ^claude-lap-[0-9]{4}T[0-9]{4}-[0-9a-f]{8}$ ]]
    printf 'host_alias=lab\n' >"${HOME}/.claude/statusline.local.conf"
    hook prompt "$(input)"
    [[ "${title}" =~ ^claude-lab-[0-9]{4}T ]]
    CLAUDE_CONFIG_DIR="${HOME}/.claude-other" HOSTNAME=box hook prompt "$(input)"
    [[ "${title}" =~ ^claude-box-[0-9]{4}T ]]
}

# bats test_tags=unit
@test "without a short name the hostname's first part is the machine's" {
    unset CLAUDE_HOST_ALIAS
    for pair in devbox-dev-01:devbox laptop-dev-01.local:laptop WorkPC:workpc; do
        HOSTNAME=${pair%%:*} hook prompt "$(input)"
        [[ "${title}" =~ ^claude-${pair#*:}-[0-9]{4}T[0-9]{4}-[0-9a-f]{8}$ ]]
    done
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
        [[ "${title}" =~ ^${pair#*:}-[0-9]{4}T[0-9]{4}-[0-9a-f]{8}$ ]]
    done
}

# bats test_tags=unit
@test "an untitled prompt without state is named now, as claude" {
    hook prompt "$(input)"
    [[ "${title}" =~ ^claude-[0-9]{4}T[0-9]{4}-[0-9a-f]{8}$ ]]
    CLAUDE_SESSION_NAME_TZ=Asia/Tokyo hook prompt "$(input)"
    [[ "${title}" =~ ^claude-[0-9]{4}T[0-9]{4}-[0-9a-f]{8}$ ]]
}

# bats test_tags=unit
@test "a named session is never renamed, not even after a model switch" {
    record_model muse-spark-1.3
    for name in claude-20261011T193012Z claude-20261011T193012Z-btree-splits gpt-20261011T143012-0500; do
        hook prompt "$(input "${name}")"
        [ "$status" -eq 0 ]
        [ -z "${output}" ]
    done
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
@test "a name in the hook's earlier form gets the current form, same time and topic" {
    export CLAUDE_HOST_ALIAS=lap
    hook prompt "$(input claude-20261011T0848-0500-probe-file-git-commit-0ed0b890)"
    [ "$status" -eq 0 ]
    [ "${title}" = "claude-lap-1011T0848-probe-file-git-commit-0ed0b890" ]
    hook prompt "$(input gpt-20261011T1930Z-0ed0b890)"
    [ "${title}" = "gpt-lap-1011T1930-0ed0b890" ]
    CLAUDE_HOST_ALIAS=off hook prompt "$(input claude-20261011T0848+0530-btree-0ed0b890)"
    [ "${title}" = "claude-1011T0848-btree-0ed0b890" ]
    hook prompt "$(input claude-20261011T084812-0500-btree-0ed0b890)"
    [ "${title}" = "claude-lap-1011T0848-btree-0ed0b890" ]
}

# bats test_tags=unit
@test "the current form, another session's name and a hand-made one stay as they are" {
    export CLAUDE_HOST_ALIAS=lap
    for name in claude-lap-1011T0848-probe-file-0ed0b890 claude-20261011T0848-0500-probe-file-aaaaaaaa \
        claude-20261011T0848-0500-probe-file-0ed0b89 my-20261011-notes-0ed0b890 claude-20261011T084-0500-0ed0b890; do
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
@test "merge mode adds each session hook entry once and keeps existing hooks" {
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

    [ "$(jq '.hooks.SessionStart | length' "${SETTINGS_JSON}")" -eq 4 ]
    [ "$(jq -r '.hooks.SessionStart[2].matcher' "${SETTINGS_JSON}")" = "" ]
    [ "$(jq -r '.hooks.SessionStart[2].hooks[0].command' "${SETTINGS_JSON}")" = "~/.claude/hooks/session-account.sh" ]
    [ "$(jq -r '.hooks.SessionStart[3].matcher' "${SETTINGS_JSON}")" = "" ]
    [ "$(jq -r '.hooks.SessionStart[3].hooks[0].command' "${SETTINGS_JSON}")" = "~/.claude/hooks/session-remote-title.sh" ]
    [ "$(jq -r '.hooks.UserPromptSubmit[1].hooks[0].command' "${SETTINGS_JSON}")" = "~/.claude/hooks/session-remote-title.sh" ]
    [ "$(jq -r '.hooks.SessionStart[1].matcher' "${SETTINGS_JSON}")" = "startup" ]
    [ "$(jq -r '.hooks.SessionStart[1].hooks[0].command' "${SETTINGS_JSON}")" = "~/.claude/hooks/session-name.sh" ]
    [ "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "${SETTINGS_JSON}")" = "~/.claude/hooks/session-name.sh" ]
    [ "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "${SETTINGS_JSON}")" = "other.sh" ]
}

# bats test_tags=unit
@test "the repo settings wire both modes" {
    local settings="${REPO_DIR}/.claude/settings.json"
    [ "$(jq -r '.hooks.SessionStart[] | select(.matcher == "startup") | .hooks[].command' "${settings}")" = "~/.claude/hooks/session-name.sh" ]
    [ "$(jq -r '.hooks.UserPromptSubmit[].hooks[0].command' "${settings}")" = "~/.claude/hooks/session-name.sh" ]
}

# bats test_tags=unit
@test "the repo settings give every start and prompt the remote title hook" {
    local settings="${REPO_DIR}/.claude/settings.json"
    jq -e '[.hooks.SessionStart[] | select(.matcher == "") | .hooks[].command] | index("~/.claude/hooks/session-remote-title.sh")' "${settings}" >/dev/null
    jq -e '[.hooks.UserPromptSubmit[] | select(.matcher == "") | .hooks[].command] | index("~/.claude/hooks/session-remote-title.sh")' "${settings}" >/dev/null
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

# A PATH of real binaries without timeout(1), as on macOS, plus the stubs.
no_timeout_path() {
    local bin="${BATS_TEST_TMPDIR}/notimeout" real p tool
    mkdir -p "$bin"
    # Real binaries only: a version manager's shim cannot run on this PATH.
    real=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/shims' | paste -sd: -)
    for tool in bash sh jq cat head tail tr iconv cut grep find mkdir rmdir mv printf env sort sleep perl uname date seq; do
        p=$(PATH="$real" command -v "$tool") && ln -sf "$p" "$bin/$tool"
    done
    ln -sf "${STUB_DIR}/claude" "$bin/claude"
    printf '%s' "$bin"
}

prompt_input() { # <title> <prompt> [transcript]
    jq -nc --arg title "$1" --arg prompt "$2" --arg sid "$SID" --arg tp "${3:-}" \
        '{session_id: $sid, session_title: $title, prompt: $prompt, transcript_path: $tp}
         | with_entries(select(.value != ""))'
}

# bats test_tags=unit
@test "topic: the first prompt names the session once, with the model's topic" {
    stub_claude
    record_model claude-opus-5-5
    hook prompt "$(prompt_input "" "Explain how PostgreSQL B-tree indexes handle page splits")"
    [[ "${title}" =~ ^claude-[0-9]{4}T[0-9]{4}-postgresql-btree-page-splits-[0-9a-f]{8}$ ]]
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
    ! grep -q '^HERDR_' "${BATS_TEST_TMPDIR}/claude.env"
    grep -qx 'CLAUDE_SESSION_NAME=off' "${BATS_TEST_TMPDIR}/claude.env"
}

# bats test_tags=unit
@test "topic: a later prompt asks no model and renames nothing" {
    stub_claude
    record_model gpt-6.1-sol
    hook prompt "$(prompt_input claude-20261012T141205Z-btree-splits "a new direction entirely")"
    [ -z "${output}" ]
    [ ! -e "${BATS_TEST_TMPDIR}/claude.args" ]
}

# bats test_tags=unit
@test "topic: a failed model run falls back to the prompt's first words" {
    stub_claude "exit 1"
    hook prompt "$(prompt_input "" "Análisis de pricing agregado para octubre")"
    [[ "${title}" =~ -analisis-de-pricing-agregado-[0-9a-f]{8}$ ]]
}

# bats test_tags=unit
@test "topic: an answer to the prompt instead of a topic is refused" {
    stub_claude "printf '%s\\n' 'No PR list is in this session and I can check'"
    hook prompt "$(prompt_input "" "no PR list here, check the other session")"
    [[ "${title}" =~ -no-pr-list-here-[0-9a-f]{8}$ ]]
}

# bats test_tags=unit
@test "topic: the model's answer is made an address: ASCII, lowercase, hyphens" {
    stub_claude "printf '%s\\n' '**Análisis — Pricing: Cartera**' 'second line'"
    hook prompt "$(prompt_input "" "x")"
    [[ "${title}" =~ -analisis-pricing-cartera-[0-9a-f]{8}$ ]]
}

# bats test_tags=unit
@test "topic: off, or an empty prompt, asks no model" {
    stub_claude
    CLAUDE_SESSION_NAME_TOPIC=off hook prompt "$(prompt_input "" "a real prompt")"
    [[ "${title}" =~ ^claude-[0-9]{4}T[0-9]{4}-[0-9a-f]{8}$ ]]
    hook prompt "$(prompt_input "" "   ")"
    [[ "${title}" =~ ^claude-[0-9]{4}T[0-9]{4}-[0-9a-f]{8}$ ]]
    [ ! -e "${BATS_TEST_TMPDIR}/claude.args" ]
}

# bats test_tags=unit
@test "topic: the first prompt waits for the model at most 8 seconds" {
    stub_claude "sleep 30"
    local paths=("$PATH")
    paths+=("$(no_timeout_path)")
    for path in "${paths[@]}"; do
        # perl's alarm, not timeout(1): macOS runners have no coreutils.
        SECONDS=0
        run perl -e 'alarm shift; exec @ARGV' 14 env PATH="$path" bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
            "$(jq -c '. + {hook_event_name: "UserPromptSubmit"}' <<<"$(prompt_input "" "slow model here")")"
        [ "$status" -eq 0 ]
        [ "${SECONDS}" -lt 13 ]
        [[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"${output}")" =~ -slow-model-here-[0-9a-f]{8}$ ]]
    done
}

# bats test_tags=unit
@test "topic: no prompt text is kept in the state directory" {
    stub_claude
    hook prompt "$(prompt_input "" "secret-marker-7731 do the thing")"
    ! grep -rq 'secret-marker-7731' "${STATE}" 2>/dev/null
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
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/rename" ]

    stub_herdr 4 2
    hook prompt "$(prompt_input "" "page splits")"
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/rename" ]
}

# bats test_tags=unit
@test "topic: without timeout(1), as on macOS, the model still runs" {
    stub_claude
    run env PATH="$(no_timeout_path)" bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
        "$(jq -c '. + {hook_event_name: "UserPromptSubmit"}' <<<"$(prompt_input "" "page splits")")"
    [[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"${output}")" =~ -postgresql-btree-page-splits-[0-9a-f]{8}$ ]]
}

@test "tab: outside herdr nothing is renamed" {
    stub_claude
    stub_herdr 5
    unset HERDR_ENV
    hook prompt "$(prompt_input "" "page splits")"
    sleep 0.5
    [ ! -e "${BATS_TEST_TMPDIR}/rename" ]
}
