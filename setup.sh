#!/bin/bash
# setup.sh
# Path: claude-code-config/setup.sh
#
# Creates symlinks from this repo to ~/.claude/ for global Claude Code configuration.
# Run this script from inside the repo directory. Safe to re-run if you move the repo.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Claude Code Config Setup"
echo "========================"
echo "Repo location: $REPO_DIR"
echo ""

# Create ~/.claude if it doesn't exist
mkdir -p ~/.claude

# Create symlinks
echo "Creating symlinks..."

ln -sf "$REPO_DIR/.claude/commands" ~/.claude/commands
echo "  ✓ ~/.claude/commands -> $REPO_DIR/.claude/commands"

ln -sf "$REPO_DIR/.claude/skills" ~/.claude/skills
echo "  ✓ ~/.claude/skills -> $REPO_DIR/.claude/skills"

ln -sf "$REPO_DIR/.claude/agents" ~/.claude/agents
echo "  ✓ ~/.claude/agents -> $REPO_DIR/.claude/agents"

ln -sf "$REPO_DIR/.claude/hooks" ~/.claude/hooks
echo "  ✓ ~/.claude/hooks -> $REPO_DIR/.claude/hooks"

echo ""
echo "Setup complete!"
echo ""
echo "Optional next steps:"
echo "  1. Add Brave Search MCP (user scope):"
echo "     claude mcp add brave-search --scope user \\"
echo "       -e BRAVE_API_KEY='\${BRAVE_API_KEY}' \\"
echo "       -- npx -y @brave/brave-search-mcp-server"
echo ""
echo "  2. Set your BRAVE_API_KEY in ~/.zshrc or ~/.bashrc:"
echo "     export BRAVE_API_KEY=\"your-key-here\""
echo ""
echo "  3. Verify in any project:"
echo "     claude"
echo "     > /help  (should show /web-search, /brave-search, /pr)"
