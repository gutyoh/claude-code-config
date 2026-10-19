#!/usr/bin/env bats
# session-remote-title.bats
# Path: tests/session-remote-title.bats
#
# Tests for the session-remote-title.sh hook: a session's Remote Control entry
# gets the session's own name, once per remote session and name, and the
# login never reaches the process list. A fake curl logs its arguments and
# the config it reads on stdin, and answers FAKE_STATUS.
#
# Run: bats tests/session-remote-title.bats

bats_require_minimum_version 1.5.0

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/session-remote-title.sh"
SID="3f2a9c1e-7b4d-4e8a-9c6f-1a2b3c4d5e6f"
NAME="claude-20261018T1716-0500-delta-3f2a9c1e"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd jq
    isolate_home
    unset CLAUDE_CONFIG_DIR ANTHROPIC_BASE_URL CLAUDE_CODE_ENTRYPOINT CLAUDE_REMOTE_TITLE \
        CLAUDE_REMOTE_TITLE_HTTPS_PROXY STATUSLINE_HTTPS_PROXY
    export XDG_STATE_HOME="${HOME}/.local/state" LOG="$BATS_TEST_TMPDIR/curl.log"
    export CLAUDE_REMOTE_TITLE_FOREGROUND=1 CLAUDE_REMOTE_TITLE_WAIT=0
    STATE="${XDG_STATE_HOME}/claude-code/remote-titles"
    mkdir -p "${HOME}/.claude/sessions"
    jq -n '{oauthAccount: {organizationUuid: "org-1234"}}' >"${HOME}/.claude.json"
    login "$(($(date +%s) + 3600))000"
    entry "${NAME}" hook session_01ABCdef
    stub_bin curl <<'EOF'
cfg=$(cat)
{ printf 'ARGS %s\n' "$*"; printf 'CFG %s\n' "$cfg"; } >>"$LOG"
printf '%s' "${FAKE_STATUS:-200}"
EOF
}

# login <expiresAt ms> [dir]: Claude Code's credentials file in <dir>.
login() {
    jq -n --arg e "$1" '{claudeAiOauth: {accessToken: "sk-ant-oat-SECRETVALUE", expiresAt: ($e | tonumber)}}' \
        >"${2:-${HOME}/.claude}/.credentials.json"
}

# entry <name> <nameSource> <bridge> [dir]: the session's registry file.
entry() {
    jq -n --arg id "${SID}" --arg n "$1" --arg s "$2" --arg b "$3" \
        '{pid: 4242, sessionId: $id, name: $n, nameSource: $s, bridgeSessionId: $b, kind: "interactive", entrypoint: "cli"}' \
        >"${4:-${HOME}/.claude}/sessions/4242.json"
}

fire() {
    local body
    body=$(jq -nc --arg id "${SID}" --arg e "${1:-SessionStart}" '{session_id: $id, hook_event_name: $e, source: "resume"}')
    run bash -c 'printf "%s" "$2" | bash "$1"' _ "${RUN_HOOK:-$HOOK}" "${body}"
}

# own_hook: a private copy of the hook, so a test finds and stops only the
# background checks it started.
own_hook() {
    RUN_HOOK="$BATS_TEST_TMPDIR/session-remote-title.sh"
    cp "$HOOK" "$RUN_HOOK"
}

# stop_own: stops this session's background check by the pid its lock holds,
# then waits for it to go; Git Bash has no pgrep.
stop_own() {
    local pid
    pid=$(cat "${STATE}/${SID}.lock/pid" 2>/dev/null) || return 0
    kill "${pid}" 2>/dev/null || true
    for _ in $(seq 1 20); do
        kill -0 "${pid}" 2>/dev/null || return 0
        sleep 0.5
    done
}

# bats test_tags=unit
@test "a named session's remote entry gets its name through the rename endpoint" {
    fire
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q 'ARGS .*-X PUT .*https://api.anthropic.com/v1/code/sessions/cse_01ABCdef' "$LOG"
    grep -q "\"title\":\"${NAME}\"" "$LOG"
    grep -q 'x-organization-uuid: org-1234' "$LOG"
    [ "$(cat "${STATE}/cse_01ABCdef")" = "${NAME}" ]
}

# bats test_tags=unit
@test "the login travels in the stdin config, never in the arguments" {
    fire
    grep -q 'CFG .*Authorization: Bearer sk-ant-oat-SECRETVALUE' "$LOG"
    ! grep '^ARGS' "$LOG" | grep -q SECRETVALUE
}

# bats test_tags=unit
@test "the same remote session and name are set once; a new name is set again" {
    fire
    fire UserPromptSubmit
    [ "$(grep -c '^ARGS' "$LOG")" -eq 1 ]
    entry "claude-renamed" user session_01ABCdef
    fire UserPromptSubmit
    [ "$(grep -c '^ARGS' "$LOG")" -eq 2 ]
    grep -q '"title":"claude-renamed"' "$LOG"
}

# bats test_tags=unit
@test "a new remote session after a resume gets the name too" {
    fire
    entry "${NAME}" user session_01XYZnew
    fire
    grep -q 'sessions/cse_01XYZnew' "$LOG"
}

# bats test_tags=unit
@test "a session without a chosen name is left alone" {
    for source in "" auto default; do
        entry "my-app-3f" "${source}" session_01ABCdef
        fire
    done
    [ ! -f "$LOG" ]
}

# bats test_tags=unit
@test "nothing is sent without a remote id, a name, or this session's entry" {
    entry "" hook session_01ABCdef
    fire
    entry "${NAME}" hook ""
    fire
    rm "${HOME}/.claude/sessions/4242.json"
    fire
    [ ! -f "$LOG" ]
}

# bats test_tags=unit
@test "an expired or missing login is never refreshed, and nothing is sent" {
    login "$(($(date +%s) - 10))000"
    fire
    rm "${HOME}/.claude/.credentials.json"
    fire
    [ ! -f "$LOG" ]
}

# bats test_tags=unit
@test "a failed request leaves no record, so the next event tries again" {
    FAKE_STATUS=500 fire
    [ ! -f "${STATE}/cse_01ABCdef" ]
    fire
    [ "$(grep -c '^ARGS' "$LOG")" -eq 2 ]
    [ -f "${STATE}/cse_01ABCdef" ]
}

# bats test_tags=unit
@test "off, a non-interactive run, or another API base sends nothing" {
    CLAUDE_REMOTE_TITLE=off fire
    CLAUDE_CODE_ENTRYPOINT=sdk-cli fire
    ANTHROPIC_BASE_URL=https://gateway.example fire
    [ ! -f "$LOG" ]
    ANTHROPIC_BASE_URL=https://api.anthropic.com/ fire
    [ -f "$LOG" ]
}

# bats test_tags=unit
@test "another home reads its own login, account and sessions" {
    local other="${HOME}/.claude-home"
    mkdir -p "${other}/sessions"
    jq -n '{oauthAccount: {organizationUuid: "org-home"}}' >"${other}/.claude.json"
    login "$(($(date +%s) + 3600))000" "${other}"
    entry "${NAME}" hook session_01HOMEabc "${other}"
    CLAUDE_CONFIG_DIR="${other}/" fire
    grep -q 'x-organization-uuid: org-home' "$LOG"
    grep -q 'sessions/cse_01HOMEabc' "$LOG"
}

# bats test_tags=unit
@test "on macOS the login comes from the home's Keychain entry" {
    stub_bin uname 'echo Darwin'
    stub_bin security 'echo "$*" >>"$BATS_TEST_TMPDIR/security.log"; jq -nc "{claudeAiOauth: {accessToken: \"sk-ant-oat-KEYCHAIN\", expiresAt: 9999999999999}}"'
    rm "${HOME}/.claude/.credentials.json"
    fire
    grep -q -- '-s Claude Code-credentials -w' "$BATS_TEST_TMPDIR/security.log"
    grep -q 'CFG .*Bearer sk-ant-oat-KEYCHAIN' "$LOG"
}

# bats test_tags=unit
@test "the remote id waits for Remote Control to connect" {
    entry "${NAME}" hook ""
    (sleep 3 && entry "${NAME}" hook session_01LATEone) &
    CLAUDE_REMOTE_TITLE_WAIT=10 fire
    grep -q 'sessions/cse_01LATEone' "$LOG"
}

# bats test_tags=unit
@test "in the background the hook returns at once and prints nothing" {
    own_hook
    entry "${NAME}" hook ""
    start=$(date +%s)
    CLAUDE_REMOTE_TITLE_FOREGROUND= CLAUDE_REMOTE_TITLE_WAIT=30 fire
    stop_own
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(($(date +%s) - start))" -lt 5 ]
}

# bats test_tags=unit
@test "the statusline's proxy override applies, its own wins, and empty means direct" {
    fire
    ! grep -q 'proxy = ' "$LOG"
    rm -rf "${STATE}" "$LOG"
    STATUSLINE_HTTPS_PROXY= fire
    grep -q 'CFG proxy = ""' "$LOG"
    rm -rf "${STATE}" "$LOG"
    STATUSLINE_HTTPS_PROXY= CLAUDE_REMOTE_TITLE_HTTPS_PROXY=http://proxy.example:3128 fire
    grep -q 'CFG proxy = "http://proxy.example:3128"' "$LOG"
}

# bats test_tags=unit
@test "many events start one background check per session, not one each" {
    # Counted by what reaches the API, not by processes, which Git Bash on
    # Windows lists differently.
    own_hook
    entry "${NAME}" hook ""
    for _ in 1 2 3 4 5; do
        CLAUDE_REMOTE_TITLE_FOREGROUND= CLAUDE_REMOTE_TITLE_WAIT=30 fire
    done
    sleep 1
    entry "${NAME}" hook session_01ONEonly
    for _ in $(seq 1 20); do
        [ -f "$LOG" ] && break
        sleep 1
    done
    sleep 3
    stop_own
    [ "$(grep -c '^ARGS' "$LOG")" -eq 1 ]
}

# bats test_tags=unit
@test "a name nobody chose ends the wait at once" {
    entry "my-app-3f" auto ""
    start=$(date +%s)
    CLAUDE_REMOTE_TITLE_WAIT=30 fire
    # Well under the wait, even on an emulated bash.
    [ "$(($(date +%s) - start))" -lt 15 ]
    [ ! -f "$LOG" ]
}

# bats test_tags=unit
@test "a lock left by a check that died does not block the next one" {
    mkdir -p "${STATE}/${SID}.lock"
    touch -t 202001010000 "${STATE}/${SID}.lock"
    fire
    grep -q 'sessions/cse_01ABCdef' "$LOG"
    [ ! -d "${STATE}/${SID}.lock" ]
}

# bats test_tags=unit
@test "a check stopped midway leaves no lock behind" {
    own_hook
    entry "${NAME}" hook ""
    CLAUDE_REMOTE_TITLE_FOREGROUND= CLAUDE_REMOTE_TITLE_WAIT=20 fire
    for _ in $(seq 1 20); do
        [ -s "${STATE}/${SID}.lock/pid" ] && break
        sleep 0.5
    done
    [ -d "${STATE}/${SID}.lock" ]
    stop_own
    [ ! -d "${STATE}/${SID}.lock" ]
}

# bats test_tags=unit
@test "a lock whose holder is gone is taken over at once" {
    bash -c 'exit 0' &
    gone=$!
    wait "${gone}"
    mkdir -p "${STATE}/${SID}.lock"
    printf '%s' "${gone}" >"${STATE}/${SID}.lock/pid"
    fire
    grep -q 'sessions/cse_01ABCdef' "$LOG"
}

# bats test_tags=unit
@test "a live lock makes a later event return without sending" {
    mkdir -p "${STATE}/${SID}.lock"
    printf '%s' "$$" >"${STATE}/${SID}.lock/pid"
    fire
    [ ! -f "$LOG" ]
}

# bats test_tags=unit
@test "an unexpected session or remote id is ignored" {
    body=$(jq -nc '{session_id: "../../etc", hook_event_name: "SessionStart"}')
    run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" "${body}"
    [ "$status" -eq 0 ]
    entry "${NAME}" hook 'session_01;rm -rf x'
    fire
    [ ! -f "$LOG" ]
}
