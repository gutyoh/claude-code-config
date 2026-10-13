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

@test "an email, any part of one, in any case, names its account" {
    two_accounts
    for who in me@home.example home.example HOME ME@HOME.EXAMPLE; do
        run "$SCRIPT" "${who}" -p hi
        [ "$status" -eq 0 ]
        [[ ${output} == *"home=${HOME}/.claude-home args=-p hi"* ]] || {
            echo "${who}: ${output}"
            return 1
        }
    done
}

@test "a part that names several accounts or none is refused" {
    two_accounts
    run "$SCRIPT" me@ -p hi
    [ "$status" -eq 1 ]
    [[ ${output} == *"names 2 accounts"* ]]
    [[ ${output} == *"me@work.example"* && ${output} == *"me@home.example"* ]]
    [[ ${output} != *RAN* ]]
    run "$SCRIPT" nobody -p hi
    [ "$status" -eq 1 ]
    [[ ${output} == *"no account matches 'nobody'"* ]]
}

@test "one email in two organizations takes /organization or /plan" {
    account "${HOME}/.claude" me@x.example claude_team Acme
    linked_home "${HOME}/.claude-x" me@x.example claude_pro Personal
    run "$SCRIPT" me@x.example -p hi
    [ "$status" -eq 1 ]
    [[ ${output} == *"names 2 accounts"* ]]
    run "$SCRIPT" me@x.example/acme -p hi
    [[ ${output} == *"RAN set= home= args=-p hi"* ]]
    run "$SCRIPT" me/pro -p hi
    [[ ${output} == *"home=${HOME}/.claude-x args=-p hi"* ]]
}

@test "~/.claude runs with CLAUDE_CONFIG_DIR unset, others with their exact path" {
    two_accounts
    CLAUDE_CONFIG_DIR="${HOME}/.claude-home" run "$SCRIPT" work.example doctor
    [[ ${output} == *"RAN set= home= args=doctor"* ]]
    CLAUDE_CONFIG_DIR="${HOME}/.claude" run "$SCRIPT" home.example doctor
    [[ ${output} == *"RAN set=1 home=${HOME}/.claude-home args=doctor"* ]]
}

@test "CLAUDE_AS chooses the account when claude options come first" {
    two_accounts
    CLAUDE_AS=home run "$SCRIPT" --continue
    [[ ${output} == *"home=${HOME}/.claude-home args=--continue"* ]]
    CLAUDE_AS=home run "$SCRIPT"
    [[ ${output} == *"home=${HOME}/.claude-home args="* ]]
    run "$SCRIPT" --continue
    [ "$status" -eq 2 ]
    [[ ${output} == *"name the account first"* ]]
}

@test "another account's credentials are dropped; a gateway's is named, never shown" {
    two_accounts
    CLAUDE_CODE_OAUTH_TOKEN=secret-value-1 ANTHROPIC_API_KEY=secret-value-2 \
        CLAUDE_SECURESTORAGE_CONFIG_DIR=/elsewhere ANTHROPIC_AUTH_TOKEN=secret-value-3 \
        run "$SCRIPT" home doctor
    [[ ${output} == *"ENV oauth=unset key=unset store=unset"* ]]
    [[ ${output} == *"warning: ANTHROPIC_AUTH_TOKEN set"* ]]
    [[ ${output} != *secret-value* ]]
    CLAUDE_CODE_OAUTH_TOKEN=secret-value-1 run "$SCRIPT" work doctor
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
    [[ ${output} == *"Ready: claude-as New@Home.example/pro"* ]]
    run "$SCRIPT" new@home -p hi
    [[ ${output} == *"home=${h} args=-p hi"* ]]
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
    [[ ${output} == *"claude-as <who> [claude args]"* ]]
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
    run "$SCRIPT" me@x -p hi
    [ "$status" -eq 0 ]
    [[ ${output} == *"one account in 2 homes; using ~/.claude"* ]]
    [[ ${output} == *"RAN set= home= args=-p hi"* ]]
}

@test "a home's path names it directly" {
    account "${HOME}/.claude" me@x.example claude_team Acme
    linked_home "${HOME}/.claude-copy" me@x.example claude_team Acme
    run "$SCRIPT" '~/.claude-copy' -p hi
    [[ ${output} == *"home=${HOME}/.claude-copy args=-p hi"* ]]
    run "$SCRIPT" "${HOME}/.claude-copy/" -p hi
    [[ ${output} == *"home=${HOME}/.claude-copy args=-p hi"* ]]
    run "$SCRIPT" "${HOME}/.claude" -p hi
    [[ ${output} == *"RAN set= home= args=-p hi"* ]]
    run "$SCRIPT" '~/.nope' -p hi
    [ "$status" -eq 1 ]
    [[ ${output} == *"is not a home"* ]]
}
