#!/usr/bin/env bash
# refresh-usage-cache.sh — PreToolUse/Stop hook for rate limit usage caching
# Path: .claude/hooks/refresh-usage-cache.sh
#
# Fires on every tool call and stop event. Checks cache age — if fresh, exits in <1ms.
# If stale (>60s), fires a BACKGROUND Haiku API call (~$0.00001) and
# extracts rate limit utilization from response headers:
#   anthropic-ratelimit-unified-5h-utilization: 0.13  (= 13%)
#   anthropic-ratelimit-unified-5h-reset: 1772740800  (epoch)
#
# This avoids the /api/oauth/usage endpoint entirely (which is rate-limited
# to the point of being unusable with multiple sessions).
#
# The statusline reads this cache file — zero API calls in the render path.
#
# Future-proof: when Anthropic adds rate_limit data to statusline stdin JSON,
# remove this hook from settings.json and the statusline reads stdin directly.
#
# Cache: ~/.claude/cache/claude-usage.json
# Cost:  ~$0.00001/call (8 input + 1 output Haiku tokens)
# Frequency: at most once per USAGE_CACHE_TTL (default 60s)

set -uo pipefail

# Consume stdin (hook receives tool_input JSON — we don't need it)
cat >/dev/null

CACHE_DIR="${HOME}/.claude/cache"
CACHE_FILE="${CACHE_DIR}/claude-usage.json"
USAGE_CACHE_TTL="${USAGE_CACHE_TTL:-60}"
KEYCHAIN_SERVICE="Claude Code-credentials"
HAIKU_MODEL="claude-haiku-4-5-20251001"

# --- Fast exit if cache is fresh ---

is_cache_fresh() {
    [[ ! -f "${CACHE_FILE}" ]] && return 1

    local mtime now age
    case "$(uname -s)" in
        Darwin)                    mtime=$(stat -f "%m" "${CACHE_FILE}" 2>/dev/null) ;;
        Linux | MSYS* | MINGW* | CYGWIN* | *_NT*) mtime=$(stat -c "%Y" "${CACHE_FILE}" 2>/dev/null) ;;
        *)                         return 1 ;;
    esac
    [[ -z "${mtime}" ]] && return 1

    now=$(date +%s)
    age=$((now - mtime))
    [[ ${age} -lt ${USAGE_CACHE_TTL} ]]
}

if is_cache_fresh; then
    exit 0
fi

# --- Background fetch ---

_get_token() {
    local creds=""
    case "$(uname -s)" in
        Darwin)
            creds=$(security find-generic-password -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null) || return 1
            ;;
        Linux)
            if command -v secret-tool &>/dev/null; then
                creds=$(secret-tool lookup service "${KEYCHAIN_SERVICE}" 2>/dev/null) || return 1
            else
                return 1
            fi
            ;;
        MSYS* | MINGW* | CYGWIN*)
            # Windows: read from credentials file (same as statusline api.sh)
            local creds_file="${HOME}/.claude/.credentials.json"
            if [[ -f "${creds_file}" ]]; then
                creds=$(cat "${creds_file}" 2>/dev/null)
            else
                return 1
            fi
            ;;
        *) return 1 ;;
    esac
    [[ -z "${creds}" ]] && return 1
    echo "${creds}" | jq -r '.claudeAiOauth.accessToken // empty'
}

_fetch_and_cache() {
    local token
    token=$(_get_token) || return 1
    [[ -z "${token}" ]] && return 1

    mkdir -p "${CACHE_DIR}" 2>/dev/null

    # Tiny Haiku call: 8 input + 1 output token ≈ $0.00001
    local response
    response=$(curl -si --max-time 15 "https://api.anthropic.com/v1/messages" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -d "{\"model\":\"${HAIKU_MODEL}\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
        2>/dev/null) || return 1

    # Extract rate limit headers
    local util_5h reset_5h status overage_util overage_reset
    util_5h=$(echo "${response}" | grep -i "anthropic-ratelimit-unified-5h-utilization:" | awk '{print $2}' | tr -d '\r\n ')
    reset_5h=$(echo "${response}" | grep -i "anthropic-ratelimit-unified-5h-reset:" | awk '{print $2}' | tr -d '\r\n ')
    status=$(echo "${response}" | grep -i "anthropic-ratelimit-unified-status:" | awk '{print $2}' | tr -d '\r\n ')
    overage_util=$(echo "${response}" | grep -i "anthropic-ratelimit-unified-overage-utilization:" | awk '{print $2}' | tr -d '\r\n ')
    overage_reset=$(echo "${response}" | grep -i "anthropic-ratelimit-unified-overage-reset:" | awk '{print $2}' | tr -d '\r\n ')

    [[ -z "${util_5h}" ]] && return 1

    # Convert 0.13 fraction to 13 percentage (integer, rounded to nearest)
    local pct
    pct=$(echo "${util_5h}" | awk '{printf "%d", $1 * 100 + 0.5}')

    local overage_pct="0"
    if [[ -n "${overage_util}" ]]; then
        overage_pct=$(echo "${overage_util}" | awk '{printf "%d", $1 * 100 + 0.5}')
    fi

    local now
    now=$(date +%s)

    # Write cache atomically (temp + mv prevents partial reads)
    local tmp_file="${CACHE_FILE}.tmp.$$"
    cat >"${tmp_file}" <<EOF
{"five_hour_pct":${pct},"five_hour_reset_epoch":${reset_5h:-0},"overage_pct":${overage_pct},"overage_reset_epoch":${overage_reset:-0},"status":"${status:-unknown}","fetched_at":${now}}
EOF
    mv -f "${tmp_file}" "${CACHE_FILE}"
}

# Run in background so the hook returns instantly.
# On Windows Git Bash (MSYS/MINGW), backgrounded processes get killed when the
# hook exits — disown doesn't survive. Run in foreground instead (~1-2s block
# every 60s when cache is stale; fast-exit path above handles the common case).
case "$(uname -s)" in
    MSYS* | MINGW* | CYGWIN*)
        _fetch_and_cache
        ;;
    *)
        _fetch_and_cache &
        disown 2>/dev/null
        ;;
esac
exit 0
