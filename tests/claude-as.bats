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
    unset CLAUDE_AS CLAUDE_AS_HOMES CLAUDE_AS_SHARED CLAUDE_AS_SHARE
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
    grep -q 'command claude --allow-dangerously-skip-permissions' "$BATS_TEST_DIRNAME/../lib/setup/settings.sh"
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
