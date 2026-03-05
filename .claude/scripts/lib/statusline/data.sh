# data.sh -- ccusage, time formatting, and data collection
# Path: .claude/scripts/lib/statusline/data.sh
# Sourced by statusline.sh — do not execute directly.
#
# Usage data priority chain (future-proof):
#   1. Stdin JSON: rate_limit.five_hour_percentage (future Anthropic native)
#   2. Hook cache: ~/.claude/cache/claude-usage.json (PreToolUse Haiku ping)
#   3. OAuth API:  /api/oauth/usage with stale-while-error (legacy fallback)

get_ccusage_block() {
    local ccdata active_block

    ccdata=$(ccusage blocks --json 2>/dev/null) || return 1
    [[ -z "${ccdata}" || "${ccdata}" == "null" ]] && return 1

    active_block=$(echo "${ccdata}" | jq '.blocks[] | select(.isActive == true)' 2>/dev/null)
    [[ -z "${active_block}" || "${active_block}" == "null" ]] && return 1

    echo "${active_block}"
}

calculate_time_remaining() {
    local resets_at="$1"
    [[ -z "${resets_at}" ]] && echo "--" && return

    local reset_epoch now_epoch remaining_seconds hours mins

    reset_epoch=$(iso8601_to_epoch "${resets_at}") || {
        echo "--"
        return
    }
    now_epoch=$(date "+%s")
    remaining_seconds=$((reset_epoch - now_epoch))

    if [[ "${remaining_seconds}" -le 0 ]]; then
        echo "0h0m"
        return
    fi

    hours=$((remaining_seconds / 3600))
    mins=$(((remaining_seconds % 3600) / 60))
    echo "${hours}h${mins}m"
}

# Calculate time remaining from an epoch timestamp (not ISO)
calculate_time_remaining_epoch() {
    local reset_epoch="$1"
    [[ -z "${reset_epoch}" || "${reset_epoch}" == "0" ]] && echo "--" && return

    local now_epoch remaining_seconds hours mins
    now_epoch=$(date "+%s")
    remaining_seconds=$((reset_epoch - now_epoch))

    if [[ "${remaining_seconds}" -le 0 ]]; then
        echo "0h0m"
        return
    fi

    hours=$((remaining_seconds / 3600))
    mins=$(((remaining_seconds % 3600) / 60))
    echo "${hours}h${mins}m"
}

# Priority 1: Check stdin JSON for native rate_limit data (future Anthropic feature)
get_native_usage_data() {
    local input="$1"
    local pct
    pct=$(echo "${input}" | jq -r '.rate_limit.five_hour_percentage // empty' 2>/dev/null)
    [[ -z "${pct}" ]] && return 1

    local reset
    reset=$(echo "${input}" | jq -r '.rate_limit.five_hour_reset_seconds // empty' 2>/dev/null)

    DATA_SESSION_PCT="${pct%%.*}"
    DATA_SESSION_PCT="${DATA_SESSION_PCT:-0}"

    if [[ -n "${reset}" && "${reset}" != "0" ]]; then
        local hours=$((reset / 3600))
        local mins=$(((reset % 3600) / 60))
        DATA_TIME_LEFT="${hours}h${mins}m"
    fi
    return 0
}

# Priority 2: Read hook cache (PreToolUse Haiku ping headers)
get_hook_usage_data() {
    local cache_file="${HOOK_USAGE_CACHE:-${HOME}/.claude/cache/claude-usage.json}"
    [[ ! -f "${cache_file}" ]] && return 1

    local pct reset_epoch
    pct=$(jq -r '.five_hour_pct // empty' "${cache_file}" 2>/dev/null)
    [[ -z "${pct}" ]] && return 1

    reset_epoch=$(jq -r '.five_hour_reset_epoch // empty' "${cache_file}" 2>/dev/null)

    DATA_SESSION_PCT="${pct}"
    DATA_TIME_LEFT=$(calculate_time_remaining_epoch "${reset_epoch}")
    return 0
}

# Priority 3: OAuth API with stale-while-error (legacy fallback)
get_oauth_usage_data() {
    local api_data=""
    api_data=$(get_cached_api_data) || return 1
    [[ -z "${api_data}" ]] && return 1

    local utilization resets_at weekly_util weekly_reset
    utilization=$(printf "%s" "${api_data}" | cut -f1)
    resets_at=$(printf "%s" "${api_data}" | cut -f2)
    weekly_util=$(printf "%s" "${api_data}" | cut -f3)
    weekly_reset=$(printf "%s" "${api_data}" | cut -f4)
    DATA_SESSION_PCT="${utilization%%.*}"
    DATA_SESSION_PCT="${DATA_SESSION_PCT:-0}"
    DATA_TIME_LEFT=$(calculate_time_remaining "${resets_at}")

    if [[ -n "${weekly_util}" ]]; then
        DATA_WEEKLY_PCT="${weekly_util%%.*}"
        DATA_WEEKLY_PCT="${DATA_WEEKLY_PCT:-0}"
        DATA_WEEKLY_TIME_LEFT=$(calculate_time_remaining "${weekly_reset}")
    fi
    return 0
}

collect_data() {
    local input="$1"

    # Model name from stdin JSON
    DATA_MODEL=$(echo "${input}" | jq -r '.model.display_name // "claude"' \
        | sed 's/Claude //' \
        | tr '[:upper:]' '[:lower:]' \
        | tr ' ' '-')

    # Version from stdin JSON
    DATA_VERSION=$(echo "${input}" | jq -r '.version // empty')

    # Lines added/removed from stdin JSON
    DATA_LINES_ADDED=$(echo "${input}" | jq -r '.cost.total_lines_added // empty')
    DATA_LINES_REMOVED=$(echo "${input}" | jq -r '.cost.total_lines_removed // empty')

    # Session duration from stdin JSON
    DATA_SESSION_TIME_MS=$(echo "${input}" | jq -r '.cost.total_duration_ms // empty')

    # Current working directory from stdin JSON
    DATA_CWD=$(echo "${input}" | jq -r '.cwd // empty')

    # Account email
    DATA_EMAIL=$(jq -r '.oauthAccount.emailAddress // empty' ~/.claude.json 2>/dev/null)
    DATA_EMAIL="${DATA_EMAIL:-N/A}"

    # Usage data: priority chain (1→2→3)
    if ! get_native_usage_data "${input}"; then
        if ! get_hook_usage_data; then
            get_oauth_usage_data || true
        fi
    fi

    # Token + cost data from ccusage
    local active_block=""
    active_block=$(get_ccusage_block) || active_block=""

    if [[ -n "${active_block}" ]]; then
        DATA_INPUT_TOKENS=$(echo "${active_block}" | jq -r '.tokenCounts.inputTokens // 0')
        DATA_OUTPUT_TOKENS=$(echo "${active_block}" | jq -r '.tokenCounts.outputTokens // 0')
        DATA_CACHE_READ=$(echo "${active_block}" | jq -r '.tokenCounts.cacheReadInputTokens // 0')
        DATA_COST_USD=$(echo "${active_block}" | jq -r '.costUSD // 0')
        DATA_BURN_RATE=$(echo "${active_block}" | jq -r '.burnRate.costPerHour // 0')
    fi
}
