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
#   AUTO_ROTATE_COOLDOWN_SEC   - Seconds between rotations (default: 300)
#                                Prevents repeated rotations before restart.
#   AUTO_ROTATE_STATE_DIR      - Override state directory (default: /tmp)
#   AUTO_ROTATE_CMD_TIMEOUT_SEC - Max seconds the mcp-key-rotate subprocess
#                                may run before being killed (default: 30).
#                                Guards against e.g. a macOS Keychain prompt
#                                hanging the PostToolUse hook indefinitely.
#                                Requires GNU `timeout` (install via
#                                `brew install coreutils` on macOS). When
#                                unavailable the subprocess runs without
#                                a timeout.
#
# Usage:     Configured in .claude/settings.json as a PostToolUse hook
#            with matcher "mcp__(tavily|brave-search)__.*"
# Platforms: macOS, Linux

set -euo pipefail

# --- Configuration ---

readonly COOLDOWN_SEC="${AUTO_ROTATE_COOLDOWN_SEC:-300}"
readonly STATE_DIR="${AUTO_ROTATE_STATE_DIR:-/tmp}"
readonly CMD_TIMEOUT_SEC="${AUTO_ROTATE_CMD_TIMEOUT_SEC:-30}"

# --- Helpers ---

now_epoch() {
    date +%s
}

cooldown_file() {
    local service="$1"
    echo "${STATE_DIR}/mcp-auto-rotate-${service}.ts"
}

lock_dir() {
    local service="$1"
    echo "${STATE_DIR}/mcp-auto-rotate-${service}.lock"
}

# Acquire a per-service lock (atomic mkdir, same pattern as rate-limit hook)
acquire_lock() {
    local service="$1"
    local lockdir
    lockdir="$(lock_dir "${service}")"
    mkdir -p "${STATE_DIR}"

    local retries=0
    local max_retries=20 # 20 * 100ms = 2 seconds max wait
    while ! mkdir "${lockdir}" 2>/dev/null; do
        retries=$((retries + 1))
        if [[ ${retries} -ge ${max_retries} ]]; then
            # Stale lock — force remove and retry once
            rm -rf "${lockdir}"
            mkdir "${lockdir}" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
}

release_lock() {
    local service="$1"
    rm -rf "$(lock_dir "${service}")"
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
            # Anchored patterns: require context words to avoid false positives
            # (e.g. "found 432 results" won't match)
            if [[ "${result_text}" =~ status[[:space:]]*code[[:space:]]*432 ]] ||
               [[ "${result_text}" =~ [Ee]rror[[:space:]:.]*432 ]] ||
               [[ "${result_text}" =~ HTTP[[:space:]]*432 ]] ||
               [[ "${result_text}" =~ [Qq]uota[[:space:]]*(exceeded|exhausted|reached|limit) ]] ||
               [[ "${result_text}" =~ [Rr]ate[[:space:]]*[Ll]imit ]]; then
                return 0
            fi
            ;;
        brave)
            # Brave returns HTTP 429 for rate limit / quota
            if [[ "${result_text}" =~ status[[:space:]]*code[[:space:]]*429 ]] ||
               [[ "${result_text}" =~ [Ee]rror[[:space:]:.]*429 ]] ||
               [[ "${result_text}" =~ HTTP[[:space:]]*429 ]] ||
               [[ "${result_text}" =~ [Tt]oo[[:space:]]*[Mm]any[[:space:]]*[Rr]equests ]] ||
               [[ "${result_text}" =~ [Rr]ate[[:space:]]*[Ll]imit ]] ||
               [[ "${result_text}" =~ [Qq]uota[[:space:]]*(exceeded|exhausted|reached|limit) ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# --- Bounded subprocess execution ---

# Run "$@" with a wall-clock timeout if GNU `timeout` is available. Returns
# the command's exit status on success, 124 if the timeout fires, or runs
# without bound if no timeout binary is present.
run_with_timeout() {
    local seconds="$1"
    shift
    if command -v timeout &>/dev/null; then
        timeout --foreground --kill-after=5s "${seconds}s" "$@"
    elif command -v gtimeout &>/dev/null; then
        gtimeout --foreground --kill-after=5s "${seconds}s" "$@"
    else
        "$@"
    fi
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

    # Extract tool result (handles string, object, array, scalar, or null)
    # Check multiple possible field names for robustness
    local result_text
    result_text=$(echo "${input}" | jq -r '
        [.tool_result, .tool_output, .tool_error, .error] |
        map(select(. != null)) |
        map(tostring) |
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

    # Acquire per-service lock (atomic mkdir) to prevent concurrent rotations
    acquire_lock "${service}"
    trap 'release_lock "${service}"' EXIT

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

    # Execute rotation (bounded by CMD_TIMEOUT_SEC so a hung subprocess —
    # e.g. a macOS Keychain prompt — can never freeze the PostToolUse chain)
    local rotate_output rotate_status
    rotate_output=$(run_with_timeout "${CMD_TIMEOUT_SEC}" "${rotate_cmd}" "${service}" 2>&1) || rotate_status=$?
    rotate_status="${rotate_status:-0}"
    if [[ "${rotate_status}" -eq 124 ]]; then
        echo "[auto-rotate] ${service}: API quota exhausted. Auto-rotation timed out after ${CMD_TIMEOUT_SEC}s (subprocess may be stuck on a prompt)."
        echo "Run manually: mcp-key-rotate ${service}"
        exit 0
    fi
    if [[ "${rotate_status}" -ne 0 ]]; then
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
