# cli.sh -- CLI argument parsing and help
# Path: lib/setup/cli.sh
# Sourced by setup.sh — do not execute directly.

show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration."
    echo ""
    echo "Options:"
    echo "  -y, --yes              Accept all defaults without prompting"
    echo "  --no-mcp               Skip Brave Search MCP server installation"
    echo "  --no-agents            Skip agents & skills installation"
    echo "  --agent-teams          Enable agent teams (experimental)"
    echo "  --no-agent-teams       Disable agent teams"
    echo "  --minimal              Core only (no agents, skills, MCP, agent teams, or proxy PATH)"
    echo "  --overwrite-settings   Replace settings.json with repo defaults"
    echo "  --skip-settings        Don't modify settings.json"
    echo "  --theme THEME          Statusline color theme (dark|light|colorblind|none)"
    echo "  --components LIST      Comma-separated statusline components"
    echo "  --bar-style STYLE      Progress bar style (text|block|smooth|gradient|thin|spark)"
    echo "  --bar-pct-inside       Show percentage inside the bar"
    echo "  --compact              Compact mode (no labels, merged tokens — default)"
    echo "  --no-compact           Verbose mode (labels, separate tokens, burn rate)"
    echo "  --color-scope SCOPE    Color scope: percentage (usage only) or full (entire line)"
    echo "  --icon ICON            Prefix icon (none|spark|anthropic|sparkle|star|custom)"
    echo "  --icon-style STYLE     Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)"
    echo "  --weekly-show-reset    Show weekly reset countdown inline"
    echo "  --no-weekly-show-reset Hide weekly reset countdown (default)"
    echo "  --proxy-path           Add bin/ to PATH in shell profile (default)"
    echo "  --no-proxy-path        Skip proxy launcher PATH setup"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Available components:"
    echo "  model, usage, weekly, reset, tokens_in, tokens_out, tokens_cache,"
    echo "  cost, burn_rate, email, version, lines, session_time, cwd"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                     # Interactive mode (recommended)"
    echo "  ./setup.sh -y                  # Full install, no prompts"
    echo "  ./setup.sh -y --no-mcp         # Full install without Brave Search MCP"
    echo "  ./setup.sh -y --minimal        # Core only (hooks, scripts, commands)"
    echo "  ./setup.sh -y --theme colorblind  # Full install with colorblind theme"
    echo "  ./setup.sh -y --bar-style block --bar-pct-inside --components model,usage,cost"
    echo "  ./setup.sh --overwrite-settings # Interactive, but force-overwrite settings.json"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y | --yes)
                ACCEPT_DEFAULTS="true"
                shift
                ;;
            --no-mcp)
                INSTALL_MCP="false"
                shift
                ;;
            --no-agents)
                INSTALL_AGENTS_SKILLS="false"
                shift
                ;;
            --agent-teams)
                INSTALL_AGENT_TEAMS="true"
                shift
                ;;
            --no-agent-teams)
                INSTALL_AGENT_TEAMS="false"
                shift
                ;;
            --minimal)
                INSTALL_AGENTS_SKILLS="false"
                INSTALL_MCP="false"
                INSTALL_AGENT_TEAMS="false"
                INSTALL_PROXY_PATH="false"
                shift
                ;;
            --overwrite-settings)
                SETTINGS_MODE="overwrite"
                shift
                ;;
            --skip-settings)
                SETTINGS_MODE="skip"
                shift
                ;;
            --theme)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --theme requires a value (dark|light|colorblind|none)"
                    exit 1
                fi
                case "$2" in
                    dark | light | colorblind | none)
                        STATUSLINE_THEME="$2"
                        ;;
                    *)
                        echo "Error: Invalid theme '$2'. Choose: dark, light, colorblind, none"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --components)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --components requires a comma-separated list"
                    exit 1
                fi
                STATUSLINE_COMPONENTS="$2"
                shift 2
                ;;
            --bar-style)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --bar-style requires a value (text|block|smooth|gradient|thin|spark)"
                    exit 1
                fi
                case "$2" in
                    text | block | smooth | gradient | thin | spark)
                        STATUSLINE_BAR_STYLE="$2"
                        ;;
                    *)
                        echo "Error: Invalid bar style '$2'. Choose: text, block, smooth, gradient, thin, spark"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --bar-pct-inside)
                STATUSLINE_BAR_PCT_INSIDE="true"
                shift
                ;;
            --compact)
                STATUSLINE_COMPACT="true"
                shift
                ;;
            --no-compact)
                STATUSLINE_COMPACT="false"
                shift
                ;;
            --color-scope)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --color-scope requires a value (percentage|full)"
                    exit 1
                fi
                case "$2" in
                    percentage | full)
                        STATUSLINE_COLOR_SCOPE="$2"
                        ;;
                    *)
                        echo "Error: Invalid color scope '$2'. Choose: percentage, full"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --icon)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --icon requires a value (none, spark, anthropic, sparkle, star, or a custom string)"
                    exit 1
                fi
                case "$2" in
                    none) STATUSLINE_ICON="" ;;
                    spark) STATUSLINE_ICON="✻" ;;
                    anthropic) STATUSLINE_ICON='A\' ;;
                    sparkle) STATUSLINE_ICON="❇" ;;
                    star) STATUSLINE_ICON="✦" ;;
                    *) STATUSLINE_ICON="$2" ;;
                esac
                shift 2
                ;;
            --weekly-show-reset)
                STATUSLINE_WEEKLY_SHOW_RESET="true"
                shift
                ;;
            --no-weekly-show-reset)
                STATUSLINE_WEEKLY_SHOW_RESET="false"
                shift
                ;;
            --proxy-path)
                INSTALL_PROXY_PATH="true"
                shift
                ;;
            --no-proxy-path)
                INSTALL_PROXY_PATH="false"
                shift
                ;;
            --icon-style)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --icon-style requires a value"
                    exit 1
                fi
                case "$2" in
                    plain | bold | bracketed | rounded | reverse | bold-color | angle | double-bracket)
                        STATUSLINE_ICON_STYLE="$2"
                        ;;
                    *)
                        echo "Error: Invalid icon style '$2'. Choose: plain, bold, bracketed, rounded, reverse, bold-color, angle, double-bracket"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -h | --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done
}
