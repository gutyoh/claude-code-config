#!/usr/bin/env bats
# code-mode.bats
# Path: tests/code-mode.bats
#
# Experimental features are one env switch each in settings.json. Code Mode
# changes only when asked: its sessions run without Remote Control, so a
# rerun of setup must never flip it. Turned on, every account's one-time
# answer is recorded through claude-as --relink.
#
# Run: bats tests/code-mode.bats

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd python3
    require_cmd jq
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    mkdir -p "${HOME}/.claude"
    SETTINGS_JSON="${HOME}/.claude/settings.json"
    export SETTINGS_JSON
    unset CLAUDE_CODE_EXPERIMENTAL_CODE_MODE CLAUDE_CONFIG_DIR CLAUDE_AS_HOMES CLAUDE_AS_SHARED
    # shellcheck source=../lib/setup/settings.sh
    source "${REPO_DIR}/lib/setup/settings.sh"
}

env_of() { jq -c '.env // "none"' "$SETTINGS_JSON"; }

# bats test_tags=unit
@test "set_settings_env turns a switch on beside what is there, once" {
    printf '{"env": {"OTHER": "x"}, "hooks": {}}\n' >"$SETTINGS_JSON"
    run set_settings_env true CLAUDE_CODE_EXPERIMENTAL_CODE_MODE "Code Mode"
    [ "$status" -eq 0 ]
    [[ ${output} == *"Code Mode enabled"* ]]
    [ "$(env_of)" = '{"OTHER":"x","CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}' ]
    [ "$(jq -c .hooks "$SETTINGS_JSON")" = '{}' ]
    cp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
    run set_settings_env true CLAUDE_CODE_EXPERIMENTAL_CODE_MODE "Code Mode"
    [[ ${output} == *"Code Mode already enabled"* ]]
    cmp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
}

# bats test_tags=unit
@test "set_settings_env turns a switch off, dropping an env left empty" {
    printf '{"env": {"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "1"}}\n' >"$SETTINGS_JSON"
    run set_settings_env false CLAUDE_CODE_EXPERIMENTAL_CODE_MODE "Code Mode"
    [ "$status" -eq 0 ]
    [[ ${output} == *"Code Mode disabled (removed from settings)"* ]]
    [ "$(env_of)" = '"none"' ]
    run set_settings_env false CLAUDE_CODE_EXPERIMENTAL_CODE_MODE "Code Mode"
    [[ ${output} == *"Code Mode not enabled (nothing to remove)"* ]]
}

# bats test_tags=unit
@test "set_settings_env fails on a settings file it cannot read, leaving it as it was" {
    printf 'not json\n' >"$SETTINGS_JSON"
    run set_settings_env true CLAUDE_CODE_EXPERIMENTAL_CODE_MODE "Code Mode"
    [ "$status" -eq 1 ]
    [[ ${output} == *"Failed to configure code mode"* ]]
    [ "$(cat "$SETTINGS_JSON")" = "not json" ]
}

# bats test_tags=unit
@test "agent teams still turn on and off through the shared switch" {
    printf '{}\n' >"$SETTINGS_JSON"
    INSTALL_AGENT_TEAMS=true run configure_agent_teams
    [[ ${output} == *"Agent teams enabled"* ]]
    [ "$(env_of)" = '{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}' ]
    INSTALL_AGENT_TEAMS=false run configure_agent_teams
    [[ ${output} == *"Agent teams disabled"* ]]
    [ "$(env_of)" = '"none"' ]
}

# bats test_tags=unit
@test "a rerun without --code-mode or --no-code-mode leaves Code Mode as it is" {
    printf '{}\n' >"$SETTINGS_JSON"
    INSTALL_CODE_MODE="" run configure_code_mode
    [ "$status" -eq 0 ]
    [[ ${output} == *"Code Mode left off"* ]]
    [ "$(env_of)" = '"none"' ]
    printf '{"env": {"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE": "1"}}\n' >"$SETTINGS_JSON"
    INSTALL_CODE_MODE="" run configure_code_mode
    [[ ${output} == *"Code Mode left on"* ]]
    [ "$(env_of)" = '{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}' ]
}

# bats test_tags=unit
@test "--code-mode records every account's answer; --no-code-mode records none" {
    printf '{}\n' >"$SETTINGS_JSON"
    printf '{"oauthAccount": {"emailAddress": "me@work.example"}}\n' >"${HOME}/.claude.json"
    INSTALL_CODE_MODE=false run configure_code_mode
    [ "$status" -eq 0 ]
    [[ ${output} != *accepted* ]]
    run jq -e 'has("codeModeCaveatsAcceptedV1")' "${HOME}/.claude.json"
    [ "$status" -ne 0 ]
    INSTALL_CODE_MODE=true run configure_code_mode
    [ "$status" -eq 0 ]
    [[ ${output} == *"Code Mode enabled"* ]]
    [[ ${output} == *"  accepted    Code Mode for ~/.claude"* ]]
    jq -e '.codeModeCaveatsAcceptedV1 and .codeModeAutoModeCaveatAcceptedV1
        and .oauthAccount.emailAddress == "me@work.example"' "${HOME}/.claude.json"
}

# bats test_tags=unit
@test "both installers offer Code Mode in every settings mode, and only when asked" {
    [ "$(grep -c '^ *configure_code_mode$' "${REPO_DIR}/setup.sh")" -eq 2 ]
    [ "$(grep -c '^ *Update-CodeMode$' "${REPO_DIR}/setup.ps1")" -eq 2 ]
    grep -q '^INSTALL_CODE_MODE=""' "${REPO_DIR}/setup.sh"
    grep -q '^\$script:InstallCodeModeFlag = \$null' "${REPO_DIR}/setup.ps1"
}
