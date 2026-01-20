#!/bin/bash
# setup.sh
# Path: claude-code-config/setup.sh
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Optionally configures MCP servers in user scope.
# Run this script from inside the repo directory. Safe to re-run if you move the repo.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Claude Code Config Setup"
echo "========================"
echo "Repo location: $REPO_DIR"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v jq &> /dev/null; then
    echo "  ⚠ jq not found (required for IDE diagnostics hook and file suggestion)"
    echo "    Install with: brew install jq  # macOS"
    echo "                  sudo apt-get install jq  # Ubuntu/Debian"
    echo ""
    echo "  Setup will continue, but some features may not work."
    echo ""
else
    echo "  ✓ jq installed"
fi

if ! command -v python3 &> /dev/null; then
    echo "  ⚠ python3 not found (required for setup script)"
    echo "    Setup cannot continue without python3."
    exit 1
else
    echo "  ✓ python3 installed"
fi

# Check for file suggestion prerequisites (optional but recommended)
if ! command -v fd &> /dev/null; then
    echo "  ⚠ fd not found (optional: for faster file suggestions)"
    echo "    Install with: brew install fd  # macOS"
    echo "                  sudo apt-get install fd-find  # Ubuntu/Debian"
    echo ""
else
    echo "  ✓ fd installed"
fi

if ! command -v fzf &> /dev/null; then
    echo "  ⚠ fzf not found (optional: for faster file suggestions)"
    echo "    Install with: brew install fzf  # macOS"
    echo "                  sudo apt-get install fzf  # Ubuntu/Debian"
    echo ""
else
    echo "  ✓ fzf installed"
fi

if ! command -v ccusage &> /dev/null; then
    echo "  ⚠ ccusage not found (optional: for statusline billing tracking)"
    echo "    Install with: npm install -g ccusage"
    echo ""
else
    echo "  ✓ ccusage installed"
fi

if ! command -v bc &> /dev/null; then
    echo "  ⚠ bc not found (optional: for statusline number formatting)"
    echo "    Install with: brew install bc  # macOS"
    echo "                  sudo apt-get install bc  # Ubuntu/Debian"
    echo ""
else
    echo "  ✓ bc installed"
fi

echo ""

# Create ~/.claude if it doesn't exist
mkdir -p ~/.claude

# Function to safely create symlink without circular references
create_symlink() {
    local source="$1"
    local target="$2"
    local name="$3"

    # Resolve the real path of ~/.claude to detect if we're IN the repo
    local claude_real=$(cd ~/.claude && pwd -P)
    local repo_claude_real=$(cd "$REPO_DIR/.claude" && pwd -P)

    # If ~/.claude IS the repo's .claude directory, skip symlink creation
    if [ "$claude_real" = "$repo_claude_real" ]; then
        echo "  ✓ ~/.claude/$name (same as repo, no symlink needed)"
        return 0
    fi

    # Check if symlink already exists and points to correct location
    if [ -L "$target" ]; then
        local current_target=$(readlink "$target")
        if [ "$current_target" = "$source" ]; then
            echo "  ✓ ~/.claude/$name -> $source (already configured)"
            return 0
        fi
    fi

    # Remove existing (file, directory, or wrong symlink) and create fresh
    rm -rf "$target"
    ln -s "$source" "$target"
    echo "  ✓ ~/.claude/$name -> $source"
}

# Create symlinks
echo "Step 1: Creating symlinks..."

create_symlink "$REPO_DIR/.claude/commands" ~/.claude/commands "commands"
create_symlink "$REPO_DIR/.claude/skills" ~/.claude/skills "skills"
create_symlink "$REPO_DIR/.claude/agents" ~/.claude/agents "agents"
create_symlink "$REPO_DIR/.claude/hooks" ~/.claude/hooks "hooks"
create_symlink "$REPO_DIR/.claude/scripts" ~/.claude/scripts "scripts"

echo ""

# Configure hooks in global settings.json
echo "Step 2: Configuring hooks (user scope)..."
echo ""

SETTINGS_JSON="$HOME/.claude/settings.json"

# Check if settings.json exists
if [ ! -f "$SETTINGS_JSON" ]; then
    echo "  Creating ~/.claude/settings.json with default hooks..."
    cat > "$SETTINGS_JSON" <<'EOF'
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
    # Check if IDE diagnostics hook is already configured
    if python3 -c "
import json
import sys
try:
    with open('$SETTINGS_JSON') as f:
        data = json.load(f)
    # Check if mcp__ide__getDiagnostics hook exists
    hooks = data.get('hooks', {}).get('PreToolUse', [])
    for hook in hooks:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            sys.exit(0)  # Hook exists
    sys.exit(1)  # Hook doesn't exist
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ IDE diagnostics hook already configured"
    else
        echo "  Adding IDE diagnostics hook to existing settings..."
        # Merge the hook into existing settings.json using Python
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "$SETTINGS_JSON"

try:
    # Read existing settings
    with open(settings_file) as f:
        data = json.load(f)

    # Ensure hooks structure exists
    if 'hooks' not in data:
        data['hooks'] = {}
    if 'PreToolUse' not in data['hooks']:
        data['hooks']['PreToolUse'] = []

    # Add IDE diagnostics hook
    ide_hook = {
        "matcher": "mcp__ide__getDiagnostics",
        "hooks": [
            {
                "type": "command",
                "command": "~/.claude/hooks/open-file-in-ide.sh"
            }
        ]
    }

    # Check if it already exists (shouldn't happen, but safe check)
    existing = False
    for hook in data['hooks']['PreToolUse']:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            existing = True
            break

    if not existing:
        data['hooks']['PreToolUse'].append(ide_hook)

    # Write back
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ IDE diagnostics hook added")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add hook: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
fi

echo ""

# Configure file suggestion in global settings.json
echo "Step 3: Configuring file suggestion (user scope)..."
echo ""

# Only configure file suggestion if fd and fzf are available
if command -v fd &> /dev/null && command -v fzf &> /dev/null; then
    # Check if file suggestion is already configured
    if python3 -c "
import json
import sys
try:
    with open('$SETTINGS_JSON') as f:
        data = json.load(f)
    # Check if fileSuggestion exists
    if 'fileSuggestion' in data:
        sys.exit(0)  # Already configured
    sys.exit(1)  # Not configured
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ File suggestion already configured"
    else
        echo "  Adding file suggestion to settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "$SETTINGS_JSON"

try:
    # Read existing settings
    with open(settings_file) as f:
        data = json.load(f)

    # Add file suggestion configuration
    data['fileSuggestion'] = {
        "type": "command",
        "command": "~/.claude/scripts/file-suggestion.sh"
    }

    # Write back
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ File suggestion configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add file suggestion: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
else
    echo "  ⚠ Skipping file suggestion (fd and fzf not installed)"
    echo "    Install with: brew install fd fzf  # macOS"
    echo "                  sudo apt-get install fd-find fzf  # Ubuntu/Debian"
fi

echo ""

# Configure statusline in global settings.json
echo "Step 4: Configuring statusline (user scope)..."
echo ""

# Check if statusLine is already configured
if python3 -c "
import json
import sys
try:
    with open('$SETTINGS_JSON') as f:
        data = json.load(f)
    # Check if statusLine exists
    if 'statusLine' in data:
        sys.exit(0)  # Already configured
    sys.exit(1)  # Not configured
except Exception:
    sys.exit(1)
" 2>/dev/null; then
    echo "  ✓ Statusline already configured"
else
    echo "  Adding statusline to settings..."
    python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "$SETTINGS_JSON"

try:
    # Read existing settings
    with open(settings_file) as f:
        data = json.load(f)

    # Add statusline configuration (uses script for two-tier display)
    data['statusLine'] = {
        "type": "command",
        "command": "~/.claude/scripts/statusline.sh",
        "padding": 0
    }

    # Write back
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ Statusline configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add statusline: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
fi

if ! command -v ccusage &> /dev/null; then
    echo ""
    echo "  Note: Install ccusage for full statusline functionality:"
    echo "    npm install -g ccusage"
fi

echo ""

# Configure MCP servers in user scope
echo "Step 5: Configuring MCP servers (user scope)..."
echo ""

# Check if claude CLI is available
if ! command -v claude &> /dev/null; then
    echo "  ⚠ Claude Code CLI not found. Install it first:"
    echo "    curl -fsSL https://claude.ai/install.sh | bash"
    echo ""
    echo "  After installing, re-run this script or manually add MCP servers:"
    echo "    claude mcp add brave-search --scope user \\"
    echo "      -e BRAVE_API_KEY='\${BRAVE_API_KEY}' \\"
    echo "      -- npx -y @brave/brave-search-mcp-server"
    echo ""
else
    # Check if brave-search MCP is already configured in USER scope specifically
    # We check ~/.claude.json directly because `claude mcp list` shows ALL scopes
    # (including project-level .mcp.json which doesn't work globally)
    CLAUDE_JSON="$HOME/.claude.json"
    USER_SCOPE_CONFIGURED=false

    if [ -f "$CLAUDE_JSON" ]; then
        # Use python to check if brave-search exists in root-level mcpServers (user scope)
        # Note: Use 'except Exception:' not 'except:' to avoid catching SystemExit
        if python3 -c "
import json
import sys
try:
    with open('$CLAUDE_JSON') as f:
        data = json.load(f)
    # Check root-level mcpServers (user scope), not project-level
    if 'brave-search' in data.get('mcpServers', {}):
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
            USER_SCOPE_CONFIGURED=true
        fi
    fi

    if [ "$USER_SCOPE_CONFIGURED" = true ]; then
        echo "  ✓ brave-search MCP already configured (user scope)"
    else
        echo "  Adding brave-search MCP server to user scope..."
        # Add Brave Search MCP to user scope
        # The ${BRAVE_API_KEY} will be expanded at runtime by Claude Code
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
fi

echo ""
echo "Step 6: Environment variables"
echo ""

# Check if BRAVE_API_KEY is set
if [ -n "$BRAVE_API_KEY" ]; then
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
