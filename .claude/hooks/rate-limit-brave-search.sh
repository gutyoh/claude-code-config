#!/usr/bin/env bash
# rate-limit-brave-search.sh
# Path: .claude/hooks/rate-limit-brave-search.sh
#
# Claude Code PreToolUse hook that enforces rate limiting on Brave Search
# MCP tool calls. Prevents 429 (Too Many Requests) errors by serializing
# requests and enforcing a minimum delay between calls.
#
# Configuration:
#   BRAVE_API_RATE_LIMIT_MS       - Minimum milliseconds between calls (default: 1100)
#                                   Free tier: 1100 (1 req/sec + safety margin)
#                                   Paid tier:  50  (20 req/sec)
#   BRAVE_RATE_LIMIT_STATE_DIR    - Directory for lock + timestamp files
#                                   (default: /tmp). Overridable mainly so the
#                                   bats suite can isolate test state without
#                                   clobbering the user's real rate-limit
#                                   timestamp.
#
# Usage:     Configured in .claude/settings.json as a PreToolUse hook
#            with matcher "mcp__brave-search__.*"
# Platforms: macOS, Linux

set -euo pipefail

# --- Configuration ---

readonly RATE_LIMIT_MS="${BRAVE_API_RATE_LIMIT_MS:-1100}"
readonly STATE_DIR="${BRAVE_RATE_LIMIT_STATE_DIR:-/tmp}"
readonly LOCK_DIR="${STATE_DIR}/brave-search-rate-limit.lock"
readonly TIMESTAMP_FILE="${STATE_DIR}/brave-search-last-call"
mkdir -p "${STATE_DIR}" 2>/dev/null || true

# --- Portable Python (PEP 394) ---
# python3 on Unix/macOS, python on Windows Git Bash
if command -v python3 &>/dev/null && python3 --version &>/dev/null; then
    _PY="python3"
else
    _PY="python"
fi

# --- Helpers ---

# Get current time in milliseconds (portable: macOS + Linux + Windows)
now_ms() {
    "${_PY}" -c "import time; print(int(time.time() * 1000))"
}

# Acquire a portable lock using mkdir (atomic on POSIX)
acquire_lock() {
    local retries=0
    local max_retries=50 # 50 * 100ms = 5 seconds max wait
    while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
        retries=$((retries + 1))
        if [[ ${retries} -ge ${max_retries} ]]; then
            # Stale lock — force remove and retry once
            rm -rf "${LOCK_DIR}"
            mkdir "${LOCK_DIR}" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
}

release_lock() {
    rm -rf "${LOCK_DIR}"
}

# Ensure lock is released on exit (including errors/signals)
cleanup() {
    release_lock
}

# --- Main ---

main() {
    # Read stdin (required by hook contract, but we don't need the content)
    cat >/dev/null

    # Acquire serialization lock
    trap cleanup EXIT
    acquire_lock

    # Check time since last call
    if [[ -f "${TIMESTAMP_FILE}" ]]; then
        local last_call
        last_call=$(cat "${TIMESTAMP_FILE}")
        local now
        now=$(now_ms)
        local elapsed=$((now - last_call))

        if [[ ${elapsed} -lt ${RATE_LIMIT_MS} ]]; then
            local sleep_ms=$((RATE_LIMIT_MS - elapsed))
            local sleep_sec
            sleep_sec=$("${_PY}" -c "print(${sleep_ms} / 1000)")
            sleep "${sleep_sec}"
        fi
    fi

    # Record this call's timestamp
    now_ms >"${TIMESTAMP_FILE}"

    # Allow the tool call to proceed
    exit 0
}

main "$@"
