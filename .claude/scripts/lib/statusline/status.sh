# status.sh -- Claude service status fetcher with SWR caching
# Path: .claude/scripts/lib/statusline/status.sh
# Sourced by statusline.sh — do not execute directly.
#
# Fetches service health from status.claude.com JSON API (Atlassian Statuspage).
# Extracts the "Claude Code" component status specifically.
# Maps API indicator to display labels: "on", "degraded", "partial", "outage", "maintenance".
# Uses a simple stale-while-error cache (no lock needed — public, unauthenticated endpoint).

readonly STATUS_CACHE_FILE="${_TMP_DIR}/status-cache"
readonly STATUS_CACHE_TTL=300          # Fresh for 5 minutes
readonly STATUS_CACHE_MAX_STALE=900    # Serve stale up to 15 minutes
readonly STATUS_CURL_TIMEOUT=3         # Tight timeout to avoid blocking render
readonly STATUS_API_URL="https://status.claude.com/api/v2/summary.json"

# Map Atlassian Statuspage component status to display label
_map_status_label() {
    case "$1" in
        operational)          echo "on" ;;
        degraded_performance) echo "degraded" ;;
        partial_outage)       echo "partial" ;;
        major_outage)         echo "outage" ;;
        under_maintenance)    echo "maintenance" ;;
        *)                    echo "" ;;
    esac
}

# Get age of status cache file in seconds
_status_cache_age() {
    [[ ! -f "${STATUS_CACHE_FILE}" ]] && echo "999999" && return
    local now file_mod
    now=$(date "+%s")
    case "${PLATFORM}" in
        macos) file_mod=$(stat -f "%m" "${STATUS_CACHE_FILE}" 2>/dev/null) ;;
        *)     file_mod=$(stat -c "%Y" "${STATUS_CACHE_FILE}" 2>/dev/null) ;;
    esac
    [[ -z "${file_mod}" ]] && echo "999999" && return
    echo $((now - file_mod))
}

# Fetch status from API and write label to cache
_fetch_and_cache_status() {
    local response raw_status label
    response=$(curl -s --max-time "${STATUS_CURL_TIMEOUT}" "${STATUS_API_URL}" 2>/dev/null) || return 1
    [[ -z "${response}" ]] && return 1

    raw_status=$(echo "${response}" | jq -r '.components[] | select(.name == "Claude Code") | .status' 2>/dev/null)
    [[ -z "${raw_status}" ]] && return 1

    label=$(_map_status_label "${raw_status}")
    [[ -z "${label}" ]] && return 1

    local tmp="${STATUS_CACHE_FILE}.tmp.$$"
    echo "${label}" > "${tmp}"
    mv -f "${tmp}" "${STATUS_CACHE_FILE}"
    echo "${label}"
}

# Main entry: collect Claude Code service status into DATA_CC_STATUS
# Non-blocking: always serves cached/empty immediately, refreshes in background.
collect_service_status() {
    # Skip entirely if cc_status is not in the component list (exact match)
    [[ ",${CONF_COMPONENTS}," != *",cc_status,"* ]] && return

    local cache_age
    cache_age=$(_status_cache_age)

    # Fresh cache — serve immediately
    if [[ ${cache_age} -lt ${STATUS_CACHE_TTL} && -f "${STATUS_CACHE_FILE}" ]]; then
        DATA_CC_STATUS=$(cat "${STATUS_CACHE_FILE}")
        return
    fi

    # Stale but within max stale window — serve stale, refresh in background
    if [[ ${cache_age} -lt ${STATUS_CACHE_MAX_STALE} && -f "${STATUS_CACHE_FILE}" ]]; then
        DATA_CC_STATUS=$(cat "${STATUS_CACHE_FILE}")
        _fetch_and_cache_status &>/dev/null 3>&- &
        disown 2>/dev/null
        return
    fi

    # Expired or no cache — serve empty, try to refresh in background
    DATA_CC_STATUS=""
    _fetch_and_cache_status &>/dev/null &
    disown 2>/dev/null
}
