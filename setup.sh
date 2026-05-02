#!/usr/bin/env bash
# setup.sh
# Path: claude-code-config/setup.sh
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers, agents, and skills in user scope.
# Run this script from inside the repo directory. Safe to re-run if you move the repo.
#
# Usage: ./setup.sh [options]
#   -y, --yes              Accept all defaults without prompting
#   --no-mcp               Skip Brave Search MCP server installation
#   --no-agents            Skip agents & skills installation
#   --agent-teams          Enable agent teams (experimental)
#   --no-agent-teams       Disable agent teams
#   --no-proxy-path        Skip proxy launcher PATH and shell shortcut setup
#   --minimal              Core only (no agents, skills, MCP, agent teams, proxy PATH, or shell shortcuts)
#   --overwrite-settings   Replace settings.json with repo defaults
#   --skip-settings        Don't modify settings.json
#   --theme THEME          Statusline color theme (dark|light|colorblind|none)
#   --components LIST      Comma-separated statusline components
#   --bar-style STYLE      Progress bar style (text|block|smooth|gradient|thin|spark)
#   --bar-pct-inside       Show percentage inside the bar
#   --compact              Compact mode (no labels, merged tokens)
#   --no-compact           Verbose mode (labels, separate tokens)
#   --color-scope SCOPE    Color scope: percentage or full
#   --icon-style STYLE     Icon style (plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket)
#   --weekly-show-reset    Show weekly reset countdown inline
#   -h, --help             Show this help message
#
# Platforms: macOS, Linux

set -euo pipefail

# --- Constants ---

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPO_DIR
readonly CLAUDE_DIR="${HOME}/.claude"
readonly SETTINGS_JSON="${CLAUDE_DIR}/settings.json"
readonly CLAUDE_JSON="${HOME}/.claude.json"

# --- Installation Options (defaults) ---

INSTALL_AGENTS_SKILLS="true"
INSTALL_MCP_SERVERS=("brave-search" "tavily") # populated from MCP_SERVER_KEYS
SETTINGS_MODE="merge"                         # merge | overwrite | skip
STATUSLINE_THEME="dark"                       # dark | light | colorblind | none
STATUSLINE_COMPONENTS="model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
STATUSLINE_BAR_STYLE="text"
STATUSLINE_BAR_PCT_INSIDE="false"
STATUSLINE_COMPACT="true"                # Compact: no labels, merged tokens, no burn_rate in wide mode
STATUSLINE_COLOR_SCOPE="percentage"      # "percentage" = color usage only, "full" = color entire line
STATUSLINE_ICON=""                       # Prefix icon: "✻", "A\", "❋", etc. or "" for none
STATUSLINE_ICON_STYLE="plain"            # plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket
STATUSLINE_WEEKLY_SHOW_RESET="false"     # Show weekly reset countdown inline
STATUSLINE_CC_STATUS_POSITION="inline"   # inline | newline
STATUSLINE_CC_STATUS_VISIBILITY="always" # always | problem_only
STATUSLINE_CC_STATUS_COLOR="full"        # none | full | status_only
INSTALL_AGENT_TEAMS="true"
INSTALL_PROXY_PATH="true"
INSTALL_OPENCODE="auto"            # "auto" | "yes" | "no" — auto = detect_opencode result
ACCEPT_DEFAULTS="false"
USER_CUSTOMIZED_STATUSLINE="false" # Set to true when user goes through TUI statusline customization

# --- Component Registry ---

readonly ALL_COMPONENT_KEYS=(
    "model" "usage" "weekly" "reset" "tokens_in" "tokens_out" "tokens_cache"
    "cost" "burn_rate" "email" "cc_status" "version" "lines" "session_time" "cwd"
)

readonly ALL_COMPONENT_DESCS=(
    "Model name (opus-4.5)"
    "Session utilization (5h)"
    "Weekly utilization (7d)"
    "Reset countdown timer"
    "Input tokens count"
    "Output tokens count"
    "Cache read tokens"
    "Session cost in USD"
    "Burn rate (USD/hr)"
    "Account email address"
    "Claude Code service status"
    "Claude Code version"
    "Lines added/removed"
    "Session elapsed time"
    "Working directory"
)

readonly DEFAULT_COMPONENT_INDICES=(0 1 2 3 4 5 6 7 8 9) # first 10

# --- Source Modules ---

_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_SETUP_DIR}/lib/setup/tui.sh"
source "${_SETUP_DIR}/lib/setup/preview.sh"
source "${_SETUP_DIR}/lib/setup/filesystem.sh"
source "${_SETUP_DIR}/lib/setup/settings.sh"
source "${_SETUP_DIR}/lib/setup/statusline-conf.sh"
source "${_SETUP_DIR}/lib/setup/mcp.sh"
source "${_SETUP_DIR}/lib/setup/opencode.sh"
source "${_SETUP_DIR}/lib/setup/cli.sh"
source "${_SETUP_DIR}/lib/setup/menu.sh"

# ============================================================================
# Main
# ============================================================================

main() {
    parse_arguments "$@"

    echo "Claude Code Config Setup"
    echo "========================"
    echo "Repo location: ${REPO_DIR}"
    echo ""

    # Check prerequisites
    echo "Checking prerequisites..."

    check_prerequisite "jq" "jq" "false" "required for IDE diagnostics hook and file suggestion"
    check_prerequisite "python3" "python3" "true" ""
    check_prerequisite "fd" "fd" "false" "optional: for faster file suggestions"
    check_prerequisite "fzf" "fzf" "false" "optional: for faster file suggestions"
    check_prerequisite "ccusage" "ccusage" "false" "optional: for statusline billing tracking"

    echo ""

    # Show interactive menu (unless --yes flag was passed)
    if [[ "${ACCEPT_DEFAULTS}" == "false" ]]; then
        show_install_menu
    fi

    echo ""

    local step=0

    # --- Create symlinks ---
    step=$((step + 1))
    mkdir -p "${CLAUDE_DIR}"

    echo "Step ${step}: Creating symlinks..."

    create_symlink "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks" "hooks"
    create_symlink "${REPO_DIR}/.claude/scripts" "${CLAUDE_DIR}/scripts" "scripts"

    # --- Install bin/ utilities to PATH ---
    local bin_dir="${HOME}/.local/bin"
    mkdir -p "${bin_dir}"
    if [[ -x "${REPO_DIR}/bin/mcp-key-rotate" ]]; then
        ln -sf "${REPO_DIR}/bin/mcp-key-rotate" "${bin_dir}/mcp-key-rotate"
        echo "  ✓ ~/.local/bin/mcp-key-rotate -> ${REPO_DIR}/bin/mcp-key-rotate"
    else
        echo "  ⚠ bin/mcp-key-rotate not found or not executable (skipping)"
        echo "    Run: chmod +x ${REPO_DIR}/bin/mcp-key-rotate"
    fi

    if [[ -x "${REPO_DIR}/bin/mcp-env-inject" ]]; then
        ln -sf "${REPO_DIR}/bin/mcp-env-inject" "${bin_dir}/mcp-env-inject"
        echo "  ✓ ~/.local/bin/mcp-env-inject -> ${REPO_DIR}/bin/mcp-env-inject"
    else
        echo "  ⚠ bin/mcp-env-inject not found or not executable (skipping)"
        echo "    Run: chmod +x ${REPO_DIR}/bin/mcp-env-inject"
    fi

    if [[ -x "${REPO_DIR}/bin/claude-proxy" ]]; then
        ln -sf "${REPO_DIR}/bin/claude-proxy" "${bin_dir}/claude-proxy"
        echo "  ✓ ~/.local/bin/claude-proxy -> ${REPO_DIR}/bin/claude-proxy"
    else
        echo "  ⚠ bin/claude-proxy not found or not executable (skipping)"
        echo "    Run: chmod +x ${REPO_DIR}/bin/claude-proxy"
    fi

    if [[ "${INSTALL_AGENTS_SKILLS}" == "true" ]]; then
        create_symlink "${REPO_DIR}/.claude/skills" "${CLAUDE_DIR}/skills" "skills"
        create_symlink "${REPO_DIR}/.claude/agents" "${CLAUDE_DIR}/agents" "agents"
    else
        echo "  ⊘ Skipping agents & skills (not selected)"
    fi

    echo ""

    # --- Configure settings.json ---
    if [[ "${SETTINGS_MODE}" == "overwrite" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Overwriting settings.json with repo defaults..."
        echo ""

        cp "${REPO_DIR}/.claude/settings.json" "${SETTINGS_JSON}"
        echo "  ✓ settings.json replaced with repo defaults"

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring file suggestion (user scope)..."
        echo ""

        if command -v fd &>/dev/null && command -v fzf &>/dev/null; then
            configure_file_suggestion
        else
            echo "  ⚠ Skipping file suggestion (fd and fzf not installed)"
            echo "    Install with: brew install fd fzf  # macOS"
            echo "                  sudo apt-get install fd-find fzf  # Ubuntu/Debian"
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring statusline config..."
        echo ""

        configure_statusline_conf "true"

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring agent teams..."
        echo ""

        configure_agent_teams

    elif [[ "${SETTINGS_MODE}" == "merge" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Configuring hooks (user scope)..."
        echo ""

        if [[ ! -f "${SETTINGS_JSON}" ]]; then
            echo "  Creating ~/.claude/settings.json with default hooks..."
            cat >"${SETTINGS_JSON}" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__ide__getDiagnostics",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/open-file-in-ide.sh"
          }
        ]
      }
    ]
  }
}
EOF
            echo "  ✓ IDE diagnostics hook configured"
        else
            configure_ide_hook
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring file suggestion (user scope)..."
        echo ""

        if command -v fd &>/dev/null && command -v fzf &>/dev/null; then
            configure_file_suggestion
        else
            echo "  ⚠ Skipping file suggestion (fd and fzf not installed)"
            echo "    Install with: brew install fd fzf  # macOS"
            echo "                  sudo apt-get install fd-find fzf  # Ubuntu/Debian"
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring statusline (user scope)..."
        echo ""

        configure_statusline

        if ! command -v ccusage &>/dev/null; then
            echo ""
            echo "  Note: Install ccusage for full statusline functionality:"
            echo "    npm install -g ccusage"
        fi

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring statusline config..."
        echo ""

        configure_statusline_conf "${USER_CUSTOMIZED_STATUSLINE}"

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Configuring agent teams..."
        echo ""

        configure_agent_teams

    else
        step=$((step + 1))
        echo "Step ${step}: Skipping settings.json configuration (not selected)"
    fi

    echo ""

    # --- Configure proxy launcher PATH and shell shortcuts ---
    if [[ "${INSTALL_PROXY_PATH}" == "true" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Configuring proxy launcher PATH and shell shortcuts..."
        echo ""

        configure_proxy_path
    else
        step=$((step + 1))
        echo "Step ${step}: Skipping proxy launcher PATH and shell shortcuts (not selected)"
    fi

    echo ""

    # --- Configure MCP servers ---
    if [[ ${#INSTALL_MCP_SERVERS[@]} -gt 0 ]]; then
        step=$((step + 1))
        echo "Step ${step}: Configuring MCP servers (user scope)..."
        echo ""

        configure_mcp_servers

        echo ""

        step=$((step + 1))
        echo "Step ${step}: Environment variables"
        echo ""

        check_mcp_env_vars
    else
        step=$((step + 1))
        echo "Step ${step}: Skipping MCP servers (not selected)"
    fi

    echo ""

    # --- Configure OpenCode parallel install ---
    local _opencode_resolved="no"
    case "${INSTALL_OPENCODE}" in
        yes)
            _opencode_resolved="yes"
            ;;
        no)
            _opencode_resolved="no"
            ;;
        auto)
            if detect_opencode; then
                _opencode_resolved="yes"
            else
                _opencode_resolved="no"
            fi
            ;;
    esac

    if [[ "${_opencode_resolved}" == "yes" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Configuring OpenCode (parallel install)..."
        echo ""
        configure_opencode
    else
        step=$((step + 1))
        echo "Step ${step}: Skipping OpenCode setup ($(opencode_detect_label))"
    fi

    echo ""
    echo "========================================"
    echo "Setup complete!"
    echo "========================================"
    echo ""
    echo "Verify in any project:"
    echo "  cd ~/some-project"
    echo "  claude"
    echo "  > /help           # Should show available skills"

    if [[ ${#INSTALL_MCP_SERVERS[@]} -gt 0 ]]; then
        local _mcp_key
        for _mcp_key in "${INSTALL_MCP_SERVERS[@]}"; do
            case "${_mcp_key}" in
                brave-search) echo "  > /brave-search   # Test Brave Search MCP" ;;
                tavily) echo "  > /tavily-search  # Test Tavily MCP" ;;
            esac
        done
        echo ""
        echo "To check MCP server status:"
        echo "  claude mcp list"
    fi

    if [[ "${_opencode_resolved}" == "yes" ]]; then
        echo ""
        echo "OpenCode verify:"
        echo "  cd ~/some-project"
        echo "  opencode"
        echo "  Tab to switch agents — translated subagents available via @"
        echo "  Config: ${OPENCODE_JSON}"
    fi
}

# Source guard: only run main() when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
