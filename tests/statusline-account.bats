#!/usr/bin/env bats
# statusline-account.bats
# Path: tests/statusline-account.bats
#
# The email component reads the account of the home Claude Code runs in.

STATUSLINE="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    stub_bin curl 'exit 7'
    stub_bin ccusage 'echo "{\"blocks\":[]}"'
    export TMPDIR="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.claude" "$HOME/.claude-work"
    printf 'components=email\ntheme=none\n' >"$HOME/.claude/statusline.conf"
    cp "$HOME/.claude/statusline.conf" "$HOME/.claude-work/statusline.conf"
    printf '{"oauthAccount":{"emailAddress":"default@example.com"}}' >"$HOME/.claude.json"
    printf '{"oauthAccount":{"emailAddress":"work@example.com"}}' >"$HOME/.claude-work/.claude.json"
}

email() { # CLAUDE_CONFIG_DIR value, or nothing for unset
    if [[ $# -gt 0 ]]; then
        run env CLAUDE_CONFIG_DIR="$1" COLUMNS=200 bash "$STATUSLINE" <<<'{"model":{"id":"claude-opus-5-5"}}'
    else
        run env -u CLAUDE_CONFIG_DIR COLUMNS=200 bash "$STATUSLINE" <<<'{"model":{"id":"claude-opus-5-5"}}'
    fi
}

# bats test_tags=unit
@test "unset: the default home's account beside ~/.claude" {
    email
    [ "$output" = "default@example.com" ]
}

# bats test_tags=unit
@test "another home: its own .claude.json" {
    email "$HOME/.claude-work"
    [ "$output" = "work@example.com" ]
}

# bats test_tags=unit
@test "the default home named explicitly, with or without a trailing slash, still finds its account" {
    email "$HOME/.claude"
    [ "$output" = "default@example.com" ]
    email "$HOME/.claude/"
    [ "$output" = "default@example.com" ]
}

# bats test_tags=unit
@test "the default home named explicitly prefers a .claude.json inside it" {
    printf '{"oauthAccount":{"emailAddress":"inside@example.com"}}' >"$HOME/.claude/.claude.json"
    email "$HOME/.claude"
    [ "$output" = "inside@example.com" ]
}

# bats test_tags=unit
@test "another home without an account shows N/A, never the default's" {
    rm "$HOME/.claude-work/.claude.json"
    email "$HOME/.claude-work"
    [ "$output" = "N/A" ]
}
