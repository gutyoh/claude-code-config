# mcp.sh -- MCP server configuration
# Path: lib/setup/mcp.sh
# Sourced by setup.sh — do not execute directly.

# --- MCP Server Registry ---
# Each server: KEY, LABEL, DESCRIPTION, ENV_VAR, NPX_PACKAGE

readonly MCP_SERVER_KEYS=("brave-search" "tavily")

readonly -A MCP_SERVER_LABELS=(
    ["brave-search"]="brave-search"
    ["tavily"]="tavily"
)

readonly -A MCP_SERVER_DESCS=(
    ["brave-search"]="Web, image, video, news, local search (1,000/mo free)"
    ["tavily"]="AI-native search, extract, crawl, map, research (1,000/mo free)"
)

readonly -A MCP_SERVER_ENV_VARS=(
    ["brave-search"]="BRAVE_API_KEY"
    ["tavily"]="TAVILY_API_KEY"
)

readonly -A MCP_SERVER_PACKAGES=(
    ["brave-search"]="@brave/brave-search-mcp-server"
    ["tavily"]="tavily-mcp@0.2.17"
)

readonly -A MCP_SERVER_SIGNUP_URLS=(
    ["brave-search"]="https://api-dashboard.search.brave.com/"
    ["tavily"]="https://tavily.com"
)

readonly -A MCP_SERVER_FREE_LIMITS=(
    ["brave-search"]="1,000 searches/month (\$5 free credits)"
    ["tavily"]="1,000 credits/month"
)

# --- Functions ---

configure_mcp_servers() {
    if ! command -v claude &>/dev/null; then
        echo "  ⚠ Claude Code CLI not found. Install it first:"
        echo "    curl -fsSL https://claude.ai/install.sh | bash"
        echo ""
        echo "  After installing, re-run this script or manually add MCP servers."
        echo ""
        return
    fi

    local key
    for key in "${INSTALL_MCP_SERVERS[@]}"; do
        _configure_single_mcp "${key}"
    done
}

_configure_single_mcp() {
    local key="$1"
    local env_var="${MCP_SERVER_ENV_VARS[${key}]}"
    local package="${MCP_SERVER_PACKAGES[${key}]}"
    local already_configured=false

    if [[ -f "${CLAUDE_JSON}" ]]; then
        if python3 - "${CLAUDE_JSON}" "${key}" <<'PYTHON_CHECK' 2>/dev/null; then
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if sys.argv[2] in data.get('mcpServers', {}):
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYTHON_CHECK
            already_configured=true
        fi
    fi

    if [[ "${already_configured}" == "true" ]]; then
        echo "  ✓ ${key} MCP already configured (user scope)"
    else
        echo "  Adding ${key} MCP server to user scope..."
        if claude mcp add "${key}" --scope user \
            -e "${env_var}=\${${env_var}}" \
            -- npx -y "${package}" 2>/dev/null; then
            echo "  ✓ ${key} MCP added to user scope"
        else
            echo "  ⚠ Failed to add ${key} MCP. You can add it manually:"
            echo "    claude mcp add ${key} --scope user \\"
            echo "      -e ${env_var}='\${${env_var}}' \\"
            echo "      -- npx -y ${package}"
        fi
    fi
}

check_mcp_env_vars() {
    local key
    for key in "${INSTALL_MCP_SERVERS[@]}"; do
        local env_var="${MCP_SERVER_ENV_VARS[${key}]}"
        local signup_url="${MCP_SERVER_SIGNUP_URLS[${key}]}"
        local free_limit="${MCP_SERVER_FREE_LIMITS[${key}]}"

        local env_val="${!env_var:-}"
        if [[ -n "${env_val}" ]]; then
            echo "  ✓ ${env_var} is set (${#env_val} chars)"
        else
            echo "  ⚠ ${env_var} not set. Add to your shell profile:"
            echo ""
            echo "    # Add to ~/.zshrc or ~/.bashrc:"
            echo "    export ${env_var}=\"your-api-key-here\""
            echo ""
            echo "    Get a free API key (${free_limit}):"
            echo "    ${signup_url}"
        fi
    done
}
