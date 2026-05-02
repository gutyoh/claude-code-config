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
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 2 ]
    [ "${INSTALL_MCP_SERVERS[0]}" = "brave-search" ]
    [ "${INSTALL_MCP_SERVERS[1]}" = "tavily" ]
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

@test "parse_arguments: --no-mcp disables all MCP servers" {
    parse_arguments --no-mcp
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 0 ]
}

@test "parse_arguments: --mcp with single server" {
    parse_arguments --mcp brave-search
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 1 ]
    [ "${INSTALL_MCP_SERVERS[0]}" = "brave-search" ]
}

@test "parse_arguments: --mcp with multiple servers" {
    parse_arguments --mcp brave-search,tavily
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 2 ]
    [ "${INSTALL_MCP_SERVERS[0]}" = "brave-search" ]
    [ "${INSTALL_MCP_SERVERS[1]}" = "tavily" ]
}

@test "parse_arguments: --mcp tavily only" {
    parse_arguments --mcp tavily
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 1 ]
    [ "${INSTALL_MCP_SERVERS[0]}" = "tavily" ]
}

@test "parse_arguments: --mcp with invalid server exits with error" {
    run bash -c "source '$SETUP' && parse_arguments --mcp nonexistent"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown MCP server"* ]]
}

@test "parse_arguments: --mcp without value exits with error" {
    run bash -c "source '$SETUP' && parse_arguments --mcp"
    [ "$status" -ne 0 ]
}

@test "parse_arguments: --no-mcp then --mcp overrides" {
    parse_arguments --no-mcp --mcp tavily
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 1 ]
    [ "${INSTALL_MCP_SERVERS[0]}" = "tavily" ]
}

@test "parse_arguments: --no-agents disables agents" {
    parse_arguments --no-agents
    [ "$INSTALL_AGENTS_SKILLS" = "false" ]
}

@test "parse_arguments: --minimal disables MCP, agents, agent teams, and proxy PATH" {
    parse_arguments --minimal
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 0 ]
    [ "$INSTALL_AGENTS_SKILLS" = "false" ]
    [ "$INSTALL_AGENT_TEAMS" = "false" ]
    [ "$INSTALL_PROXY_PATH" = "false" ]
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
    [ "${#INSTALL_MCP_SERVERS[@]}" -eq 0 ]
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

# --- Proxy PATH ---

@test "parse_arguments: --proxy-path enables proxy PATH" {
    INSTALL_PROXY_PATH="false"
    parse_arguments --proxy-path
    [ "$INSTALL_PROXY_PATH" = "true" ]
}

@test "parse_arguments: --no-proxy-path disables proxy PATH" {
    parse_arguments --no-proxy-path
    [ "$INSTALL_PROXY_PATH" = "false" ]
}

@test "configure_claude_shortcuts: installs claude and clp functions" {
    local profile="${BATS_TEST_TMPDIR}/.zshrc"
    touch "$profile"

    configure_claude_shortcuts "$profile"

    grep -Fq 'claude-code-config: claude launch shortcuts' "$profile"
    grep -Fq 'command claude --allow-dangerously-skip-permissions "$@"' "$profile"
    grep -Fq 'command claude --dangerously-skip-permissions "$@"' "$profile"
    grep -Fq 'claude-proxy --no-validate -m "$model" -- --allow-dangerously-skip-permissions "$@"' "$profile"
    grep -Fq 'claude-proxy --no-validate -m "$model" -- --dangerously-skip-permissions "$@"' "$profile"
}

@test "configure_claude_shortcuts: replaces existing managed block" {
    local profile="${BATS_TEST_TMPDIR}/.zshrc"
    cat >"$profile" <<'EOF'
keep-before
# claude-code-config: claude launch shortcuts
old body
# claude-code-config: end claude launch shortcuts
keep-after
EOF

    configure_claude_shortcuts "$profile"
    configure_claude_shortcuts "$profile"

    [ "$(grep -Fc 'claude-code-config: claude launch shortcuts' "$profile")" -eq 1 ]
    [ "$(grep -Fc 'claude-code-config: end claude launch shortcuts' "$profile")" -eq 1 ]
    grep -Fq 'keep-before' "$profile"
    grep -Fq 'keep-after' "$profile"
    ! grep -Fq 'old body' "$profile"
}

@test "configure_claude_shortcuts: generated functions forward arguments correctly" {
    local profile="${BATS_TEST_TMPDIR}/.zshrc"
    local stub_dir="${BATS_TEST_TMPDIR}/stubs"
    local log="${BATS_TEST_TMPDIR}/calls.log"
    mkdir -p "$stub_dir"

    cat >"${stub_dir}/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude:%s\n' "$*" >>"$CALL_LOG"
EOF
    cat >"${stub_dir}/claude-proxy" <<'EOF'
#!/usr/bin/env bash
printf 'claude-proxy:%s\n' "$*" >>"$CALL_LOG"
EOF
    chmod +x "${stub_dir}/claude" "${stub_dir}/claude-proxy"

    configure_claude_shortcuts "$profile"

    run env PATH="${stub_dir}:$PATH" CALL_LOG="$log" bash -c "source '$profile' && claude --resume && claude -a --resume && clp --continue && clp -a --resume"
    [ "$status" -eq 0 ]
    grep -Fq 'claude:--allow-dangerously-skip-permissions --resume' "$log"
    grep -Fq 'claude:--dangerously-skip-permissions --resume' "$log"
    grep -Fq 'claude-proxy:--no-validate -m gpt-5.5(high) -- --allow-dangerously-skip-permissions --continue' "$log"
    grep -Fq 'claude-proxy:--no-validate -m gpt-5.5(high) -- --dangerously-skip-permissions --resume' "$log"
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
