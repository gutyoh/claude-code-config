# mcp.sh -- MCP server configuration
# Path: lib/setup/mcp.sh
# Sourced by setup.sh — do not execute directly.

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

    local user_scope_configured=false

    if [[ -f "${CLAUDE_JSON}" ]]; then
        if python3 - "${CLAUDE_JSON}" <<'PYTHON_CHECK' 2>/dev/null; then
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if 'brave-search' in data.get('mcpServers', {}):
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYTHON_CHECK
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
