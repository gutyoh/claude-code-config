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

echo ""

# Configure MCP servers in user scope
echo "Step 2: Configuring MCP servers (user scope)..."
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
echo "Step 3: Environment variables"
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
