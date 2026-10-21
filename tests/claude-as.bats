#!/usr/bin/env bats
# claude-as.bats
# Path: tests/claude-as.bats
#
# Tests for bin/claude-as: accounts found by the email they signed in with,
# one home each, everything but the login shared with ~/.claude.
# A stub claude stands in for Claude Code; it never reaches the network.
#
# Run: bats tests/claude-as.bats

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../bin/claude-as"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd jq
    isolate_home
    unset CLAUDE_AS CLAUDE_AS_HOMES CLAUDE_AS_SHARED CLAUDE_AS_SHARE CLAUDE_CONFIG_DIR CLAUDE_ENV_FILE
    # A session started by claude-as passes these on to the tests run in it.
    unset CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX CLAUDE_HOST_ALIAS ${!HERDR_@}
    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_PROFILE
    export XDG_STATE_HOME="${HOME}/.local/state"
    mkdir -p "${HOME}/.claude/projects" "${HOME}/.claude/skills" "${HOME}/.claude/hooks"
    echo '{}' >"${HOME}/.claude/settings.json"
    echo 'shared prompt' >"${HOME}/.claude/history.jsonl"
    stub_claude
}

# The stub: `auth status` and `auth login` act on the home it is given;
# `-p --resume <id>` finds a transcript the way Claude Code reports it;
# anything else prints the home and arguments it ran with.
stub_claude() {
    stub_bin claude <<'EOF'
home=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
acct=$home/.claude.json
[[ -n ${CLAUDE_CONFIG_DIR:-} ]] || acct=$HOME/.claude.json
if [[ $1 == auth && $2 == status ]]; then
    if jq -e '.oauthAccount.emailAddress' "$acct" >/dev/null 2>&1 && [[ ! -e $home/.signed-out ]]; then
        echo '{"loggedIn": true}'
    else
        echo '{"loggedIn": false}'
    fi
    exit 0
fi
if [[ $1 == auth && $2 == login ]]; then
    printf 'login %s\n' "${*:3}" >>"$HOME/logins"
    jq --arg e "${STUB_EMAIL:-$4}" --arg t "${STUB_TYPE:-claude_pro}" --arg o "${STUB_ORG:-Org}" \
        '.oauthAccount = {emailAddress: $e, organizationType: $t, organizationName: $o, organizationUuid: ($o + "-id")}' \
        "$acct" >"$acct.tmp" && cat "$acct.tmp" >"$acct" && rm "$acct.tmp"
    exit 0
fi
if [[ $1 == -p && $2 == --resume ]]; then
    printf 'probe pane=%s\n' "${HERDR_ENV-}${HERDR_PANE_ID-}${HERDR_TAB_ID-}${HERDR_WORKSPACE_ID-}${HERDR_SOCKET_PATH-}" >>"$HOME/probes"
    if compgen -G "$home/projects/*/$3.jsonl" >/dev/null; then
        echo "Error: No deferred tool marker found in the resumed session."
    else
        echo "No conversation found with session ID: $3"
    fi
    exit 0
fi
if [[ $1 == --version ]]; then
    echo "${STUB_VERSION:-2.1.296} (Claude Code)"
    exit 0
fi
printf 'RAN set=%s home=%s args=%s\n' "${CLAUDE_CONFIG_DIR+1}" "${CLAUDE_CONFIG_DIR:-}" "$*"
printf 'ENV oauth=%s key=%s store=%s\n' "${CLAUDE_CODE_OAUTH_TOKEN-unset}" "${ANTHROPIC_API_KEY-unset}" "${CLAUDE_SECURESTORAGE_CONFIG_DIR-unset}"
printf 'RC prefix=%s\n' "${CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX-unset}"
printf 'PANE env=%s pane=%s\n' "${HERDR_ENV-unset}" "${HERDR_PANE_ID-unset}"
printf 'CONFIRMED=%s\n' "${CLAUDE_AS_CONFIRMED-unset}"
EOF
}

# account <home> <email> [type] [org] [user tier]: a signed-in home.
account() {
    local home=$1 file
    mkdir -p "${home}"
    file="${home}/.claude.json"
    [[ ${home} == "${HOME}/.claude" ]] && file="${HOME}/.claude.json"
    jq -n --arg e "$2" --arg t "${3:-claude_pro}" --arg o "${4:-Org}" --arg u "${5:-}" \
        '{oauthAccount: {emailAddress: $e, organizationType: $t, organizationName: $o,
          organizationUuid: ($o + "-id"),
          userRateLimitTier: (if $u == "" then null else $u end)}}' >"${file}"
}

linked_home() {
    account "$@"
    local name
    for name in settings.json skills hooks projects; do
        ln -s "${HOME}/.claude/${name}" "$1/${name}"
    done
}

two_accounts() {
    account "${HOME}/.claude" me@work.example claude_team Acme default_claude_max_5x
    linked_home "${HOME}/.claude-home" me@home.example claude_max Personal default_claude_max_20x
}

@test "no arguments lists every account with its plan and organization" {
    two_accounts
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ ${output} == *"me@work.example"*"team/max_5x"*"Acme"*"~/.claude"* ]]
    [[ ${output} == *"me@home.example"*"max/max_20x"*"Personal"*"~/.claude-home"* ]]
    [[ ${output} != *'\~'* ]]
}

@test "only a path under HOME is shortened to ~" {
    account "${HOME}/.claude" me@work.example
    linked_home "${HOME}x" me@home.example
    CLAUDE_AS_HOMES="${HOME}/.claude:${HOME}x" run "$SCRIPT"
    [[ ${output} == *" ~/.claude"* ]]
    [[ ${output} == *" ${HOME}x"* ]]
}

@test "a plan Claude Code adds later shows without a change here" {
    account "${HOME}/.claude" a@x.example claude_ultra Org default_claude_ultra_50x
    account "${HOME}/.claude-b" b@x.example claude_team Org ""
    account "${HOME}/.claude-c" c@x.example claude_pro Org ""
    run "$SCRIPT"
    [[ ${output} == *"ultra/ultra_50x"* ]]
    [[ ${output} == *"b@x.example"*"team "* ]]
    [[ ${output} == *"c@x.example"*"pro "* ]]
}

@test "another tool's ~/.claude-* folder or a linked one is not a home" {
    two_accounts
    mkdir -p "${HOME}/.claude-code-router"
    ln -s "${HOME}/.claude-home" "${HOME}/.claude-alias"
    run "$SCRIPT"
    [[ ${output} != *"claude-code-router"* ]]
    [[ ${output} != *"claude-alias"* ]]
}

@test "a whole email, in any case, names its account" {
    two_accounts
    for who in me@home.example ME@HOME.EXAMPLE Me@Home.Example; do
        run "$SCRIPT" "${who}" -p hi
        [ "$status" -eq 0 ]
        [[ ${output} == *"home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions -p hi"* ]] || {
            echo "${who}: ${output}"
            return 1
        }
    done
}

@test "part of an email runs nothing and lists the whole emails it is part of" {
    two_accounts
    for who in me@ home.example HOME me; do
        run "$SCRIPT" "${who}" -p hi
        [ "$status" -eq 1 ]
        [[ ${output} != *RAN* ]] || {
            echo "${who}: ${output}"
            return 1
        }
        [[ ${output} == *"no account is '${who}'; name one by its whole email"* ]]
    done
    run "$SCRIPT" me@ -p hi
    [[ ${output} == *"me@work.example"* && ${output} == *"me@home.example"* ]]
    run "$SCRIPT" nobody -p hi
    [ "$status" -eq 1 ]
    [[ ${output} == *"no account is 'nobody'; run claude-as to list them"* ]]
}

@test "a name that runs one account keeps running it after another is added" {
    account "${HOME}/.claude" me@x.example claude_team Acme
    run "$SCRIPT" me@x.example -p hi
    [[ ${output} == *"RAN set= home= args=--allow-dangerously-skip-permissions -p hi"* ]]
    linked_home "${HOME}/.claude-y" me@x.example.org claude_pro Other
    linked_home "${HOME}/.claude-z" ame@x.example claude_pro Other
    run "$SCRIPT" me@x.example -p hi
    [ "$status" -eq 0 ]
    [[ ${output} == *"RAN set= home= args=--allow-dangerously-skip-permissions -p hi"* ]]
}

@test "one email in two organizations takes its /organization, /plan or /organization id" {
    account "${HOME}/.claude" me@x.example claude_team Acme default_claude_max_5x
    linked_home "${HOME}/.claude-x" me@x.example claude_pro Personal
    run "$SCRIPT" me@x.example -p hi
    [ "$status" -eq 1 ]
    [[ ${output} == *"names 2 accounts"* ]]
    [[ ${output} == *"me@x.example/team/max_5x (Acme, Acme-id, ~/.claude)"* ]]
    for who in me@x.example/acme me@x.example/team me@x.example/team/max_5x ME@X.EXAMPLE/Acme-ID; do
        run "$SCRIPT" "${who}" -p hi
        [[ ${output} == *"RAN set= home= args=--allow-dangerously-skip-permissions -p hi"* ]] || {
            echo "${who}: ${output}"
            return 1
        }
    done
    run "$SCRIPT" me@x.example/pro -p hi
    [[ ${output} == *"home=${HOME}/.claude-x args=--allow-dangerously-skip-permissions -p hi"* ]]
    # Part of an organization or plan is no name either.
    for who in me@x.example/acm me@x.example/tea me@x/pro; do
        run "$SCRIPT" "${who}" -p hi
        [ "$status" -eq 1 ]
        [[ ${output} != *RAN* ]]
    done
}

@test "~/.claude runs with CLAUDE_CONFIG_DIR unset, others with their exact path" {
    two_accounts
    CLAUDE_CONFIG_DIR="${HOME}/.claude-home" run "$SCRIPT" me@work.example doctor
    [[ ${output} == *"RAN set= home= args=--allow-dangerously-skip-permissions doctor"* ]]
    CLAUDE_CONFIG_DIR="${HOME}/.claude" run "$SCRIPT" me@home.example doctor
    [[ ${output} == *"RAN set=1 home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions doctor"* ]]
}

@test "CLAUDE_AS chooses the account when claude options come first" {
    two_accounts
    CLAUDE_AS=me@home.example run "$SCRIPT" --continue
    [[ ${output} == *"home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions --continue"* ]]
    CLAUDE_AS=me@home.example run "$SCRIPT"
    [[ ${output} == *"home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions"* ]]
    run "$SCRIPT" --continue
    [ "$status" -eq 2 ]
    [[ ${output} == *"name the account first"* ]]
}

@test "an account starts as the claude shell function does: bypass on Shift+Tab, or on with -a" {
    two_accounts
    run "$SCRIPT" me@home.example
    [[ ${output} == *"home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions"$'\n'* ]]
    for flag in -a --unsafe --bypass -adskp; do
        run "$SCRIPT" me@home.example "${flag}" --continue
        [[ ${output} == *"home=${HOME}/.claude-home args=--dangerously-skip-permissions --continue"* ]] || {
            echo "${flag}: ${output}"
            return 1
        }
    done
    CLAUDE_AS=me@work.example run "$SCRIPT" -a
    [[ ${output} == *"RAN set= home= args=--dangerously-skip-permissions"$'\n'* ]]
    # Only first: a later -a is claude's own.
    run "$SCRIPT" me@home.example --continue -a
    [[ ${output} == *"args=--allow-dangerously-skip-permissions --continue -a"* ]]
    # The shell functions setup.sh writes hold the same defaults.
    grep -q 'mode=--allow-dangerously-skip-permissions' "$BATS_TEST_DIRNAME/../lib/setup/settings.sh"
    grep -q 'mode=--dangerously-skip-permissions' "$BATS_TEST_DIRNAME/../lib/setup/settings.sh"
    grep -q 'set -l mode --allow-dangerously-skip-permissions' "$BATS_TEST_DIRNAME/../lib/setup/settings.sh"
}

@test "another account's credentials are dropped; a gateway's is named, never shown" {
    two_accounts
    CLAUDE_CODE_OAUTH_TOKEN=secret-value-1 ANTHROPIC_API_KEY=secret-value-2 \
        CLAUDE_SECURESTORAGE_CONFIG_DIR=/elsewhere ANTHROPIC_AUTH_TOKEN=secret-value-3 \
        run "$SCRIPT" me@home.example doctor
    [[ ${output} == *"ENV oauth=unset key=unset store=unset"* ]]
    [[ ${output} == *"warning: ANTHROPIC_AUTH_TOKEN set"* ]]
    [[ ${output} != *secret-value* ]]
    CLAUDE_CODE_OAUTH_TOKEN=secret-value-1 run "$SCRIPT" me@work.example doctor
    [[ ${output} == *"RAN set= home="*"ENV oauth=unset"* ]]
}

@test "--add gives the account a private home that shares all but the login" {
    account "${HOME}/.claude" me@work.example claude_team Acme
    jq '.projects = {"/repo": {hasTrustDialogAccepted: true, allowedTools: ["Bash"]},
                     "/new": {hasTrustDialogAccepted: false}}' "${HOME}/.claude.json" >"${HOME}/j"
    mv "${HOME}/j" "${HOME}/.claude.json"
    run "$SCRIPT" --add New@Home.example --sso
    [ "$status" -eq 0 ]
    local h="${HOME}/.claude-new@home.example"
    [ "$(file_mode "${h}")" = 700 ]
    for name in settings.json skills hooks projects; do
        [ "$(readlink "${h}/${name}")" = "${HOME}/.claude/${name}" ]
    done
    [ ! -e "${h}/history.jsonl" ]
    [ ! -e "${h}/.credentials.json" ]
    jq -e '.hasCompletedOnboarding == true' "${h}/.claude.json"
    jq -e '.projects == {"/repo": {"hasTrustDialogAccepted": true}}' "${h}/.claude.json"
    jq -e '.oauthAccount.emailAddress == "New@Home.example"' "${h}/.claude.json"
    [ "$(file_mode "${h}/.claude.json")" = 600 ]
    grep -qx 'login --email New@Home.example --sso' "${HOME}/logins"
    [[ ${output} == *"Ready: claude-as new@home.example"$'\n'* || ${output} == *"Ready: claude-as new@home.example" ]]
    run "$SCRIPT" new@home.example -p hi
    [[ ${output} == *"home=${h} args=--allow-dangerously-skip-permissions -p hi"* ]]
}

@test "--add never reuses a folder that exists" {
    account "${HOME}/.claude" me@work.example
    mkdir -p "${HOME}/.claude-b@x.example"
    run "$SCRIPT" --add b@x.example
    [ "$status" -eq 0 ]
    [ -f "${HOME}/.claude-b@x.example-2/.claude.json" ]
    [ ! -e "${HOME}/.claude-b@x.example/.claude.json" ]
}

@test "--add says when the browser signed in someone else, or a free plan" {
    account "${HOME}/.claude" me@work.example
    STUB_EMAIL=other@x.example run "$SCRIPT" --add b@x.example
    [ "$status" -eq 1 ]
    [[ ${output} == *"signed in as 'other@x.example', not b@x.example"* ]]
    STUB_TYPE=claude_free run "$SCRIPT" --add c@x.example
    [[ ${output} == *"c@x.example has no paid plan"* ]]
}

@test "--add for an email already here signs in another of its organizations" {
    account "${HOME}/.claude" me@x.example claude_team Acme
    STUB_ORG=Personal run "$SCRIPT" --add me@x.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"is signed in already"* ]]
    [[ ${output} != *"same account and organization"* ]]
    # Its name tells it apart from the email's other organization.
    [[ ${output} == *"Ready: claude-as me@x.example/pro"* ]]
    STUB_ORG=Acme STUB_TYPE=claude_team run "$SCRIPT" --add me@x.example
    [[ ${output} == *"is the same account and organization as ~/.claude"* ]]
}

@test "--add refuses what is not an email" {
    account "${HOME}/.claude" me@work.example
    run "$SCRIPT" --add 'not-an-email'
    [ "$status" -eq 2 ]
    run "$SCRIPT" --add '../../etc@x.example'
    [ "$status" -eq 2 ]
    [ ! -e "${HOME}/logins" ]
}

@test "--relink adds what is missing and leaves anything else alone" {
    two_accounts
    mkdir -p "${HOME}/.claude/agents" "${HOME}/.claude-home/skills.d"
    rm "${HOME}/.claude-home/skills"
    mkdir "${HOME}/.claude-home/skills"
    run "$SCRIPT" --relink
    [ "$status" -eq 0 ]
    [ "$(readlink "${HOME}/.claude-home/agents")" = "${HOME}/.claude/agents" ]
    [[ ${output} == *"left alone  ~/.claude-home/skills"* ]]
    [ -d "${HOME}/.claude-home/skills" ] && [ ! -L "${HOME}/.claude-home/skills" ]
    run "$SCRIPT" --relink
    [[ ${output} != *linked* ]]
}

@test "--check passes when every home is signed in and sees the history" {
    two_accounts
    run "$SCRIPT" --check
    [ "$status" -eq 0 ]
    [ "$(grep -c 'ok    sees the shared session history' <<<"${output}")" -eq 2 ]
    [ "$(grep -c 'ok    signed in' <<<"${output}")" -eq 2 ]
    # The canary session is gone again: the history holds only real sessions.
    [ -z "$(find "${HOME}/.claude/projects" -name '*.jsonl')" ]
    [ ! -e "${XDG_STATE_HOME}/claude-as/canary" ]
}

@test "--check probes each home outside the herdr pane it runs in" {
    two_accounts
    HERDR_ENV=1 HERDR_PANE_ID=w1:p3 HERDR_TAB_ID=w1:t3 HERDR_WORKSPACE_ID=w1 \
        HERDR_SOCKET_PATH="${HOME}/herdr.sock" run "$SCRIPT" --check
    [ "$status" -eq 0 ]
    [ "$(grep -c '^probe pane=$' "${HOME}/probes")" -eq 2 ]
}

@test "a session claude-as starts keeps its herdr pane" {
    two_accounts
    HERDR_ENV=1 HERDR_PANE_ID=w1:p3 run "$SCRIPT" me@home.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"PANE env=1 pane=w1:p3"* ]]
}

@test "--check fails a home with its own history, a missing link or no login" {
    two_accounts
    rm "${HOME}/.claude-home/projects"
    mkdir "${HOME}/.claude-home/projects"
    touch "${HOME}/.claude-home/.signed-out"
    run "$SCRIPT" --check
    [ "$status" -eq 1 ]
    [[ ${output} == *"FAIL  cannot see the shared session history"* ]]
    [[ ${output} == *"FAIL  projects is not linked"* ]]
    [[ ${output} == *"FAIL  not signed in"* ]]
    [[ ${output} == *"3 problem(s)"* ]]
}

@test "CLAUDE_AS_HOMES limits the accounts to the homes it names" {
    two_accounts
    CLAUDE_AS_HOMES="${HOME}/.claude-home/" run "$SCRIPT"
    [[ ${output} == *"me@home.example"* ]]
    [[ ${output} != *"me@work.example"* ]]
}

@test "--help prints the usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ ${output} == *"claude-as <email> [claude args]"* ]]
    [[ ${output} != *"set -euo"* ]]
}

@test "setup.sh installs claude-as into ~/.local/bin" {
    grep -q 'ln -sf "${REPO_DIR}/bin/claude-as" "${bin_dir}/claude-as"' \
        "$BATS_TEST_DIRNAME/../setup.sh"
}

@test "a home from an old release keeps its account in .config.json" {
    account "${HOME}/.claude" me@work.example
    mkdir -p "${HOME}/.claude-old"
    jq -n '{oauthAccount: {emailAddress: "old@x.example", organizationType: "claude_max"}}' \
        >"${HOME}/.claude-old/.config.json"
    run "$SCRIPT"
    [[ ${output} == *"old@x.example"*"max"*"~/.claude-old"* ]]
}

@test "--check on macOS fails a Claude Code too old for a login per home" {
    two_accounts
    stub_bin uname 'echo Darwin'
    STUB_VERSION=2.1.143 run "$SCRIPT" --check
    [ "$status" -eq 1 ]
    [[ ${output} == *"Claude Code 2.1.143 keeps one Keychain login for every home"* ]]
    STUB_VERSION=2.1.296 run "$SCRIPT" --check
    [ "$status" -eq 0 ]
}

@test "one account signed in to two homes runs from the shared one" {
    account "${HOME}/.claude" me@x.example claude_team Acme
    linked_home "${HOME}/.claude-copy" me@x.example claude_team Acme
    run "$SCRIPT" me@x.example -p hi
    [ "$status" -eq 0 ]
    [[ ${output} == *"one account in 2 homes; using ~/.claude"* ]]
    [[ ${output} == *"RAN set= home= args=--allow-dangerously-skip-permissions -p hi"* ]]
}

@test "a home's path names it directly" {
    account "${HOME}/.claude" me@x.example claude_team Acme
    linked_home "${HOME}/.claude-copy" me@x.example claude_team Acme
    run "$SCRIPT" '~/.claude-copy' -p hi
    [[ ${output} == *"home=${HOME}/.claude-copy args=--allow-dangerously-skip-permissions -p hi"* ]]
    run "$SCRIPT" "${HOME}/.claude-copy/" -p hi
    [[ ${output} == *"home=${HOME}/.claude-copy args=--allow-dangerously-skip-permissions -p hi"* ]]
    run "$SCRIPT" "${HOME}/.claude" -p hi
    [[ ${output} == *"RAN set= home= args=--allow-dangerously-skip-permissions -p hi"* ]]
    run "$SCRIPT" '~/.nope' -p hi
    [ "$status" -eq 1 ]
    [[ ${output} == *"is not a home"* ]]
}

# --- the account a session last ran as -------------------------------------

SID=3f2a9c1e-7b4d-4e8a-9c6f-1a2b3c4d5e6f

# ran <id> <home>: session-account.sh's record of a start in <home>.
ran() {
    mkdir -p "${XDG_STATE_HOME}/claude-as"
    printf '%s\t%s\t%s\n' "$1" "$2" 1792000000 >>"${XDG_STATE_HOME}/claude-as/sessions"
}

@test "-r <id> with no account resumes as the account the session last ran as" {
    two_accounts
    ran "${SID}" "${HOME}/.claude"
    ran "${SID}" "${HOME}/.claude-home"
    run "$SCRIPT" -r "${SID}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"as it last ran: me@home.example"* ]]
    [[ ${output} == *"home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions -r ${SID}"* ]]
    run "$SCRIPT" -a --resume="${SID}"
    [[ ${output} == *"home=${HOME}/.claude-home args=--dangerously-skip-permissions --resume=${SID}"* ]]
}

@test "the record outranks CLAUDE_AS for a resume; CLAUDE_AS still starts new sessions" {
    two_accounts
    ran "${SID}" "${HOME}/.claude"
    CLAUDE_AS=me@home.example run "$SCRIPT" --resume "${SID}"
    [[ ${output} == *"RAN set= home= args=--allow-dangerously-skip-permissions --resume ${SID}"* ]]
    CLAUDE_AS=me@home.example run "$SCRIPT" -p hi
    [[ ${output} == *"home=${HOME}/.claude-home args="* ]]
}

@test "a session name ending in the id's first 8 characters finds its account" {
    two_accounts
    ran "${SID}" "${HOME}/.claude-home"
    run "$SCRIPT" --resume "claude-20260101T0900Z-btree-page-splits-3f2a9c1e"
    [[ ${output} == *"home=${HOME}/.claude-home"* ]]
    # Two recorded ids with that start name no one session.
    ran 3f2a9c1e-0000-4000-8000-000000000000 "${HOME}/.claude"
    run "$SCRIPT" --resume "claude-x-3f2a9c1e"
    [ "$status" -eq 2 ]
    [[ ${output} == *"name the account first"* ]]
}

@test "with no record, the newest prompt in each home's own history decides" {
    two_accounts
    rm -f "${HOME}/.claude-home/history.jsonl"
    printf '{"display":"a","timestamp":1792000000000,"sessionId":"%s"}\n' "${SID}" >"${HOME}/.claude/history.jsonl"
    printf '{"display":"b","timestamp":1792000500000,"sessionId":"%s"}\n' "${SID}" >"${HOME}/.claude-home/history.jsonl"
    run "$SCRIPT" -r "${SID}"
    [[ ${output} == *"home=${HOME}/.claude-home"* ]]
    printf '{"display":"c","timestamp":1792000900000,"sessionId":"%s"}\n' "${SID}" >>"${HOME}/.claude/history.jsonl"
    run "$SCRIPT" -r "${SID}"
    [[ ${output} == *"RAN set= home="* ]]
}

@test "an unknown session, or a record naming a home that is gone, still needs an account" {
    two_accounts
    run "$SCRIPT" -r "${SID}"
    [ "$status" -eq 2 ]
    [[ ${output} == *"name the account first"* ]]
    ran "${SID}" "${HOME}/.claude-gone"
    run "$SCRIPT" -r "${SID}"
    [ "$status" -eq 2 ]
}

@test "naming another account than the session last ran as says so, and continues without a terminal" {
    two_accounts
    ran "${SID}" "${HOME}/.claude"
    run "$SCRIPT" me@home.example -r "${SID}"
    [ "$status" -eq 0 ]
    [[ ${output} == *"session ${SID} last ran as me@work.example"* ]]
    [[ ${output} == *"continuing it as me@home.example"* ]]
    [[ ${output} == *"home=${HOME}/.claude-home"* ]]
    run "$SCRIPT" me@work.example -r "${SID}"
    [[ ${output} != *"last ran as"* ]]
}

# Answers <reply> to claude-as on a terminal. BSD script(1), as on macOS,
# sends piped input before the prompt and then an EOF, so the reply waits.
on_terminal() {
    if script --version 2>/dev/null | grep -q util-linux; then
        printf '%s\n' "$1" | script -qec "\"$SCRIPT\" me@home.example -r ${SID}" /dev/null
    else
        (sleep 1 && printf '%s\n' "$1") | script -q /dev/null "$SCRIPT" me@home.example -r "${SID}"
    fi
}

@test "on a terminal, a switch of account asks first: no keeps it, yes switches" {
    script -q /dev/null true >/dev/null 2>&1 || script --version 2>/dev/null | grep -q util-linux \
        || skip "needs script(1) for a terminal"
    two_accounts
    ran "${SID}" "${HOME}/.claude"
    run on_terminal n
    [[ ${output} == *"Continue it as me@home.example? [y/N]"* ]]
    [[ ${output} == *"not resumed; as before: claude-as me@work.example -r ${SID}"* ]]
    [[ ${output} != *"RAN "* ]]
    run on_terminal y
    [[ ${output} == *"RAN set=1 home=${HOME}/.claude-home"* ]]
}

@test "one account in two homes is not a switch" {
    account "${HOME}/.claude" me@work.example claude_team Acme
    linked_home "${HOME}/.claude-two" me@work.example claude_team Acme
    ran "${SID}" "${HOME}/.claude-two"
    run "$SCRIPT" me@work.example -r "${SID}"
    [[ ${output} != *"last ran as"* ]]
}

@test "--where names a home only for a session that last ran outside ~/.claude" {
    two_accounts
    run "$SCRIPT" --where --resume "${SID}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    ran "${SID}" "${HOME}/.claude"
    run "$SCRIPT" --where --allow-dangerously-skip-permissions --resume "${SID}"
    [ -z "$output" ]
    ran "${SID}" "${HOME}/.claude-home"
    run "$SCRIPT" --where -r "${SID}"
    [ "$output" = "${HOME}/.claude-home" ]
    run "$SCRIPT" --where -p hi
    [ -z "$output" ]
    run "$SCRIPT" --where --resume
    [ -z "$output" ]
}

@test "started with SIGPIPE ignored, as from herdr or Claude Code, it prints no pipe errors" {
    two_accounts
    ran "${SID}" "${HOME}/.claude"
    run bash -c 'trap "" PIPE; exec "$1" --where --resume "$2"' _ "$SCRIPT" "${SID}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    ran "${SID}" "${HOME}/.claude-home"
    run bash -c 'trap "" PIPE; exec "$1" --where -r "$2"' _ "$SCRIPT" "${SID}"
    [ "$output" = "${HOME}/.claude-home" ]
}

@test "--continue resumes this folder's newest session as the account it last ran as" {
    two_accounts
    local work="${BATS_TEST_TMPDIR}/my_repo.v2" key old=11111111-2222-4333-8444-555555555555
    mkdir -p "${work}"
    key=$(cd "${work}" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')
    mkdir -p "${HOME}/.claude/projects/${key}/${SID}/subagents"
    touch -t 202601010000 "${HOME}/.claude/projects/${key}/${old}.jsonl"
    touch -t 202601020000 "${HOME}/.claude/projects/${key}/${SID}.jsonl"
    ran "${old}" "${HOME}/.claude"
    ran "${SID}" "${HOME}/.claude-home"
    cd "${work}"
    run "$SCRIPT" -c
    [[ ${output} == *"home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions -c"* ]]
    run "$SCRIPT" --where -a --continue
    [ "$output" = "${HOME}/.claude-home" ]
    # Claude Code encodes the path: dots and underscores become dashes too.
    [[ ${key} == *"-my-repo-v2" ]]
    touch -t 202601030000 "${HOME}/.claude/projects/${key}/${old}.jsonl"
    run "$SCRIPT" --where --continue
    [ -z "$output" ]
}

@test "--continue finds a non-ASCII folder by the cwd its transcripts record" {
    two_accounts
    local work="${BATS_TEST_TMPDIR}/año" cwd key
    mkdir -p "${work}"
    cwd=$(cd "${work}" && pwd -P)
    # Claude Code makes "ñ" one dash, one UTF-16 unit; sed makes it one per byte.
    key="$(printf '%s' "${cwd%/año}" | sed 's/[^A-Za-z0-9]/-/g')-a-o"
    mkdir -p "${HOME}/.claude/projects/${key}"
    printf '{"type":"user","cwd":"%s","sessionId":"%s"}\n' "${cwd}" "${SID}" \
        >"${HOME}/.claude/projects/${key}/${SID}.jsonl"
    ran "${SID}" "${HOME}/.claude-home"
    cd "${work}"
    run "$SCRIPT" --where --continue
    [ "$output" = "${HOME}/.claude-home" ]
}

@test "--continue in a folder with no session needs an account, as before" {
    two_accounts
    cd "${BATS_TEST_TMPDIR}"
    run "$SCRIPT" -c
    [ "$status" -eq 2 ]
    run "$SCRIPT" --where -c
    [ -z "$output" ]
}

# --- Remote Control keeps a resumed session's own name ----------------------

# titled <id> <title>...: a transcript whose custom titles are, in order, these.
titled() {
    local id=$1 t
    shift
    mkdir -p "${HOME}/.claude/projects/-work"
    for t in "$@"; do
        jq -nc --arg t "${t}" --arg id "${id}" '{type: "custom-title", customTitle: $t, sessionId: $id}'
    done >>"${HOME}/.claude/projects/-work/${id}.jsonl"
}

rc_on() { jq -n "{remoteControlAtStartup: ${1:-true}}" >"${HOME}/.claude/settings.json"; }

@test "--rc-name gives a resumed session's newest title, only when Remote Control starts on its own" {
    two_accounts
    titled "${SID}" claude-dev-20261018T0100Z-first-3f2a9c1e claude-dev-20261018T0100Z-renamed-3f2a9c1e
    run "$SCRIPT" --rc-name --resume "${SID}"
    [ -z "$output" ]
    rc_on false
    run "$SCRIPT" --rc-name --resume "${SID}"
    [ -z "$output" ]
    rc_on
    run "$SCRIPT" --rc-name --resume "${SID}"
    [ "$output" = "claude-dev-20261018T0100Z-renamed-3f2a9c1e" ]
    run "$SCRIPT" --rc-name -r "${SID}" --name mine
    [ "$output" = "mine" ]
    run "$SCRIPT" --rc-name "--resume=${SID}" --name=also-mine
    [ "$output" = "also-mine" ]
}

@test "--rc-name stays out of a print run, a fork, a Remote Control choice, a new session and an unknown one" {
    two_accounts
    rc_on
    titled "${SID}" claude-dev-20261018T0100Z-x-3f2a9c1e
    for args in "-p --resume ${SID}" "--print --resume ${SID}" "--resume ${SID} --fork-session" \
        "--resume ${SID} --remote-control" "--resume ${SID} --remote-control=other" \
        "--resume" "-p hi" "" "--resume 00000000-0000-4000-8000-000000000000"; do
        # shellcheck disable=SC2086
        run "$SCRIPT" --rc-name ${args}
        [ -z "$output" ] || { echo "args: ${args} -> ${output}"; false; }
    done
}

@test "--rc-name leaves a title out that would read as an option, and a project that turns Remote Control off" {
    two_accounts
    rc_on
    titled "${SID}" -looks-like-an-option
    run "$SCRIPT" --rc-name --resume "${SID}"
    [ -z "$output" ]
    titled "${SID}" fine-name
    mkdir -p "${HOME}/repo/.claude"
    echo '{"remoteControlAtStartup": false}' >"${HOME}/repo/.claude/settings.local.json"
    run bash -c 'cd "$1" && "$2" --rc-name --resume "$3"' _ "${HOME}/repo" "$SCRIPT" "${SID}"
    [ -z "$output" ]
    run "$SCRIPT" --rc-name --resume "${SID}"
    [ "$output" = "fine-name" ]
}

@test "--rc-name finds the session a hook name or --continue resumes" {
    two_accounts
    rc_on
    ran "${SID}" "${HOME}/.claude-home"
    titled "${SID}" claude-lap-20261018T0100Z-btree-3f2a9c1e
    run "$SCRIPT" --rc-name --resume claude-lap-20261018T0100Z-btree-3f2a9c1e
    [ "$output" = "claude-lap-20261018T0100Z-btree-3f2a9c1e" ]
    mkdir -p "${HOME}/work"
    mv "${HOME}/.claude/projects/-work" "${HOME}/.claude/projects/$(printf '%s' "$(cd "${HOME}/work" && pwd -P)" | sed 's/[^A-Za-z0-9]/-/g')"
    run bash -c 'cd "$1" && "$2" --rc-name -c' _ "${HOME}/work" "$SCRIPT"
    [ "$output" = "claude-lap-20261018T0100Z-btree-3f2a9c1e" ]
}

@test "a resume through claude-as, also to another account, passes the name in front of the arguments" {
    two_accounts
    rc_on
    ran "${SID}" "${HOME}/.claude"
    titled "${SID}" claude-dev-20261018T0100Z-x-3f2a9c1e
    run "$SCRIPT" -r "${SID}" -- hi
    [[ ${output} == *"args=--allow-dangerously-skip-permissions --remote-control claude-dev-20261018T0100Z-x-3f2a9c1e -r ${SID} -- hi"* ]]
    run "$SCRIPT" me@home.example -a --resume "${SID}"
    [[ ${output} == *"home=${HOME}/.claude-home args=--dangerously-skip-permissions --remote-control claude-dev-20261018T0100Z-x-3f2a9c1e --resume ${SID}"* ]]
    run "$SCRIPT" me@home.example -p hi
    [[ ${output} == *"args=--allow-dangerously-skip-permissions -p hi"* ]]
}

@test "a launch names Remote Control's made-up names after the machine, unless the prefix is set" {
    two_accounts
    printf 'host_alias=dev\n' >"${HOME}/.claude/statusline.local.conf"
    run "$SCRIPT" me@work.example -p hi
    [[ ${output} == *"RC prefix=claude-dev"* ]]
    CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX=mine run "$SCRIPT" me@work.example -p hi
    [[ ${output} == *"RC prefix=mine"* ]]
    CLAUDE_HOST_ALIAS=off run "$SCRIPT" me@work.example -p hi
    [[ ${output} == *"RC prefix=unset"* ]]
}

@test "--host-alias reads the machine's short name as the session-name hook does" {
    local hook="$BATS_TEST_DIRNAME/../.claude/hooks/session-name.sh" title from_hook
    mkdir -p "${HOME}/.claude/statusline.d"
    check() {
        title=$(jq -nc '{hook_event_name: "UserPromptSubmit", session_id: "0ed0b890-9116-4571-8ae6-17a3d0013f8c"}' \
            | CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_SESSION_NAME_TOPIC=off bash "${hook}" | jq -r .hookSpecificOutput.sessionTitle)
        # One expression per -e: BSD sed reads "t; s/.*//" as a label.
        from_hook=$(sed -E -e 's/^claude-(.*)-[0-9]{4}T[0-9]{4}-0ed0b890$/\1/' -e t -e 's/.*//' <<<"${title}")
        [ "$("$SCRIPT" --host-alias)" = "${from_hook}" ] || { echo "hook=${title} claude-as=$("$SCRIPT" --host-alias)"; false; }
    }
    HOSTNAME=devbox-dev-01 check
    HOSTNAME=Laptop-Dev-01.local check
    printf 'host_alias=wrong\n' >"${HOME}/.claude/statusline.conf"
    printf '# x\nhost_alias = lap\n' >"${HOME}/.claude/statusline.d/workstation.conf"
    check
    [ "$("$SCRIPT" --host-alias)" = "lap" ]
    printf 'host_alias=lab01\n' >"${HOME}/.claude/statusline.local.conf"
    check
    CLAUDE_HOST_ALIAS="A Very Long Machine Name" check
    [ -z "$(CLAUDE_HOST_ALIAS=off "$SCRIPT" --host-alias)" ]
}

@test "--rc-name reads the newest copy of a transcript a moved folder left twice, and its end first" {
    two_accounts
    rc_on
    titled "${SID}" from-the-old-folder
    mkdir -p "${HOME}/.claude/projects/-zz-moved"
    touch -t 202601010000 "${HOME}/.claude/projects/-work/${SID}.jsonl"
    {
        jq -nc --arg id "${SID}" '{type: "custom-title", customTitle: "early", sessionId: $id}'
        # Past the 4 MB the end is read from: the title is found again in full.
        head -c 4200000 /dev/zero | tr '\0' 'x'
        echo
    } >"${HOME}/.claude/projects/-zz-moved/${SID}.jsonl"
    run "$SCRIPT" --rc-name --resume "${SID}"
    [ "$output" = "early" ]
    jq -nc --arg id "${SID}" '{type: "custom-title", customTitle: "latest", sessionId: $id}' \
        >>"${HOME}/.claude/projects/-zz-moved/${SID}.jsonl"
    run "$SCRIPT" --rc-name --resume "${SID}"
    [ "$output" = "latest" ]
}

# --- --move: every session in herdr to one account --------------------------

# The stub herdr keeps one line per pane in $HOME/panes:
# <pane>\t<status>\t<session id or empty>\t<claude argv, or "-" for none>\t<pid>
# where <pid> is a real process standing in for that claude.
# /exit through the agent ends it and empties the session, as Claude Code does,
# unless $HOME/dialog-<pane> stands for a dialog herdr refuses to type into.
# /exit also copies the run's recovery file to $HOME/at-exit. `pane run` runs
# the command as the pane's shell would, its output in $HOME/pane-out, then
# brings the --resume id back idle and records the start in $STUB_MOVED_HOME,
# as session-account.sh does. Every call is logged.
stub_herdr() {
    stub_bin herdr <<'EOF'
state=$HOME/panes
echo "herdr $*" >>"$HOME/herdr.log"
row() { awk -F'\t' -v p="$1" '$1 == p' "$state"; }
set_row() { awk -F'\t' -v OFS='\t' -v p="$1" -v s="$2" -v i="$3" '$1 == p {$2 = s; $3 = i} 1' "$state" >"$state.t" && mv "$state.t" "$state"; }
case "$1 $2" in
"agent list")
    awk -F'\t' '$3 != ""' "$state" | jq -R -s '{result: {agents: [split("\n")[] | select(. != "") | split("\t")
        | {pane_id: .[0], agent: "claude", agent_status: .[1], agent_session: {value: .[2]}}]}}' ;;
"pane get")
    row "$3" | jq -R -s '{result: {pane: (split("\n")[0] | split("\t")
        | if .[2] == "" then {pane_id: .[0]} else {pane_id: .[0], agent: "claude", agent_status: .[1], agent_session: {value: .[2]}} end)}}' ;;
"pane process-info")
    row "$4" | jq -R -s '{result: {process_info: {foreground_processes: [split("\n")[0] | split("\t")
        | select(.[2] != "" and .[3] != "-") | {pid: (.[4] | tonumber), argv: (.[3] | split(" "))}]}}}' ;;
"agent prompt")
    [ -e "$HOME/dialog-$3" ] && exit 1
    cat "$XDG_STATE_HOME"/claude-as/*.resume >"$HOME/at-exit" 2>/dev/null
    if [ "$4" = /exit ]; then
        kill "$(row "$3" | cut -f5)" 2>/dev/null
        set_row "$3" "" ""
    fi ;;
"pane run")
    (env -u CLAUDE_AS_MOVE_DETACHED bash -c "$4") >>"$HOME/pane-out" 2>&1 </dev/null
    id=$(printf '%s' "${*:4}" | grep -oE -- '--resume [^ ]+' | cut -d' ' -f2)
    if [ -n "$id" ]; then
        set_row "$3" idle "$id"
        printf '%s\t%s\t%s\n' "$id" "$STUB_MOVED_HOME" 1792009999 >>"$XDG_STATE_HOME/claude-as/sessions"
    fi ;;
esac
exit 0
EOF
}

# pane <pane> <status> <session id> [claude argv | -]: a pane whose claude is
# a process of its own, with a transcript to resume unless the test wrote one.
pane() {
    # Off bats' own descriptors, or bats would wait for it to end.
    sleep 600 </dev/null >/dev/null 2>&1 3>&- &
    echo "$!" >>"${HOME}/pids"
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-claude --allow-dangerously-skip-permissions --resume $3}" "$!" >>"${HOME}/panes"
    [[ -e ${HOME}/.claude/projects/-p/$3.jsonl ]] || transcript "$3" '{"type":"user"}'
}

teardown() {
    [[ -s ${HOME}/pids ]] || return 0
    xargs kill <"${HOME}/pids" 2>/dev/null || true
}

# transcript <id> <json line>...: the session's transcript, one record a line.
transcript() {
    local id=$1
    shift
    mkdir -p "${HOME}/.claude/projects/-p"
    printf '%s\n' "$@" >"${HOME}/.claude/projects/-p/${id}.jsonl"
}

move_setup() {
    two_accounts
    stub_herdr
    : >"${HOME}/panes"
    mkdir -p "${XDG_STATE_HOME}/claude-as"
    export STUB_MOVED_HOME="${HOME}/.claude-home"
    # The command a pane runs names this very script.
    ME="'$(cd "$(dirname "$SCRIPT")" && pwd -P)/claude-as'"
    # No Bash tool jobs unless a test says so.
    stub_bin pgrep 'exit 1'
}

@test "--move resumes each Claude session in herdr as the account, by this script's own path" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    run "$SCRIPT" --move me@home.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"w1:p1: ${SID} moved to me@home.example"* ]]
    grep -q "herdr agent prompt w1:p1 /exit" "${HOME}/herdr.log"
    grep -qF "herdr pane run w1:p1 CLAUDE_AS_CONFIRMED=${SID} ${ME} me@home.example --resume ${SID}" "${HOME}/herdr.log"
    grep -q "RAN set=1 home=${HOME}/.claude-home args=--allow-dangerously-skip-permissions --resume ${SID}" "${HOME}/pane-out"
    # How to finish it is written down before /exit, and dropped once it runs.
    grep -qF "w1:p1	${SID}	CLAUDE_AS_CONFIRMED=${SID} ${ME} me@home.example --resume ${SID}" "${HOME}/at-exit"
    ! compgen -G "${XDG_STATE_HOME}/claude-as/*.resume"
}

@test "--move keeps bypass on with other flags, as claude reads it, and leaves a launcher's --settings behind" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}" "claude --settings /s/menu/1.json --model opus --dangerously-skip-permissions --mcp-config /m.json --resume ${SID}"
    run "$SCRIPT" --move me@home.example
    [ "$status" -eq 0 ]
    grep -qF "${ME} me@home.example -a --model='opus' --resume ${SID}" "${HOME}/herdr.log"
    # What claude itself receives: the bypass flag, never a bare -a.
    grep -q "args=--dangerously-skip-permissions --model=opus --resume ${SID}$" "${HOME}/pane-out"
    ! grep -q -- " -a \|--settings\|--mcp-config" "${HOME}/pane-out"
    # A mode the session switched to since goes first as well.
    : >"${HOME}/panes" && : >"${HOME}/pane-out"
    pane w1:p1 idle "${SID}" "claude --model opus --resume ${SID}"
    transcript "${SID}" '{"permissionMode":"bypassPermissions"}'
    ran "${SID}" "${HOME}/.claude"
    run "$SCRIPT" --move me@home.example
    grep -q "args=--dangerously-skip-permissions --model=opus --resume ${SID}$" "${HOME}/pane-out"
}

@test "--move takes a model with brackets whole, as both fish and claude read it" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}" "claude --model claude-opus-5-5[1m] --resume ${SID}"
    run "$SCRIPT" --move me@home.example
    grep -qF "${ME} me@home.example --model='claude-opus-5-5[1m]' --resume ${SID}" "${HOME}/herdr.log"
    grep -qF "args=--allow-dangerously-skip-permissions --model=claude-opus-5-5[1m] --resume ${SID}" "${HOME}/pane-out"
    if command -v fish >/dev/null 2>&1; then
        fish --no-execute -c "$(grep -oE "CLAUDE_AS_CONFIRMED=.*" "${HOME}/herdr.log")"
    fi
}

@test "--move trusts the session claude's own process records over herdr's" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    local pid
    pid=$(cut -f5 "${HOME}/panes")
    mkdir -p "${HOME}/.claude/sessions"
    # A `claude -p` from the pane's Bash tool left herdr naming its session.
    printf '{"pid":%s,"sessionId":"4c3b2a1d-0000-4000-8000-000000000001"}\n' "${pid}" >"${HOME}/.claude/sessions/${pid}.json"
    run "$SCRIPT" --move me@home.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"left alone: herdr names session ${SID}, but its claude (pid ${pid}) runs 4c3b2a1d-0000-4000-8000-000000000001"* ]]
    ! grep -q "agent prompt" "${HOME}/herdr.log"
    # When they agree, it moves.
    printf '{"pid":%s,"sessionId":"%s"}\n' "${pid}" "${SID}" >"${HOME}/.claude/sessions/${pid}.json"
    run "$SCRIPT" --move me@home.example
    [[ ${output} == *"w1:p1: ${SID} moved to me@home.example"* ]]
}

@test "--move leaves a session with no transcript to resume alone" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    rm "${HOME}/.claude/projects/-p/${SID}.jsonl"
    run "$SCRIPT" --move me@home.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"${SID} left alone: it has no transcript to resume"* ]]
    ! grep -q "agent prompt" "${HOME}/herdr.log"
}

@test "--move leaves a session already on that account alone" {
    move_setup
    ran "${SID}" "${HOME}/.claude-home"
    pane w1:p1 idle "${SID}"
    run "$SCRIPT" --move me@home.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"already runs as me@home.example"* ]]
    ! grep -q "agent prompt" "${HOME}/herdr.log"
}

@test "--move --dry-run says what it would run and touches nothing" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    run "$SCRIPT" --move me@home.example --dry-run
    [ "$status" -eq 0 ]
    [[ ${output} == *"w1:p1: would move ${SID} from me@work.example to me@home.example"* ]]
    [[ ${output} == *"by running: CLAUDE_AS_CONFIRMED=${SID} ${ME} me@home.example --resume ${SID}"* ]]
    ! grep -q "agent prompt\|pane run" "${HOME}/herdr.log"
}

@test "--move resumes in the permission mode the session is in now, not the one it started in" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    transcript "${SID}" '{"cwd":"/","permissionMode":"default"}' '{"permissionMode":"bypassPermissions"}'
    run "$SCRIPT" --move me@home.example --dry-run
    [[ ${output} == *"me@home.example -a --resume ${SID}"* ]]
    transcript "${SID}" '{"permissionMode":"acceptEdits"}'
    run "$SCRIPT" --move me@home.example --dry-run
    [[ ${output} == *"me@home.example --permission-mode='acceptEdits' --resume ${SID}"* ]]
    # Launched with -a, switched back to the default since.
    : >"${HOME}/panes"
    pane w1:p1 idle "${SID}" "claude --dangerously-skip-permissions --model opus --resume ${SID}"
    transcript "${SID}" '{"permissionMode":"default"}'
    run "$SCRIPT" --move me@home.example --dry-run
    [[ ${output} == *"me@home.example --model='opus' --resume ${SID}"* ]]
    # No mode recorded: the launch flag stands.
    transcript "${SID}" '{"cwd":"/"}'
    run "$SCRIPT" --move me@home.example --dry-run
    [[ ${output} == *"me@home.example -a --model='opus' --resume ${SID}"* ]]
}

@test "--move resumes in the folder the session was launched in" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    mkdir -p "${HOME}/work tree/sub"
    pane w1:p1 idle "${SID}"
    transcript "${SID}" "{\"cwd\":\"${HOME}/work tree\"}" "{\"cwd\":\"${HOME}/work tree/sub\"}"
    run "$SCRIPT" --move me@home.example
    grep -qF "herdr pane run w1:p1 cd '${HOME}/work tree' && CLAUDE_AS_CONFIRMED=${SID}" "${HOME}/herdr.log"
}

@test "--move never puts a folder a shell would read differently into the command" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    mkdir -p "${HOME}/a\\b"
    pane w1:p1 idle "${SID}"
    transcript "${SID}" "{\"cwd\":\"${HOME}/a\\\\b\"}"
    run "$SCRIPT" --move me@home.example --dry-run
    [[ ${output} == *"cannot resume from ${HOME}/a\\b; using the pane's folder"* ]]
    [[ ${output} == *"by running: CLAUDE_AS_CONFIRMED="* ]]
}

@test "--move leaves a session whose Bash tool runs jobs alone, unless --force names its pane" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    stub_bin pgrep 'case "$2" in 7001) echo 7002 ;; 7002) exit 1 ;; *) echo 7001 ;; esac'
    stub_bin ps 'case "$4" in 7001) echo "bash -c source /h/.claude/shell-snapshots/snapshot-bash-1.sh" ;; 7002) echo "ng serve --port 4200" ;; esac'
    run "$SCRIPT" --move me@home.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"left alone: its Bash tool runs jobs that would end with it"* ]]
    [[ ${output} == *"ng serve --port 4200"* ]]
    ! grep -q "agent prompt" "${HOME}/herdr.log"
    run "$SCRIPT" --move me@home.example --pane w1:p1 --force
    [[ ${output} == *"w1:p1: ${SID} moved to me@home.example"* ]]
}

@test "--move leaves a session whose claude process herdr cannot show alone, unless --force" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}" -
    run "$SCRIPT" --move me@home.example
    [[ ${output} == *"herdr shows no claude process, so its jobs cannot be checked"* ]]
    ! grep -q "agent prompt" "${HOME}/herdr.log"
    run "$SCRIPT" --move me@home.example --pane w1:p1 --force
    [[ ${output} == *"moved to me@home.example"* ]]
}

@test "--move leaves a session still busy after --wait alone, and fails" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 working "${SID}"
    run "$SCRIPT" --move me@home.example --wait 0
    [ "$status" -eq 1 ]
    [[ ${output} == *"still busy after 0 s, or gone; left alone"* ]]
    [[ ${output} == *"1 session(s) not moved"* ]]
    ! grep -q "agent prompt" "${HOME}/herdr.log"
}

@test "--move stopped while it waits for a busy agent stops at once and moves no other" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    ran 4c3b2a1d-0000-4000-8000-000000000001 "${HOME}/.claude"
    pane w1:p1 working "${SID}"
    pane w1:p2 working 4c3b2a1d-0000-4000-8000-000000000001
    "$SCRIPT" --move me@home.example --wait 300 >"${HOME}/out" 2>&1 &
    local pid=$! i
    sleep 2
    kill -TERM "${pid}"
    for ((i = 0; i < 20; i++)); do
        kill -0 "${pid}" 2>/dev/null || break
        sleep 0.5
    done
    ! kill -0 "${pid}" 2>/dev/null
    grep -q "w1:p1: ${SID} left alone: stopping" "${HOME}/out"
    grep -q "stopped; the sessions after w1:p1 were not moved" "${HOME}/out"
    ! grep -q "w1:p2" "${HOME}/out"
    ! grep -q "agent prompt" "${HOME}/herdr.log"
}

@test "--move leaves an agent at a dialog as it was" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    touch "${HOME}/dialog-w1:p1"
    run "$SCRIPT" --move me@home.example
    [ "$status" -eq 1 ]
    [[ ${output} == *"did not take /exit (a dialog open?); left as it was"* ]]
    ! grep -q "pane run" "${HOME}/herdr.log"
    # It never exited, so there is nothing to resume.
    ! compgen -G "${XDG_STATE_HOME}/claude-as/*.resume"
    [[ ${output} != *"exited and not resumed"* ]]
}

@test "--move reports a session that came back under another account" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    pane w1:p1 idle "${SID}"
    STUB_MOVED_HOME="${HOME}/.claude" run "$SCRIPT" --move me@home.example
    [ "$status" -eq 1 ]
    [[ ${output} == *"came back, but its record says me@work.example, not me@home.example"* ]]
}

@test "--move started from an agent's pane runs on detached and moves that pane last" {
    move_setup
    ran "${SID}" "${HOME}/.claude"
    ran 4c3b2a1d-0000-4000-8000-000000000001 "${HOME}/.claude"
    pane w1:p2 idle 4c3b2a1d-0000-4000-8000-000000000001
    pane w1:p1 idle "${SID}"
    HERDR_ENV=1 HERDR_PANE_ID=w1:p2 run "$SCRIPT" --move me@home.example
    [ "$status" -eq 0 ]
    [[ ${output} == *"moving in the background, this pane last"* ]]
    [[ ${output} == *"stop it between sessions with: kill "* ]]
    local log i
    for ((i = 0; i < 40; i++)); do
        log=$(ls "${XDG_STATE_HOME}"/claude-as/move-2*.log 2>/dev/null | head -1)
        [[ -n ${log} ]] && grep -q "w1:p2: .* moved to" "${log}" && break
        sleep 0.5
    done
    grep -q "w1:p1: ${SID} moved to me@home.example" "${log}"
    grep -q "w1:p2: 4c3b2a1d-0000-4000-8000-000000000001 moved to me@home.example" "${log}"
    # The calling pane last, after every other.
    [ "$(grep -n 'moved to' "${log}" | tail -1 | grep -c w1:p2)" -eq 1 ]
}

@test "a confirmation from --move answers for its session only, and never reaches claude" {
    two_accounts
    ran "${SID}" "${HOME}/.claude"
    CLAUDE_AS_CONFIRMED="${SID}" run "$SCRIPT" me@home.example -r "${SID}"
    [[ ${output} == *"continuing it as me@home.example"* ]]
    [[ ${output} == *"CONFIRMED=unset"* ]]
}

@test "--move needs herdr, an account and known options" {
    two_accounts
    run "$SCRIPT" --move
    [ "$status" -eq 2 ]
    run "$SCRIPT" --move me@home.example --bogus
    [ "$status" -eq 2 ]
    [[ ${output} == *"unknown option --bogus"* ]]
    PATH="${STUB_DIR}:/usr/bin:/bin" run "$SCRIPT" --move me@home.example
    [[ ${output} == *"needs herdr"* ]]
}
