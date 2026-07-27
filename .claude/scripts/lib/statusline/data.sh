# data.sh -- ccusage, time formatting, and data collection
# Path: .claude/scripts/lib/statusline/data.sh
# Sourced by statusline.sh — do not execute directly.
#
# Usage data priority chain (future-proof):
#   1. Stdin JSON: rate_limit.five_hour_percentage (future Anthropic native)
#   2. Hook cache: ~/.claude/cache/claude-usage.json (PreToolUse Haiku ping)
#   3. OAuth API:  /api/oauth/usage with stale-while-error (legacy fallback)

# --- ccusage: SWR cache ------------------------------------------------------
#
# `ccusage blocks --json` walks every session transcript under ~/.claude. That
# is seconds of work that scales with how long you have used Claude Code — on a
# well-used machine it dominates the render completely, and it ran on EVERY
# render with no cache. The statusline is drawn after every turn, so the cost
# was paid continuously and concurrent renders piled up on top of each other.
#
# Two independent fixes, in order of how much they save:
#
#   1. Do not call it at all unless a component actually consumes it. The
#      component list is user config; someone who does not display cost or
#      token counts should never pay for them.
#   2. Cache the result and serve stale while refreshing in the background —
#      the same shape status.sh already uses. A render never waits on ccusage.
#
# The block is a 5-hour rolling window, so a minute-old number is not
# meaningfully different from a fresh one. Correctness here is "roughly current",
# not "to the token".

readonly CCUSAGE_CACHE_FILE="${_TMP_DIR:-/tmp}/ccusage-block.json"
readonly CCUSAGE_CACHE_TTL=60        # Fresh for a minute
readonly CCUSAGE_CACHE_MAX_STALE=900 # Serve stale up to 15 minutes
readonly CCUSAGE_LOCK_DIR="${_TMP_DIR:-/tmp}/ccusage-lock"
readonly CCUSAGE_LOCK_MAX_AGE=120 # Reclaim a lock left by a killed process

# Components whose values come from ccusage. Nothing else needs it.
readonly CCUSAGE_COMPONENTS="tokens_in tokens_out tokens_cache cost burn_rate"

# Is any ccusage-fed component actually being displayed?
_ccusage_needed() {
    local c
    for c in ${CCUSAGE_COMPONENTS}; do
        [[ ",${CONF_COMPONENTS}," == *",${c},"* ]] && return 0
    done
    return 1
}

_ccusage_cache_age() {
    [[ ! -f "${CCUSAGE_CACHE_FILE}" ]] && echo "999999" && return
    get_file_age "${CCUSAGE_CACHE_FILE}" 2>/dev/null || echo "999999"
}

# Run ccusage and replace the cache atomically.
#
# Atomic because a render may read the file while this writes it: a half-written
# JSON document parses as nothing and the statusline silently loses its numbers.
# Locked because N concurrent sessions would otherwise each spawn their own
# multi-second scan of the same data.
_refresh_ccusage_cache() {
    command -v ccusage >/dev/null 2>&1 || return 1

    if [[ -d "${CCUSAGE_LOCK_DIR}" ]]; then
        local lock_age
        lock_age=$(get_file_age "${CCUSAGE_LOCK_DIR}" 2>/dev/null || echo 0)
        if [[ "${lock_age}" -lt "${CCUSAGE_LOCK_MAX_AGE}" ]]; then
            return 1 # someone else is already refreshing
        fi
        rmdir "${CCUSAGE_LOCK_DIR}" 2>/dev/null
    fi
    mkdir "${CCUSAGE_LOCK_DIR}" 2>/dev/null || return 1

    local ccdata active_block tmp
    ccdata=$(ccusage blocks --json 2>/dev/null)
    if [[ -n "${ccdata}" && "${ccdata}" != "null" ]]; then
        active_block=$(echo "${ccdata}" | jq -c '.blocks[] | select(.isActive == true)' 2>/dev/null)
        if [[ -n "${active_block}" && "${active_block}" != "null" ]]; then
            tmp="${CCUSAGE_CACHE_FILE}.tmp.$$"
            printf '%s\n' "${active_block}" >"${tmp}" 2>/dev/null \
                && mv -f "${tmp}" "${CCUSAGE_CACHE_FILE}" 2>/dev/null
        fi
    fi

    rmdir "${CCUSAGE_LOCK_DIR}" 2>/dev/null
    return 0
}

# Emit the active block, never blocking the render on ccusage.
get_ccusage_block() {
    _ccusage_needed || return 1

    local age
    age=$(_ccusage_cache_age)

    # Fresh — serve it.
    if [[ "${age}" -lt "${CCUSAGE_CACHE_TTL}" && -f "${CCUSAGE_CACHE_FILE}" ]]; then
        cat "${CCUSAGE_CACHE_FILE}"
        return 0
    fi

    # Stale but usable — serve it now, refresh for the next render.
    if [[ "${age}" -lt "${CCUSAGE_CACHE_MAX_STALE}" && -f "${CCUSAGE_CACHE_FILE}" ]]; then
        cat "${CCUSAGE_CACHE_FILE}"
        _refresh_ccusage_cache &>/dev/null &
        disown 2>/dev/null || true
        return 0
    fi

    # Nothing usable. Start a refresh and report no data for this render only.
    _refresh_ccusage_cache &>/dev/null &
    disown 2>/dev/null || true
    return 1
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
# Staleness: if cache is older than HOOK_STALE_THRESHOLD (default 300s = 5 min),
# prefix percentage with ~ to indicate approximate/stale data.
HOOK_STALE_THRESHOLD="${HOOK_STALE_THRESHOLD:-300}"

get_hook_usage_data() {
    local cache_file="${HOOK_USAGE_CACHE:-${HOME}/.claude/cache/claude-usage.json}"
    [[ ! -f "${cache_file}" ]] && return 1

    local pct reset_epoch
    pct=$(jq -r '.five_hour_pct // empty' "${cache_file}" 2>/dev/null)
    [[ -z "${pct}" ]] && return 1

    reset_epoch=$(jq -r '.five_hour_reset_epoch // empty' "${cache_file}" 2>/dev/null)

    # Check staleness: if cache is older than threshold, mark approximate
    local cache_age=0
    local mtime
    case "$(uname -s)" in
        Darwin) mtime=$(stat -f "%m" "${cache_file}" 2>/dev/null) ;;
        Linux) mtime=$(stat -c "%Y" "${cache_file}" 2>/dev/null) ;;
        MSYS* | MINGW* | CYGWIN*) mtime=$(stat -c "%Y" "${cache_file}" 2>/dev/null) ;;
    esac
    if [[ -n "${mtime}" ]]; then
        cache_age=$(($(date +%s) - mtime))
    fi

    DATA_SESSION_PCT="${pct}"
    if [[ ${cache_age} -gt ${HOOK_STALE_THRESHOLD} ]]; then
        DATA_SESSION_PCT_STALE=1
    fi
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

    debug "=== Data Collection Start ==="
    debug "Platform: ${PLATFORM}"
    debug "Tmp dir: ${_TMP_DIR}"

    # Model name from stdin JSON
    DATA_MODEL=$(echo "${input}" | jq -r '.model.display_name // "claude"' \
        | sed 's/Claude //' \
        | tr '[:upper:]' '[:lower:]' \
        | tr ' ' '-')
    debug_var "DATA_MODEL" "${DATA_MODEL}"

    # Version from stdin JSON
    DATA_VERSION=$(echo "${input}" | jq -r '.version // empty')

    # Lines added/removed from stdin JSON
    DATA_LINES_ADDED=$(echo "${input}" | jq -r '.cost.total_lines_added // empty')
    DATA_LINES_REMOVED=$(echo "${input}" | jq -r '.cost.total_lines_removed // empty')

    # Session duration from stdin JSON
    DATA_SESSION_TIME_MS=$(echo "${input}" | jq -r '.cost.total_duration_ms // empty')

    # Current working directory from stdin JSON
    DATA_CWD=$(echo "${input}" | jq -r '.cwd // empty')

    # Account email. `|| true` because jq exits non-zero when ~/.claude.json is
    # missing — which is the normal state on a fresh install — and a bare
    # assignment would abort any caller running under `set -e`.
    DATA_EMAIL=$(jq -r '.oauthAccount.emailAddress // empty' ~/.claude.json 2>/dev/null || true)
    DATA_EMAIL="${DATA_EMAIL:-N/A}"
    debug_var "DATA_EMAIL" "${DATA_EMAIL}"

    # Claude Code service health status (cached, non-blocking)
    collect_service_status

    # Usage data: priority chain (1→2→3)
    debug "--- Usage Data Priority Chain ---"
    debug "Trying source 1: native stdin JSON..."
    if get_native_usage_data "${input}"; then
        debug "Source: native stdin JSON (rate_limit fields)"
    else
        debug "Trying source 2: hook cache..."
        if get_hook_usage_data; then
            debug "Source: hook cache (~/.claude/cache/claude-usage.json)"
        else
            debug "Trying source 3: OAuth API..."
            if get_oauth_usage_data; then
                debug "Source: OAuth API (/api/oauth/usage)"
            else
                debug "Source: NONE - all data sources failed"
            fi
        fi
    fi
    debug_var "DATA_SESSION_PCT" "${DATA_SESSION_PCT}"
    debug_var "DATA_WEEKLY_PCT" "${DATA_WEEKLY_PCT}"
    debug_var "DATA_TIME_LEFT" "${DATA_TIME_LEFT}"

    # Token + cost data from ccusage
    debug "--- ccusage Data ---"
    local active_block=""
    if active_block=$(get_ccusage_block 2>&1); then
        debug "ccusage: found active block"
        DATA_INPUT_TOKENS=$(echo "${active_block}" | jq -r '.tokenCounts.inputTokens // 0')
        DATA_OUTPUT_TOKENS=$(echo "${active_block}" | jq -r '.tokenCounts.outputTokens // 0')
        DATA_CACHE_READ=$(echo "${active_block}" | jq -r '.tokenCounts.cacheReadInputTokens // 0')
        DATA_COST_USD=$(echo "${active_block}" | jq -r '.costUSD // 0')
        DATA_BURN_RATE=$(echo "${active_block}" | jq -r '.burnRate.costPerHour // 0')
    else
        debug "ccusage: no active block (is ccusage installed? run: npm install -g ccusage)"
    fi
    debug_var "DATA_INPUT_TOKENS" "${DATA_INPUT_TOKENS}"
    debug_var "DATA_OUTPUT_TOKENS" "${DATA_OUTPUT_TOKENS}"
    debug_var "DATA_COST_USD" "${DATA_COST_USD}"

    debug "=== Data Collection End ==="
}
