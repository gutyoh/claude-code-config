#!/usr/bin/env bats
# statusline-conf.bats
# Path: tests/statusline-conf.bats
#
# Setup rewrites statusline.conf when the user picks new options. Keys setup has
# no option for, the per-plan icons, must survive that rewrite.

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CLAUDE_DIR="${HOME}/.claude"
    mkdir -p "${CLAUDE_DIR}"
    STATUSLINE_THEME=dark STATUSLINE_COMPONENTS=model,usage STATUSLINE_BAR_STYLE=text
    STATUSLINE_BAR_PCT_INSIDE=false STATUSLINE_COMPACT=true STATUSLINE_COLOR_SCOPE=percentage
    STATUSLINE_ICON='A\' STATUSLINE_ICON_STYLE=plain STATUSLINE_WEEKLY_SHOW_RESET=false
    STATUSLINE_CC_STATUS_POSITION=inline STATUSLINE_CC_STATUS_VISIBILITY=always STATUSLINE_CC_STATUS_COLOR=full
    # shellcheck source=../lib/setup/statusline-conf.sh
    source "${REPO_DIR}/lib/setup/statusline-conf.sh"
}

# bats test_tags=unit
@test "a rewrite keeps the per-plan icons" {
    printf 'theme=light\nicon=✻\nicon_openai=\nicon_muse=󰛤\nicon_claude=A\\\n' >"${CLAUDE_DIR}/statusline.conf"
    run configure_statusline_conf "true"
    [ "$status" -eq 0 ]
    grep -qx 'theme=dark' "${CLAUDE_DIR}/statusline.conf"
    grep -qx 'icon_openai=' "${CLAUDE_DIR}/statusline.conf"
    grep -qx 'icon_muse=󰛤' "${CLAUDE_DIR}/statusline.conf"
    grep -qxF 'icon_claude=A\' "${CLAUDE_DIR}/statusline.conf"
    [ "$(grep -cE '^icon_(claude|openai|muse)=' "${CLAUDE_DIR}/statusline.conf")" -eq 3 ]
}

# bats test_tags=unit
@test "a rewrite without per-plan icons adds none" {
    printf 'theme=light\n' >"${CLAUDE_DIR}/statusline.conf"
    run configure_statusline_conf "true"
    [ "$status" -eq 0 ]
    ! grep -qE '^icon_(claude|openai|muse)=' "${CLAUDE_DIR}/statusline.conf"
}

# bats test_tags=unit
@test "a new config file has no per-plan icons" {
    run configure_statusline_conf "true"
    [ "$status" -eq 0 ]
    grep -qx 'theme=dark' "${CLAUDE_DIR}/statusline.conf"
    ! grep -qE '^icon_(claude|openai|muse)=' "${CLAUDE_DIR}/statusline.conf"
}

# bats test_tags=unit
@test "a rewrite keeps the component styles, spaces and all" {
    printf 'theme=light\nstyle.email=bold fg:#1E1E2E bg:#EB4789\nstyle.model=italic\n' >"${CLAUDE_DIR}/statusline.conf"
    run configure_statusline_conf "true"
    [ "$status" -eq 0 ]
    grep -qx 'theme=dark' "${CLAUDE_DIR}/statusline.conf"
    grep -qx 'style.email=bold fg:#1E1E2E bg:#EB4789' "${CLAUDE_DIR}/statusline.conf"
    grep -qx 'style.model=italic' "${CLAUDE_DIR}/statusline.conf"
}
