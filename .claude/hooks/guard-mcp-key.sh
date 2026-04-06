#!/usr/bin/env bash
# guard-mcp-key.sh
# Path: .claude/hooks/guard-mcp-key.sh
#
# Claude Code PreToolUse hook that blocks MCP tool calls when the required
# API key is not configured. Prevents noisy MCP server failures for users
# who haven't set up Brave/Tavily keys, and suggests /web-search as a
# zero-config fallback.
#
# Exit codes:
#   0 — Key is present, allow the MCP call
#   2 — Key is missing, block with helpful error message
#
# Usage:     Configured in .claude/settings.json as a PreToolUse hook
#            with matcher "mcp__(tavily|brave-search)__.*"
# Platforms: macOS, Linux

set -euo pipefail

# --- Service → env var mapping ---

resolve_key_var() {
    local tool_name="$1"
    case "${tool_name}" in
        mcp__tavily__*) echo "TAVILY_API_KEY" ;;
        mcp__brave-search__*) echo "BRAVE_API_KEY" ;;
        *) echo "" ;;
    esac
}

# --- Main ---

main() {
    local input
    input=$(cat)

    # Require jq for JSON parsing — fail-open if unavailable
    if ! command -v jq &>/dev/null; then
        exit 0
    fi

    # Extract tool name
    local tool_name
    tool_name=$(echo "${input}" | jq -r '.tool_name // empty' 2>/dev/null) || true
    if [[ -z "${tool_name}" ]]; then
        exit 0
    fi

    # Resolve the required env var
    local key_var
    key_var="$(resolve_key_var "${tool_name}")"
    if [[ -z "${key_var}" ]]; then
        exit 0
    fi

    # Check if the key is set and non-empty
    local key_value="${!key_var:-}"
    if [[ -n "${key_value}" ]]; then
        exit 0
    fi

    # Key is missing — block the call with a helpful message
    echo "No ${key_var} configured. Use /web-search instead (no API key needed), or set ${key_var} in your .env file and restart Claude Code." >&2
    exit 2
}

main "$@"
