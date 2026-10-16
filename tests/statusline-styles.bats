#!/usr/bin/env bats
# statusline-styles.bats
# Path: tests/statusline-styles.bats
#
# style.<component>= in statusline.conf colors one component with a Starship
# style string, so each profile can tell itself apart, say by its email.

STATUSLINE="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"
ESC=$'\033'

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    stub_bin curl 'exit 7'
    stub_bin ccusage 'echo "{\"blocks\":[]}"'
    export TMPDIR="$BATS_TEST_TMPDIR"
    mkdir -p "$HOME/.claude"
    printf '{"oauthAccount":{"emailAddress":"user@example.com"}}' >"$HOME/.claude.json"
}

conf() {
    printf 'components=model,email\ntheme=none\n%s\n' "$@" >"$HOME/.claude/statusline.conf"
}

render() { # extra env assignments
    run env COLUMNS=200 "$@" bash "$STATUSLINE" \
        <<<'{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"session_id":"s1"}'
}

# Sources only the style helpers, as statusline.sh does.
sgr() { # style [COLORTERM]
    run env COLORTERM="${2:-}" bash -c 'source "$1"; style_sgr "$2"; printf "%s" "$REPLY"' _ \
        "$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/style.sh" "$1"
}

# Styles text through style_component alone: style text COLORTERM.
sgr_component() {
    run env COLORTERM="$3" bash -c 'source "$1"; style_component "$2" "$3"; printf "%s" "$REPLY"' _ \
        "$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/style.sh" "$1" "$2"
}

# bats test_tags=unit
@test "a hex background and foreground render in truecolor when the terminal says so" {
    conf 'style.email=bold fg:#1E1E2E bg:#EB4789'
    render COLORTERM=truecolor
    [ "$status" -eq 0 ]
    [ "$output" = "opus-5.5 | ${ESC}[1;38;2;30;30;46;48;2;235;71;137muser@example.com${ESC}[0m" ]
}

# bats test_tags=unit
@test "a hex color falls back to the nearest 256-color index without truecolor" {
    conf 'style.email=bg:#EB4789'
    render COLORTERM=
    [ "$output" = "opus-5.5 | ${ESC}[48;5;204muser@example.com${ESC}[0m" ]
}

# bats test_tags=unit
@test "NO_COLOR leaves a styled component plain" {
    conf 'style.email=bold bg:#EB4789'
    render NO_COLOR=1
    [ "$output" = "opus-5.5 | user@example.com" ]
}

# bats test_tags=unit
@test "only the named component is styled" {
    conf 'style.model=italic'
    render
    [ "$output" = "${ESC}[3mopus-5.5${ESC}[0m | user@example.com" ]
}

# bats test_tags=unit
@test "a style keeps its spaces and accepts commas between words" {
    conf 'style.email =  underline, fg:cyan  '
    render
    [ "$output" = "opus-5.5 | ${ESC}[4;36muser@example.com${ESC}[0m" ]
}

# bats test_tags=unit
@test "a style with no valid word leaves the component untouched" {
    conf 'style.email=sparkly fg:#12345'
    render
    [ "$output" = "opus-5.5 | user@example.com" ]
}

# bats test_tags=unit
@test "the style resumes after a reset inside the component" {
    printf 'components=usage\ntheme=dark\nstyle.usage=underline\n' >"$HOME/.claude/statusline.conf"
    run env COLUMNS=200 bash "$STATUSLINE" \
        <<<'{"model":{"id":"claude-opus-5-5"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":9999999999}}}'
    [ "$status" -eq 0 ]
    [[ "$output" == "${ESC}[4m${ESC}[0;34m12%${ESC}[0m${ESC}[4m"* ]]
}

# bats test_tags=unit
@test "the full-line color resumes after a styled component" {
    printf 'components=email,model\ntheme=dark\ncolor_scope=full\nstyle.email=bold\n' >"$HOME/.claude/statusline.conf"
    run env COLUMNS=200 bash "$STATUSLINE" \
        <<<'{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":9999999999}}}'
    [ "$output" = "${ESC}[0;34m${ESC}[1muser@example.com${ESC}[0m${ESC}[0;34m | opus-5.5${ESC}[0m" ]
}

# bats test_tags=unit
@test "style words map to their SGR codes" {
    sgr 'bold dimmed italic underline blink inverted hidden strikethrough'
    [ "$output" = "${ESC}[1;2;3;4;5;7;8;9m" ]
    sgr 'fg:208 bg:bright-blue'
    [ "$output" = "${ESC}[38;5;208;104m" ]
    sgr 'purple bg:black'
    [ "$output" = "${ESC}[35;40m" ]
    sgr 'bold none fg:red'
    [ "$output" = "${ESC}[31m" ]
    sgr 'bright-#ffffff fg:256'
    [ "$output" = "" ]
}

# bats test_tags=unit
@test "hex colors downsample to the cube or the grey ramp, whichever is closer" {
    sgr 'fg:#000000 bg:#ffffff'
    [ "$output" = "${ESC}[38;5;16;48;5;231m" ]
    sgr 'fg:#808080 bg:#56B4E9'
    [ "$output" = "${ESC}[38;5;244;48;5;74m" ]
    sgr 'fg:#56B4E9' 24bit
    [ "$output" = "${ESC}[38;2;86;180;233m" ]
}

# bats test_tags=unit
@test "each profile styles its email from its own local conf over a shared conf" {
    local work="$HOME/.claude-work"
    mkdir -p "$work"
    printf 'components=email\ntheme=none\nstyle.email=bold\n' >"$HOME/.claude/statusline.conf"
    ln -s "$HOME/.claude/statusline.conf" "$work/statusline.conf"
    printf 'style.email=bg:#EB4789\n' >"$HOME/.claude/statusline.local.conf"
    printf 'style.email=bg:#56B4E9\n' >"$work/statusline.local.conf"
    printf '{"oauthAccount":{"emailAddress":"work@example.com"}}' >"$work/.claude.json"
    render COLORTERM=truecolor
    [ "$output" = "${ESC}[48;2;235;71;137muser@example.com${ESC}[0m" ]
    render COLORTERM=truecolor CLAUDE_CONFIG_DIR="$work"
    [ "$output" = "${ESC}[48;2;86;180;233mwork@example.com${ESC}[0m" ]
}

# bats test_tags=unit
@test "the local conf overrides any key, and the shared one applies without it" {
    printf 'components=model,email\ntheme=none\n' >"$HOME/.claude/statusline.conf"
    render
    [ "$output" = "opus-5.5 | user@example.com" ]
    printf 'components=email' >"$HOME/.claude/statusline.local.conf"
    render
    [ "$output" = "user@example.com" ]
}

# bats test_tags=unit
@test "a local conf beside a legacy one-line conf still applies" {
    printf 'none\n' >"$HOME/.claude/statusline.conf"
    printf 'components=email\nstyle.email=italic\n' >"$HOME/.claude/statusline.local.conf"
    render
    [ "$output" = "${ESC}[3muser@example.com${ESC}[0m" ]
}

# bats test_tags=unit
@test "a gradient colors each letter through its stops" {
    conf 'style.email=gradient:#FF0000-#0000FF'
    printf '{"oauthAccount":{"emailAddress":"abcde"}}' >"$HOME/.claude.json"
    render COLORTERM=truecolor
    [ "$output" = "opus-5.5 | ${ESC}[38;2;255;0;0ma${ESC}[38;2;192;0;63mb${ESC}[38;2;128;0;127mc${ESC}[38;2;64;0;191md${ESC}[38;2;0;0;255me${ESC}[0m" ]
}

# bats test_tags=unit
@test "a gradient through three stops passes the middle one, mirrored or not" {
    sgr_component 'bold gradient:FF0000-00FF00-FF0000' abcde truecolor
    [ "$output" = "${ESC}[1m${ESC}[38;2;255;0;0ma${ESC}[38;2;128;127;0mb${ESC}[38;2;0;255;0mc${ESC}[38;2;127;128;0md${ESC}[38;2;255;0;0me${ESC}[0m" ]
}

# bats test_tags=unit
@test "a gradient falls back to 256 colors and skips repeated codes" {
    sgr_component 'gradient:#FF0000-#FF0101' abc ''
    [ "$output" = "${ESC}[38;5;196mabc${ESC}[0m" ]
}

# bats test_tags=unit
@test "a gradient keeps multibyte characters whole in a C locale" {
    run env LC_ALL=C COLORTERM=truecolor bash -c 'source "$1"; style_component "gradient:#FF0000-#0000FF" "$2"; printf "%s" "$REPLY"' _ \
        "$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/style.sh" "━é"
    [ "$output" = "${ESC}[38;2;255;0;0m━${ESC}[38;2;0;0;255mé${ESC}[0m" ]
}

# bats test_tags=unit
@test "a gradient on one letter, a lone stop, or a bad stop" {
    sgr_component 'gradient:#FF0000-#0000FF' x truecolor
    [ "$output" = "${ESC}[38;2;255;0;0mx${ESC}[0m" ]
    sgr_component 'gradient:#FF0000' ab truecolor
    [ "$output" = "ab" ]
    sgr_component 'italic gradient:#FF0000-#zzzzzz' ab truecolor
    [ "$output" = "${ESC}[3mab${ESC}[0m" ]
}

# bats test_tags=unit
@test "a component that colors itself keeps its colors under the gradient's first stop" {
    sgr_component 'gradient:#FF0000-#0000FF' $'a\033[31mb\033[0m' truecolor
    [ "$output" = "${ESC}[38;2;255;0;0ma${ESC}[31mb${ESC}[0m${ESC}[38;2;255;0;0m${ESC}[0m" ]
}

# bats test_tags=unit
@test "none drops a gradient set before it" {
    sgr_component 'gradient:#FF0000-#0000FF none bold' ab truecolor
    [ "$output" = "${ESC}[1mab${ESC}[0m" ]
}
