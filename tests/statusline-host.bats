#!/usr/bin/env bats
# statusline-host.bats
# Path: tests/statusline-host.bats
#
# The host component names the machine a session runs on, and statusline.d
# lets a tool that manages the machine color it without editing the user's
# own files.

STATUSLINE="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"
ESC=$'\033'

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    # Never the real Keychain: a lookup there can raise an administrator
    # prompt or read a real login.
    stub_bin security 'exit 44'
    stub_bin curl 'exit 7'
    export TMPDIR="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.claude/statusline.d"
    printf '{"oauthAccount":{"emailAddress":"user@example.com"}}' >"$HOME/.claude.json"
    printf 'components=email,host\ntheme=none\n' >"$HOME/.claude/statusline.conf"
}

render() { # HOSTNAME value, then extra env assignments
    local name="$1"
    shift
    run env HOSTNAME="${name}" COLUMNS=200 COLORTERM=truecolor "$@" bash "$STATUSLINE" \
        <<<'{"model":{"id":"claude-opus-5-5"},"session_id":"s1"}'
}

# bats test_tags=unit
@test "the host follows the email" {
    render devbox
    [ "$status" -eq 0 ]
    [ "$output" = "user@example.com | devbox" ]
}

# bats test_tags=unit
@test "a domain or .local suffix is cut at the first dot" {
    render laptop.local
    [ "$output" = "user@example.com | laptop" ]
    render build-01.corp.example.com
    [ "$output" = "user@example.com | build-01" ]
}

# bats test_tags=unit
@test "a renamed machine shows its new name with no config change" {
    render old-name
    [ "$output" = "user@example.com | old-name" ]
    render new-name
    [ "$output" = "user@example.com | new-name" ]
}

# bats test_tags=unit
@test "a host icon from statusline.d goes before the name, with one space" {
    printf 'host_icon=\xef\x85\xb9\n' >"$HOME/.claude/statusline.d/machine.conf"
    render laptop.local
    [ "$output" = "user@example.com | $(printf '\xef\x85\xb9') laptop" ]
    printf 'host_icon=\xf3\xb0\xb0\x96\n' >"$HOME/.claude/statusline.d/machine.conf"
    render devbox
    [ "$output" = "user@example.com | $(printf '\xf3\xb0\xb0\x96') devbox" ]
}

# bats test_tags=unit
@test "without a host icon the name stands alone, and an empty one adds no space" {
    render devbox
    [ "$output" = "user@example.com | devbox" ]
    printf 'host_icon=\n' >"$HOME/.claude/statusline.d/machine.conf"
    render devbox
    [ "$output" = "user@example.com | devbox" ]
}

# bats test_tags=unit
@test "the host style colors the icon and the name together" {
    printf 'theme=dark\nhost_icon=*\nstyle.host=bold fg:#C74634\n' >"$HOME/.claude/statusline.d/machine.conf"
    render devbox
    [[ "$output" == *"${ESC}[1;38;2;199;70;52m* devbox${ESC}[0m"* ]]
}

# bats test_tags=unit
@test "without HOSTNAME the kernel's node name is used" {
    stub_bin uname 'if [ "$1" = -n ]; then echo node-7.lan; else echo Linux; fi'
    render ""
    [ "$output" = "user@example.com | node-7" ]
}

# bats test_tags=unit
@test "the host is shown only when components names it" {
    printf 'components=email\ntheme=none\n' >"$HOME/.claude/statusline.conf"
    render devbox
    [ "$output" = "user@example.com" ]
}

# bats test_tags=unit
@test "a style in statusline.d colors the host" {
    printf 'style.host=bold fg:#C74634\n' >"$HOME/.claude/statusline.d/machine.conf"
    render devbox
    [ "$output" = "user@example.com | ${ESC}[1;38;2;199;70;52mdevbox${ESC}[0m" ]
}

# bats test_tags=unit
@test "statusline.d overrides statusline.conf, and statusline.local.conf overrides both" {
    printf 'components=email,host\ntheme=none\nstyle.host=fg:#111111\n' >"$HOME/.claude/statusline.conf"
    printf 'style.host=fg:#222222\n' >"$HOME/.claude/statusline.d/machine.conf"
    render devbox
    [ "$output" = "user@example.com | ${ESC}[38;2;34;34;34mdevbox${ESC}[0m" ]
    printf 'style.host=fg:#333333\n' >"$HOME/.claude/statusline.local.conf"
    render devbox
    [ "$output" = "user@example.com | ${ESC}[38;2;51;51;51mdevbox${ESC}[0m" ]
}

# bats test_tags=unit
@test "drop-in files are read in name order, the last one winning" {
    printf 'style.host=fg:#111111\n' >"$HOME/.claude/statusline.d/10-first.conf"
    printf 'style.host=fg:#222222\n' >"$HOME/.claude/statusline.d/20-second.conf"
    render devbox
    [ "$output" = "user@example.com | ${ESC}[38;2;34;34;34mdevbox${ESC}[0m" ]
}

# bats test_tags=unit
@test "only *.conf files in statusline.d are read" {
    printf 'style.host=fg:#111111\n' >"$HOME/.claude/statusline.d/machine.conf.bak"
    printf 'style.host=fg:#111111\n' >"$HOME/.claude/statusline.d/.machine.conf.workstation-tmp"
    render devbox
    [ "$output" = "user@example.com | devbox" ]
}

# bats test_tags=unit
@test "a missing or empty statusline.d changes nothing" {
    render devbox
    [ "$output" = "user@example.com | devbox" ]
    rmdir "$HOME/.claude/statusline.d"
    render devbox
    [ "$output" = "user@example.com | devbox" ]
}

# bats test_tags=unit
@test "a drop-in can set any key, not only styles" {
    printf 'components=host\n' >"$HOME/.claude/statusline.d/machine.conf"
    render devbox
    [ "$output" = "devbox" ]
}

# bats test_tags=unit
@test "statusline.d is read from the profile's CLAUDE_CONFIG_DIR" {
    mkdir -p "$HOME/.claude-work/statusline.d"
    printf 'components=host\ntheme=none\n' >"$HOME/.claude-work/statusline.conf"
    printf 'style.host=fg:#3DDC84\n' >"$HOME/.claude-work/statusline.d/machine.conf"
    render devbox CLAUDE_CONFIG_DIR="$HOME/.claude-work"
    [ "$output" = "${ESC}[38;2;61;220;132mdevbox${ESC}[0m" ]
}

# bats test_tags=unit
@test "NO_COLOR leaves the host plain" {
    printf 'style.host=bold fg:#C74634\n' >"$HOME/.claude/statusline.d/machine.conf"
    render devbox NO_COLOR=1
    [ "$output" = "user@example.com | devbox" ]
}

# bats test_tags=unit
@test "claude-as shares statusline.d across accounts" {
    grep -Eq '^SHARE=".*statusline\.d' "$BATS_TEST_DIRNAME/../bin/claude-as"
}
