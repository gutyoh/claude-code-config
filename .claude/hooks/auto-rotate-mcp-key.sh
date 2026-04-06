#!/usr/bin/env bash
# auto-rotate-mcp-key.sh
# Path: .claude/hooks/auto-rotate-mcp-key.sh
#
# Claude Code PostToolUse hook that auto-rotates MCP API keys when quota
# exhaustion is detected (Tavily HTTP 432, Brave HTTP 429).
#
# On detection:
#   1. Runs mcp-key-rotate <service> to advance to the next pool key
#   2. Outputs a message telling Claude to inform the user to restart
#   3. Enters cooldown to prevent rotation storms (MCP server still holds old key)
#
# Configuration:
#   AUTO_ROTATE_COOLDOWN_SEC  - Seconds between rotations (default: 300)
#                               Prevents repeated rotations before restart.
#   AUTO_ROTATE_STATE_DIR     - Override state directory (default: /tmp)
#
# Usage:     Configured in .claude/settings.json as a PostToolUse hook
#            with matcher "mcp__(tavily|brave-search)__.*"
# Platforms: macOS, Linux

set -euo pipefail

# --- Configuration ---

readonly COOLDOWN_SEC="${AUTO_ROTATE_COOLDOWN_SEC:-300}"
readonly STATE_DIR="${AUTO_ROTATE_STATE_DIR:-/tmp}"

# --- Helpers ---

now_epoch() {
    date +%s
}

cooldown_file() {
    local service="$1"
    echo "${STATE_DIR}/mcp-auto-rotate-${service}.ts"
}

is_in_cooldown() {
    local service="$1"
    local cf
    cf="$(cooldown_file "${service}")"

    if [[ ! -f "${cf}" ]]; then
        return 1 # Not in cooldown
    fi

    local last_rotate now elapsed
    last_rotate="$(cat "${cf}" 2>/dev/null || echo "0")"
    # Validate numeric
    if [[ ! "${last_rotate}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    now="$(now_epoch)"
    elapsed=$((now - last_rotate))

    if [[ ${elapsed} -lt ${COOLDOWN_SEC} ]]; then
        return 0 # In cooldown
    fi
    return 1 # Cooldown expired
}

set_cooldown() {
    local service="$1"
    mkdir -p "${STATE_DIR}"
    now_epoch >"$(cooldown_file "${service}")"
}

# --- Service resolution ---

resolve_service() {
    local tool_name="$1"
    case "${tool_name}" in
        mcp__tavily__*) echo "tavily" ;;
        mcp__brave-search__*) echo "brave" ;;
        *) echo "" ;;
    esac
}

# --- Error detection ---

is_quota_error() {
    local service="$1" result_text="$2"

    case "${service}" in
        tavily)
            # Tavily returns HTTP 432 for quota exhaustion
            if [[ "${result_text}" =~ 432 ]] ||
               [[ "${result_text}" =~ [Qq]uota ]] ||
               [[ "${result_text}" =~ [Rr]ate[[:space:]]*[Ll]imit ]]; then
                return 0
            fi
            ;;
        brave)
            # Brave returns HTTP 429 for rate limit / quota
            if [[ "${result_text}" =~ 429 ]] ||
               [[ "${result_text}" =~ [Tt]oo[[:space:]]*[Mm]any[[:space:]]*[Rr]equests ]] ||
               [[ "${result_text}" =~ [Rr]ate[[:space:]]*[Ll]imit ]] ||
               [[ "${result_text}" =~ [Qq]uota ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# --- Locate mcp-key-rotate ---

find_rotate_cmd() {
    # 1. In PATH (installed via setup.sh to ~/.local/bin/)
    local cmd
    cmd="$(command -v mcp-key-rotate 2>/dev/null || echo "")"
    if [[ -n "${cmd}" && -x "${cmd}" ]]; then
        echo "${cmd}"
        return
    fi

    # 2. Common install location
    if [[ -x "${HOME}/.local/bin/mcp-key-rotate" ]]; then
        echo "${HOME}/.local/bin/mcp-key-rotate"
        return
    fi

    # 3. Repo-relative (hook is at .claude/hooks/, script at bin/)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_cmd="${script_dir}/../../bin/mcp-key-rotate"
    if [[ -x "${repo_cmd}" ]]; then
        echo "${repo_cmd}"
        return
    fi

    echo ""
}

# --- Main ---

main() {
    local input
    input=$(cat)

    # Require jq for JSON parsing
    if ! command -v jq &>/dev/null; then
        exit 0
    fi

    # Extract tool name
    local tool_name
    tool_name=$(echo "${input}" | jq -r '.tool_name // empty' 2>/dev/null) || true
    if [[ -z "${tool_name}" ]]; then
        exit 0
    fi

    # Resolve service
    local service
    service="$(resolve_service "${tool_name}")"
    if [[ -z "${service}" ]]; then
        exit 0
    fi

    # Extract tool result (handles string, object, or null)
    # Check multiple possible field names for robustness
    local result_text
    result_text=$(echo "${input}" | jq -r '
        [.tool_result, .tool_output, .tool_error, .error] |
        map(select(. != null)) |
        map(if type == "object" then tostring else . end) |
        join(" ")
    ' 2>/dev/null) || true

    if [[ -z "${result_text}" ]]; then
        exit 0
    fi

    # Check for quota exhaustion
    if ! is_quota_error "${service}" "${result_text}"; then
        exit 0
    fi

    # --- Quota error detected ---

    # Check cooldown (prevent rotation storms)
    if is_in_cooldown "${service}"; then
        echo "[auto-rotate] ${service}: API quota still exhausted. Key was already rotated -- restart Claude Code to apply the new key."
        echo "Suggest /web-search as an immediate fallback (no API key needed)."
        exit 0
    fi

    # Locate rotation script
    local rotate_cmd
    rotate_cmd="$(find_rotate_cmd)"
    if [[ -z "${rotate_cmd}" ]]; then
        echo "[auto-rotate] ${service}: API quota exhausted but mcp-key-rotate not found."
        echo "Run manually: mcp-key-rotate ${service}"
        exit 0
    fi

    # Execute rotation
    local rotate_output
    if ! rotate_output=$("${rotate_cmd}" "${service}" 2>&1); then
        echo "[auto-rotate] ${service}: API quota exhausted. Auto-rotation failed: ${rotate_output}"
        echo "Run manually: mcp-key-rotate ${service}"
        exit 0
    fi

    # Record cooldown
    set_cooldown "${service}"

    # Output for Claude (shown as additional context to the model)
    echo "[auto-rotate] ${service}: API quota exhausted. ${rotate_output}"
    echo "ACTION REQUIRED: Restart Claude Code for the new key to take effect."
    echo "IMMEDIATE FALLBACK: Use /web-search (Claude built-in search, no API key needed)."

    exit 0
}

main "$@"
