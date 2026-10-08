#!/usr/bin/env bats
# statusline-credentials.bats
# Path: tests/statusline-credentials.bats
#
# get_oauth_token() on Linux: a desktop keyring when present, otherwise the
# credentials file Claude Code writes on headless hosts.
#
# Run: bats tests/statusline-credentials.bats

MODULES_DIR="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    debug() { :; }
    KEYCHAIN_SERVICE="Claude Code-credentials"
    PLATFORM="$(detect_test_platform)"
    # These pin the Linux branch; macOS reads the Keychain and has its own path.
    [[ "$PLATFORM" == "linux" ]] || skip "Linux credential lookup"
    source "$MODULES_DIR/api.sh"
    unset CLAUDE_CONFIG_DIR
    mkdir -p "$HOME/.claude"
}

creds() { printf '{"claudeAiOauth":{"accessToken":"%s"}}' "$1"; }

@test "linux without a keyring reads ~/.claude/.credentials.json" {
    require_cmd jq
    # Drop only the PATH entries that hold secret-tool. A fixed /usr/bin:/bin
    # also loses jq wherever it lives elsewhere (NixOS, version-manager shims).
    NOKEYRING_PATH=""
    local dir dirs
    IFS=: read -ra dirs <<<"$PATH"
    for dir in "${dirs[@]}"; do
        [[ -x "${dir}/secret-tool" ]] || NOKEYRING_PATH+="${NOKEYRING_PATH:+:}${dir}"
    done
    no_keyring_token() { PATH="$NOKEYRING_PATH" get_oauth_token; }
    creds file-token >"$HOME/.claude/.credentials.json"
    run no_keyring_token
    [ "$status" -eq 0 ]
    [ "$output" = "file-token" ]
}

@test "linux honors CLAUDE_CONFIG_DIR for the credentials file" {
    export CLAUDE_CONFIG_DIR="$HOME/.claude-work"
    mkdir -p "$CLAUDE_CONFIG_DIR"
    creds work-token >"$CLAUDE_CONFIG_DIR/.credentials.json"
    creds wrong-token >"$HOME/.claude/.credentials.json"
    stub_bin secret-tool 'exit 1'
    run get_oauth_token
    [ "$status" -eq 0 ]
    [ "$output" = "work-token" ]
}

@test "linux prefers the keyring when it answers" {
    stub_bin secret-tool "printf '%s' '$(creds keyring-token)'"
    creds file-token >"$HOME/.claude/.credentials.json"
    run get_oauth_token
    [ "$status" -eq 0 ]
    [ "$output" = "keyring-token" ]
}

@test "linux with neither source fails instead of printing nothing" {
    stub_bin secret-tool 'exit 1'
    run get_oauth_token
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}
