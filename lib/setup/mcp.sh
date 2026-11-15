# mcp.sh -- MCP server configuration
# Path: lib/setup/mcp.sh
# Sourced by setup.sh — do not execute directly.
# Compatible with Bash 3.2+ (no associative arrays).

# Python before 3.15 reads, writes and prints in the system code page (cp1252
# under Git Bash on Windows): UTF-8 mode, as 3.15 defaults, unless turned off.
export PYTHONUTF8="${PYTHONUTF8:-1}"

# --- MCP Server Registry ---

readonly MCP_SERVER_KEYS=("brave-search" "tavily")

# Lookup function — replaces associative arrays for Bash 3.2 compatibility.
# Usage: mcp_get <key> <field>
#   Fields: label, desc, env_var, package, signup_url, free_limit
mcp_get() {
    local key="$1" field="$2"
    case "${key}:${field}" in
        brave-search:label) echo "brave-search" ;;
        brave-search:desc) echo "Web, image, video, news, local search (1,000/mo free)" ;;
        brave-search:env_var) echo "BRAVE_API_KEY" ;;
        brave-search:package) echo "@brave/brave-search-mcp-server@2.1.4" ;;
        brave-search:signup_url) echo "https://api-dashboard.search.brave.com/" ;;
        brave-search:free_limit) echo "1,000 searches/month (\$5 free credits)" ;;
        tavily:label) echo "tavily" ;;
        tavily:desc) echo "AI-native search, extract, crawl, map, research (1,000/mo free)" ;;
        tavily:env_var) echo "TAVILY_API_KEY" ;;
        tavily:package) echo "tavily-mcp@0.2.17" ;;
        tavily:signup_url) echo "https://tavily.com" ;;
        tavily:free_limit) echo "1,000 credits/month" ;;
        *) return 1 ;;
    esac
}

# --- MCP Backend Detection ---
# Per server: fnox when it can decrypt that server's key, else the env file.
# Usage: detect_mcp_backend [key]   (key defaults to brave-search)
# Returns: "fnox" or "envfile"

readonly MCP_KEYS_ENV_FILE="${MCP_KEYS_ENV_FILE:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/mcp-keys.env}"

detect_mcp_backend() {
    local key="${1:-brave-search}" env_var
    env_var="$(mcp_get "${key}" env_var)"
    # From HOME, so a repository's fnox.toml is never read.
    if command -v fnox &>/dev/null && (cd "${HOME}" && fnox get "${env_var}") &>/dev/null; then
        echo "fnox"
        return
    fi
    echo "envfile"
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

    local key backend any_envfile=0
    for key in "${INSTALL_MCP_SERVERS[@]}"; do
        backend="$(detect_mcp_backend "${key}")"
        [[ "${backend}" == "envfile" ]] && any_envfile=1
        _configure_single_mcp "${key}" "${backend}"
    done

    # For servers on the envfile backend: create the keys env file
    if ((any_envfile)); then
        _create_mcp_keys_env
    fi
}

# Build the JSON config for a given MCP server and backend.
# Usage: _build_mcp_json <key> <backend>
# Outputs a JSON string suitable for `claude mcp add-json`.
# Uses jq for safe JSON construction (handles special chars in values).
_build_mcp_json() {
    local key="$1"
    local backend="$2"
    local package
    package="$(mcp_get "${key}" package)"

    if [[ "${backend}" == "fnox" ]]; then
        # mcp-fnox-inject passes the server only its own key, read from fnox in HOME.
        local env_var
        env_var="$(mcp_get "${key}" env_var)"
        jq -n -c \
            --arg env_var "${env_var}" \
            --arg package "${package}" \
            '{type:"stdio",command:"mcp-fnox-inject",args:[$env_var,"npx","-y",$package]}'
    else
        # Env file wrapper: mcp-env-inject npx -y <package>
        jq -n -c \
            --arg package "${package}" \
            '{type:"stdio",command:"mcp-env-inject",args:["npx","-y",$package]}'
    fi
}

_configure_single_mcp() {
    local key="$1"
    local backend="$2"
    local env_var package
    env_var="$(mcp_get "${key}" env_var)"
    package="$(mcp_get "${key}" package)"

    # Remove existing config so we can re-register with correct backend
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
            # Remove old config to re-register with correct wrapper
            claude mcp remove "${key}" --scope user 2>/dev/null || true
        fi
    fi

    echo "  Adding ${key} MCP server (${backend} backend)..."

    local mcp_json
    mcp_json="$(_build_mcp_json "${key}" "${backend}")"

    if claude mcp add-json --scope user "${key}" "${mcp_json}" 2>/dev/null; then
        echo "  ✓ ${key} MCP added (${backend} wrapper)"
    else
        echo "  ⚠ Failed to add ${key} MCP server."
        echo "    Manual: claude mcp add-json --scope user ${key} '${mcp_json}'"
    fi
}

# Create ~/.claude/mcp-keys.env from available sources.
# Sources (in priority order):
#   1. Current environment variables (set via .env + direnv, or manual export)
#   2. Repo .env file (if we're running from the repo directory)
_create_mcp_keys_env() {
    local keys_written=0
    local env_content=""

    echo ""
    echo "  Creating ${MCP_KEYS_ENV_FILE}..."

    local key
    for key in "${INSTALL_MCP_SERVERS[@]}"; do
        local env_var
        env_var="$(mcp_get "${key}" env_var)"

        # Try current environment first
        local env_val="${!env_var:-}"

        # Fall back to repo .env file
        if [[ -z "${env_val}" && -f "${REPO_DIR}/.env" ]]; then
            env_val="$(grep "^${env_var}=" "${REPO_DIR}/.env" 2>/dev/null | head -1 | cut -d'=' -f2- || true)"
        fi

        if [[ -n "${env_val}" ]]; then
            env_content+="${env_var}=${env_val}"$'\n'
            keys_written=$((keys_written + 1))
            echo "  ✓ ${env_var} written (${#env_val} chars)"
        else
            echo "  ⚠ ${env_var} not found — add it later with:"
            local signup_url
            signup_url="$(mcp_get "${key}" signup_url)"
            echo "    echo '${env_var}=YOUR_KEY' >> ${MCP_KEYS_ENV_FILE}"
            echo "    Get a key: ${signup_url}"
        fi
    done

    if [[ ${keys_written} -gt 0 ]]; then
        mkdir -p "$(dirname "${MCP_KEYS_ENV_FILE}")"
        printf '%s' "${env_content}" >"${MCP_KEYS_ENV_FILE}"
        chmod 600 "${MCP_KEYS_ENV_FILE}"
        echo ""
        echo "  ✓ ${MCP_KEYS_ENV_FILE} created (${keys_written} keys, mode 600)"
    else
        echo ""
        echo "  ⚠ No MCP keys found. Add them to ${MCP_KEYS_ENV_FILE} before using MCP servers."
    fi
}

check_mcp_env_vars() {
    local key env_var backend
    for key in "${INSTALL_MCP_SERVERS[@]}"; do
        env_var="$(mcp_get "${key}" env_var)"
        backend="$(detect_mcp_backend "${key}")"
        if [[ "${backend}" == "fnox" ]]; then
            echo "  ✓ ${env_var} in fnox — injected alone at ${key} launch"
        elif [[ -f "${MCP_KEYS_ENV_FILE}" ]] && grep -q "^${env_var}=" "${MCP_KEYS_ENV_FILE}" 2>/dev/null; then
            echo "  ✓ ${env_var} found in ${MCP_KEYS_ENV_FILE}"
        else
            local signup_url free_limit
            signup_url="$(mcp_get "${key}" signup_url)"
            free_limit="$(mcp_get "${key}" free_limit)"
            echo "  ⚠ ${env_var} missing from fnox and ${MCP_KEYS_ENV_FILE}"
            echo "    echo '${env_var}=YOUR_KEY' >> ${MCP_KEYS_ENV_FILE}"
            echo "    Get a free API key (${free_limit}): ${signup_url}"
        fi
    done
}
