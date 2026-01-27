#!/usr/bin/env bash
# setup.sh
# Path: claude-code-config/setup.sh
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers in user scope.
# Run this script from inside the repo directory. Safe to re-run if you move the repo.
#
# Platforms: macOS, Linux

set -euo pipefail

# --- Constants ---

readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CLAUDE_DIR="${HOME}/.claude"
readonly SETTINGS_JSON="${CLAUDE_DIR}/settings.json"
readonly CLAUDE_JSON="${HOME}/.claude.json"

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

# --- Main ---

main() {
    echo "Claude Code Config Setup"
    echo "========================"
    echo "Repo location: ${REPO_DIR}"
    echo ""

    # Step 1: Check prerequisites
    echo "Checking prerequisites..."

    check_prerequisite "jq" "jq" "false" "required for IDE diagnostics hook and file suggestion"
    check_prerequisite "python3" "python3" "true" ""
    check_prerequisite "fd" "fd" "false" "optional: for faster file suggestions"
    check_prerequisite "fzf" "fzf" "false" "optional: for faster file suggestions"
    check_prerequisite "ccusage" "ccusage" "false" "optional: for statusline billing tracking"
    check_prerequisite "bc" "bc" "false" "optional: for statusline number formatting"

    echo ""

    # Step 2: Create symlinks
    mkdir -p "${CLAUDE_DIR}"

    echo "Step 1: Creating symlinks..."

    create_symlink "${REPO_DIR}/.claude/commands" "${CLAUDE_DIR}/commands" "commands"
    create_symlink "${REPO_DIR}/.claude/skills" "${CLAUDE_DIR}/skills" "skills"
    create_symlink "${REPO_DIR}/.claude/agents" "${CLAUDE_DIR}/agents" "agents"
    create_symlink "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks" "hooks"
    create_symlink "${REPO_DIR}/.claude/scripts" "${CLAUDE_DIR}/scripts" "scripts"

    echo ""

    # Step 3: Configure hooks
    echo "Step 2: Configuring hooks (user scope)..."
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

    # Step 4: Configure file suggestion
    echo "Step 3: Configuring file suggestion (user scope)..."
    echo ""

    if command -v fd &>/dev/null && command -v fzf &>/dev/null; then
        configure_file_suggestion
    else
        echo "  ⚠ Skipping file suggestion (fd and fzf not installed)"
        echo "    Install with: brew install fd fzf  # macOS"
        echo "                  sudo apt-get install fd-find fzf  # Ubuntu/Debian"
    fi

    echo ""

    # Step 5: Configure statusline
    echo "Step 4: Configuring statusline (user scope)..."
    echo ""

    configure_statusline

    if ! command -v ccusage &>/dev/null; then
        echo ""
        echo "  Note: Install ccusage for full statusline functionality:"
        echo "    npm install -g ccusage"
    fi

    echo ""

    # Step 6: Configure MCP servers
    echo "Step 5: Configuring MCP servers (user scope)..."
    echo ""

    configure_mcp_servers

    echo ""

    # Step 7: Environment variables
    echo "Step 6: Environment variables"
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

    echo ""
    echo "========================================"
    echo "Setup complete!"
    echo "========================================"
    echo ""
    echo "Verify in any project:"
    echo "  cd ~/some-project"
    echo "  claude"
    echo "  > /help           # Should show /web-search, /brave-search, /pr"
    echo "  > /brave-search   # Test the MCP integration"
    echo ""
    echo "To check MCP server status:"
    echo "  claude mcp list"
}

main "$@"
