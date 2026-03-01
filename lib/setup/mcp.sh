# mcp.sh -- MCP server configuration
# Path: lib/setup/mcp.sh
# Sourced by setup.sh — do not execute directly.
# Compatible with Bash 3.2+ (no associative arrays).

# --- MCP Server Registry ---

readonly MCP_SERVER_KEYS=("brave-search" "tavily")

# Lookup function — replaces associative arrays for Bash 3.2 compatibility.
# Usage: mcp_get <key> <field>
#   Fields: label, desc, env_var, package, signup_url, free_limit
mcp_get() {
    local key="$1" field="$2"
    case "${key}:${field}" in
        brave-search:label)      echo "brave-search" ;;
        brave-search:desc)       echo "Web, image, video, news, local search (1,000/mo free)" ;;
        brave-search:env_var)    echo "BRAVE_API_KEY" ;;
        brave-search:package)    echo "@brave/brave-search-mcp-server" ;;
        brave-search:signup_url) echo "https://api-dashboard.search.brave.com/" ;;
        brave-search:free_limit) echo "1,000 searches/month (\$5 free credits)" ;;
        tavily:label)            echo "tavily" ;;
        tavily:desc)             echo "AI-native search, extract, crawl, map, research (1,000/mo free)" ;;
        tavily:env_var)          echo "TAVILY_API_KEY" ;;
        tavily:package)          echo "tavily-mcp@0.2.17" ;;
        tavily:signup_url)       echo "https://tavily.com" ;;
        tavily:free_limit)       echo "1,000 credits/month" ;;
        *) return 1 ;;
    esac
}

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
    local env_var
    env_var="$(mcp_get "${key}" env_var)"
    local package
    package="$(mcp_get "${key}" package)"
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
        local env_var signup_url free_limit
        env_var="$(mcp_get "${key}" env_var)"
        signup_url="$(mcp_get "${key}" signup_url)"
        free_limit="$(mcp_get "${key}" free_limit)"

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
