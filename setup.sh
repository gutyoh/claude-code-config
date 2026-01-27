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
#   --minimal              Core only (no agents, skills, or MCP)
#   --overwrite-settings   Replace settings.json with repo defaults
#   --skip-settings        Don't modify settings.json
#   -h, --help             Show this help message
#
# Platforms: macOS, Linux

set -euo pipefail

# --- Constants ---

readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CLAUDE_DIR="${HOME}/.claude"
readonly SETTINGS_JSON="${CLAUDE_DIR}/settings.json"
readonly CLAUDE_JSON="${HOME}/.claude.json"

# --- Installation Options (defaults) ---

INSTALL_AGENTS_SKILLS="true"
INSTALL_MCP="true"
SETTINGS_MODE="merge"  # merge | overwrite | skip
ACCEPT_DEFAULTS="false"

# --- Functions ---

create_symlink() {
    local source="$1"
    local target="$2"
    local name="$3"

    # Resolve the real path of ~/.claude to detect if we're IN the repo
    local claude_real
    claude_real=$(cd "${CLAUDE_DIR}" && pwd -P)
    local repo_claude_real
    repo_claude_real=$(cd "${REPO_DIR}/.claude" && pwd -P)

    # If ~/.claude IS the repo's .claude directory, skip symlink creation
    if [[ "${claude_real}" == "${repo_claude_real}" ]]; then
        echo "  ✓ ~/.claude/${name} (same as repo, no symlink needed)"
        return 0
    fi

    # Check if symlink already exists and points to correct location
    if [[ -L "${target}" ]]; then
        local current_target
        current_target=$(readlink "${target}")
        if [[ "${current_target}" == "${source}" ]]; then
            echo "  ✓ ~/.claude/${name} -> ${source} (already configured)"
            return 0
        fi
    fi

    # Remove existing (file, directory, or wrong symlink) and create fresh
    rm -rf "${target}"
    ln -s "${source}" "${target}"
    echo "  ✓ ~/.claude/${name} -> ${source}"
}

check_prerequisite() {
    local cmd="$1"
    local label="$2"
    local required="${3:-false}"
    local install_hint="${4:-}"

    if ! command -v "${cmd}" &>/dev/null; then
        echo "  ⚠ ${label} not found${install_hint:+ (${install_hint})}"
        if [[ -n "${install_hint}" ]]; then
            echo "    Install with: brew install ${cmd}  # macOS"
            echo "                  sudo apt-get install ${cmd}  # Ubuntu/Debian"
        fi
        if [[ "${required}" == "true" ]]; then
            echo "    Setup cannot continue without ${cmd}."
            exit 1
        fi
        echo ""
        return 1
    else
        echo "  ✓ ${label} installed"
        return 0
    fi
}

configure_ide_hook() {
    # Check if IDE diagnostics hook is already configured
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    hooks = data.get('hooks', {}).get('PreToolUse', [])
    for hook in hooks:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ IDE diagnostics hook already configured"
    else
        echo "  Adding IDE diagnostics hook to existing settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

try:
    with open(settings_file) as f:
        data = json.load(f)

    if 'hooks' not in data:
        data['hooks'] = {}
    if 'PreToolUse' not in data['hooks']:
        data['hooks']['PreToolUse'] = []

    ide_hook = {
        "matcher": "mcp__ide__getDiagnostics",
        "hooks": [
            {
                "type": "command",
                "command": "~/.claude/hooks/open-file-in-ide.sh"
            }
        ]
    }

    existing = False
    for hook in data['hooks']['PreToolUse']:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            existing = True
            break

    if not existing:
        data['hooks']['PreToolUse'].append(ide_hook)

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ IDE diagnostics hook added")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add hook: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_file_suggestion() {
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    if 'fileSuggestion' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ File suggestion already configured"
    else
        echo "  Adding file suggestion to settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

try:
    with open(settings_file) as f:
        data = json.load(f)

    data['fileSuggestion'] = {
        "type": "command",
        "command": "~/.claude/scripts/file-suggestion.sh"
    }

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ File suggestion configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add file suggestion: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_statusline() {
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    if 'statusLine' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ Statusline already configured"
    else
        echo "  Adding statusline to settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

try:
    with open(settings_file) as f:
        data = json.load(f)

    data['statusLine'] = {
        "type": "command",
        "command": "~/.claude/scripts/statusline.sh",
        "padding": 0
    }

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ Statusline configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add statusline: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_mcp_servers() {
    if ! command -v claude &>/dev/null; then
        echo "  ⚠ Claude Code CLI not found. Install it first:"
        echo "    curl -fsSL https://claude.ai/install.sh | bash"
        echo ""
        echo "  After installing, re-run this script or manually add MCP servers:"
        echo "    claude mcp add brave-search --scope user \\"
        echo "      -e BRAVE_API_KEY='\${BRAVE_API_KEY}' \\"
        echo "      -- npx -y @brave/brave-search-mcp-server"
        echo ""
        return
    fi

    # Check if brave-search MCP is already configured in USER scope specifically
    # We check ~/.claude.json directly because `claude mcp list` shows ALL scopes
    # (including project-level .mcp.json which doesn't work globally)
    local user_scope_configured=false

    if [[ -f "${CLAUDE_JSON}" ]]; then
        if python3 -c "
import json
import sys
try:
    with open('${CLAUDE_JSON}') as f:
        data = json.load(f)
    if 'brave-search' in data.get('mcpServers', {}):
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
            user_scope_configured=true
        fi
    fi

    if [[ "${user_scope_configured}" == "true" ]]; then
        echo "  ✓ brave-search MCP already configured (user scope)"
    else
        echo "  Adding brave-search MCP server to user scope..."
        if claude mcp add brave-search --scope user \
            -e BRAVE_API_KEY='${BRAVE_API_KEY}' \
            -- npx -y @brave/brave-search-mcp-server 2>/dev/null; then
            echo "  ✓ brave-search MCP added to user scope"
        else
            echo "  ⚠ Failed to add brave-search MCP. You can add it manually:"
            echo "    claude mcp add brave-search --scope user \\"
            echo "      -e BRAVE_API_KEY='\${BRAVE_API_KEY}' \\"
            echo "      -- npx -y @brave/brave-search-mcp-server"
        fi
    fi
}

show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration."
    echo ""
    echo "Options:"
    echo "  -y, --yes              Accept all defaults without prompting"
    echo "  --no-mcp               Skip Brave Search MCP server installation"
    echo "  --no-agents            Skip agents & skills installation"
    echo "  --minimal              Core only (no agents, skills, or MCP)"
    echo "  --overwrite-settings   Replace settings.json with repo defaults"
    echo "  --skip-settings        Don't modify settings.json"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                     # Interactive mode (recommended)"
    echo "  ./setup.sh -y                  # Full install, no prompts"
    echo "  ./setup.sh -y --no-mcp         # Full install without Brave Search MCP"
    echo "  ./setup.sh -y --minimal        # Core only (hooks, scripts, commands)"
    echo "  ./setup.sh --overwrite-settings # Interactive, but force-overwrite settings.json"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
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
            --minimal)
                INSTALL_AGENTS_SKILLS="false"
                INSTALL_MCP="false"
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
            -h|--help)
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

show_install_menu() {
    local agents_label="yes"
    local mcp_label="yes"
    local settings_label="merge (preserve existing, add new)"

    if [[ "${INSTALL_AGENTS_SKILLS}" == "false" ]]; then
        agents_label="no"
    fi
    if [[ "${INSTALL_MCP}" == "false" ]]; then
        mcp_label="no"
    fi
    if [[ "${SETTINGS_MODE}" == "overwrite" ]]; then
        settings_label="overwrite (replace with repo defaults)"
    elif [[ "${SETTINGS_MODE}" == "skip" ]]; then
        settings_label="skip (don't modify)"
    fi

    echo "Current installation options:"
    echo "  core (hooks, scripts, commands):  always"
    echo "  agents & skills:                  ${agents_label}"
    echo "  brave search MCP:                 ${mcp_label}"
    echo "  settings.json:                    ${settings_label}"
    echo ""
    echo "1) Proceed with installation (default - just press enter)"
    echo "2) Customize installation"
    echo "3) Cancel installation"
    echo ""

    local choice
    read -rp "> " choice
    choice="${choice:-1}"

    case "${choice}" in
        1)
            # Use current options
            ;;
        2)
            customize_installation
            ;;
        3)
            echo "Installation cancelled."
            exit 0
            ;;
        *)
            echo "Invalid option. Using current options."
            ;;
    esac
}

customize_installation() {
    echo ""

    local answer

    read -rp "Install agents & skills? [Y/n] " answer
    case "${answer}" in
        [nN]) INSTALL_AGENTS_SKILLS="false" ;;
    esac

    read -rp "Install Brave Search MCP server? [Y/n] " answer
    case "${answer}" in
        [nN]) INSTALL_MCP="false" ;;
    esac

    echo ""
    echo "Settings.json mode:"
    echo "  [m]erge     - Preserve existing settings, add new (default)"
    echo "  [o]verwrite - Replace with repo defaults"
    echo "  [s]kip      - Don't modify settings.json"
    echo ""
    read -rp "Settings mode [m/o/s] (default: m): " answer
    answer="${answer:-m}"

    case "${answer}" in
        [oO]) SETTINGS_MODE="overwrite" ;;
        [sS]) SETTINGS_MODE="skip" ;;
        *) SETTINGS_MODE="merge" ;;
    esac
}

# --- Main ---

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
    check_prerequisite "bc" "bc" "false" "optional: for statusline number formatting"

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

    create_symlink "${REPO_DIR}/.claude/commands" "${CLAUDE_DIR}/commands" "commands"
    create_symlink "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks" "hooks"
    create_symlink "${REPO_DIR}/.claude/scripts" "${CLAUDE_DIR}/scripts" "scripts"

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

        # Add file suggestion on top of overwritten settings (runtime-detected)
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

    elif [[ "${SETTINGS_MODE}" == "merge" ]]; then
        # Hooks
        step=$((step + 1))
        echo "Step ${step}: Configuring hooks (user scope)..."
        echo ""

        if [[ ! -f "${SETTINGS_JSON}" ]]; then
            echo "  Creating ~/.claude/settings.json with default hooks..."
            cat > "${SETTINGS_JSON}" <<'EOF'
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

        # File suggestion
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

        # Statusline
        step=$((step + 1))
        echo "Step ${step}: Configuring statusline (user scope)..."
        echo ""

        configure_statusline

        if ! command -v ccusage &>/dev/null; then
            echo ""
            echo "  Note: Install ccusage for full statusline functionality:"
            echo "    npm install -g ccusage"
        fi

    else
        step=$((step + 1))
        echo "Step ${step}: Skipping settings.json configuration (not selected)"
    fi

    echo ""

    # --- Configure MCP servers ---
    if [[ "${INSTALL_MCP}" == "true" ]]; then
        step=$((step + 1))
        echo "Step ${step}: Configuring MCP servers (user scope)..."
        echo ""

        configure_mcp_servers

        echo ""

        # Environment variables
        step=$((step + 1))
        echo "Step ${step}: Environment variables"
        echo ""

        if [[ -n "${BRAVE_API_KEY:-}" ]]; then
            echo "  ✓ BRAVE_API_KEY is set (${#BRAVE_API_KEY} chars)"
        else
            echo "  ⚠ BRAVE_API_KEY not set. Add to your shell profile:"
            echo ""
            echo "    # Add to ~/.zshrc or ~/.bashrc:"
            echo "    export BRAVE_API_KEY=\"your-api-key-here\""
            echo ""
            echo "    Get a free API key (2,000 searches/month):"
            echo "    https://api-dashboard.search.brave.com/"
        fi
    else
        step=$((step + 1))
        echo "Step ${step}: Skipping MCP servers (not selected)"
    fi

    echo ""
    echo "========================================"
    echo "Setup complete!"
    echo "========================================"
    echo ""
    echo "Verify in any project:"
    echo "  cd ~/some-project"
    echo "  claude"
    echo "  > /help           # Should show custom commands"

    if [[ "${INSTALL_MCP}" == "true" ]]; then
        echo "  > /brave-search   # Test the MCP integration"
        echo ""
        echo "To check MCP server status:"
        echo "  claude mcp list"
    fi
}

main "$@"
