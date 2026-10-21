#!/usr/bin/env bats
# statusline-keychain.bats
# Path: tests/statusline-keychain.bats
#
# get_oauth_token() on macOS asks the Keychain only for Claude Code's own
# service. An empty service name would match the first password item of any
# kind, System keychain items included, which raises an administrator prompt
# or hands back an unrelated secret.
#
# Run: bats tests/statusline-keychain.bats

MODULES_DIR="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    debug() { :; }
    PLATFORM=macos
    LOG="$BATS_TEST_TMPDIR/security.log"
    stub_bin security "echo \"\$*\" >>'${LOG}'; printf '%s' '{\"claudeAiOauth\":{\"accessToken\":\"tok\"}}'"
    source "$MODULES_DIR/api.sh"
    unset CLAUDE_CONFIG_DIR
}

# bats test_tags=unit
@test "an empty keychain service never queries the Keychain" {
    KEYCHAIN_SERVICE=""
    run get_oauth_token
    [ "$status" -ne 0 ]
    [ ! -e "$LOG" ]
}

# bats test_tags=unit
@test "the named service is the only one asked for" {
    KEYCHAIN_SERVICE="Claude Code-credentials"
    run get_oauth_token
    [ "$status" -eq 0 ]
    [ "$output" = "tok" ]
    [ "$(cat "$LOG")" = "find-generic-password -s Claude Code-credentials -w" ]
}

# bats test_tags=unit
@test "isolate_home's default security stub answers nothing" {
    rm -f "$LOG"
    stub_bin security 'exit 44'
    KEYCHAIN_SERVICE="Claude Code-credentials"
    run get_oauth_token
    [ "$status" -ne 0 ]
}
