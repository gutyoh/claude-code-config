#!/usr/bin/env bats
# setup-cli.bats
# Path: tests/setup-cli.bats
#
# bats-core tests for setup.sh CLI argument parsing.
# Sources setup.sh (source guard prevents main from running).
# Run: bats tests/setup-cli.bats
#      make test

SETUP="$BATS_TEST_DIRNAME/../setup.sh"

setup() {
    source "$SETUP"
}

# --- Default values ---

@test "parse_arguments: defaults are set before parsing" {
    [ "$ACCEPT_DEFAULTS" = "false" ]
    [ "$INSTALL_MCP" = "true" ]
    [ "$INSTALL_AGENTS_SKILLS" = "true" ]
    [ "$SETTINGS_MODE" = "merge" ]
    [ "$STATUSLINE_THEME" = "dark" ]
    [ "$STATUSLINE_BAR_STYLE" = "text" ]
    [ "$STATUSLINE_COMPACT" = "true" ]
}

# --- Flag parsing ---

@test "parse_arguments: -y sets ACCEPT_DEFAULTS" {
    parse_arguments -y
    [ "$ACCEPT_DEFAULTS" = "true" ]
}

@test "parse_arguments: --yes sets ACCEPT_DEFAULTS" {
    parse_arguments --yes
    [ "$ACCEPT_DEFAULTS" = "true" ]
}

@test "parse_arguments: --no-mcp disables MCP" {
    parse_arguments --no-mcp
    [ "$INSTALL_MCP" = "false" ]
}

@test "parse_arguments: --no-agents disables agents" {
    parse_arguments --no-agents
    [ "$INSTALL_AGENTS_SKILLS" = "false" ]
}

@test "parse_arguments: --minimal disables MCP and agents" {
    parse_arguments --minimal
    [ "$INSTALL_MCP" = "false" ]
    [ "$INSTALL_AGENTS_SKILLS" = "false" ]
}

@test "parse_arguments: --overwrite-settings sets overwrite mode" {
    parse_arguments --overwrite-settings
    [ "$SETTINGS_MODE" = "overwrite" ]
}

@test "parse_arguments: --skip-settings sets skip mode" {
    parse_arguments --skip-settings
    [ "$SETTINGS_MODE" = "skip" ]
}

# --- Theme ---

@test "parse_arguments: --theme light sets theme" {
    parse_arguments --theme light
    [ "$STATUSLINE_THEME" = "light" ]
}

@test "parse_arguments: --theme colorblind sets theme" {
    parse_arguments --theme colorblind
    [ "$STATUSLINE_THEME" = "colorblind" ]
}

@test "parse_arguments: --theme invalid exits with error" {
    run bash -c "source '$SETUP' && parse_arguments --theme invalid"
    [ "$status" -ne 0 ]
}

# --- Bar style ---

@test "parse_arguments: --bar-style block sets bar style" {
    parse_arguments --bar-style block
    [ "$STATUSLINE_BAR_STYLE" = "block" ]
}

@test "parse_arguments: --bar-pct-inside sets flag" {
    parse_arguments --bar-pct-inside
    [ "$STATUSLINE_BAR_PCT_INSIDE" = "true" ]
}

# --- Compact ---

@test "parse_arguments: --no-compact disables compact" {
    parse_arguments --no-compact
    [ "$STATUSLINE_COMPACT" = "false" ]
}

@test "parse_arguments: --compact enables compact" {
    STATUSLINE_COMPACT="false"
    parse_arguments --compact
    [ "$STATUSLINE_COMPACT" = "true" ]
}

# --- Color scope ---

@test "parse_arguments: --color-scope full sets scope" {
    parse_arguments --color-scope full
    [ "$STATUSLINE_COLOR_SCOPE" = "full" ]
}

# --- Icon ---

@test "parse_arguments: --icon spark sets icon" {
    parse_arguments --icon spark
    [ "$STATUSLINE_ICON" = "✻" ]
}

@test "parse_arguments: --icon none clears icon" {
    STATUSLINE_ICON="✻"
    parse_arguments --icon none
    [ "$STATUSLINE_ICON" = "" ]
}

# --- Combined flags ---

@test "parse_arguments: multiple flags combine correctly" {
    parse_arguments -y --no-mcp --theme colorblind --bar-style smooth
    [ "$ACCEPT_DEFAULTS" = "true" ]
    [ "$INSTALL_MCP" = "false" ]
    [ "$STATUSLINE_THEME" = "colorblind" ]
    [ "$STATUSLINE_BAR_STYLE" = "smooth" ]
}

# --- Weekly show reset ---

@test "parse_arguments: --weekly-show-reset sets flag" {
    parse_arguments --weekly-show-reset
    [ "$STATUSLINE_WEEKLY_SHOW_RESET" = "true" ]
}

@test "parse_arguments: --no-weekly-show-reset clears flag" {
    STATUSLINE_WEEKLY_SHOW_RESET="true"
    parse_arguments --no-weekly-show-reset
    [ "$STATUSLINE_WEEKLY_SHOW_RESET" = "false" ]
}

# --- Unknown option ---

@test "parse_arguments: unknown option exits with error" {
    run bash -c "source '$SETUP' && parse_arguments --nonexistent"
    [ "$status" -ne 0 ]
}

# --- Help ---

@test "parse_arguments: --help exits 0" {
    run bash -c "source '$SETUP' && parse_arguments --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
