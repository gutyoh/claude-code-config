#!/usr/bin/env bash
# statusline.sh -- Claude Code Statusline (Hybrid: API + ccusage)
# Path: .claude/scripts/statusline.sh
#
# Displays real-time session metrics in Claude Code's status bar.
# Uses Anthropic OAuth API for accurate utilization % and reset timer (ground truth).
# Uses ccusage for token breakdown, cost, and burn rate.
# Falls back to ccusage estimation if API is unavailable.
#
# Wide:   opus-4.5 | session: 21% used | resets: 1h26m | in: 1.5k out: 563 | cache: 6.2M | $5.21 ($2.99/hr)
# Narrow: opus-4.5 | 21% | 1h26m | 1.5k/563/6.2M | $5.21
#
# Prerequisites: jq, curl, bc, ccusage (optional for token/cost data)
# Platforms:     macOS (Keychain), Linux (Secret Service / libsecret)

set -uo pipefail

# --- Constants ---

readonly API_URL="https://api.anthropic.com/api/oauth/usage"
readonly KEYCHAIN_SERVICE="Claude Code-credentials"
readonly API_BETA_HEADER="oauth-2025-04-20"
readonly CURL_TIMEOUT=3
readonly DEFAULT_TERM_WIDTH=120
readonly WIDE_THRESHOLD=110
readonly FALLBACK_SESSION_LIMIT=17213778

# --- Platform Detection ---

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

readonly PLATFORM="$(detect_platform)"

# --- Utility Functions ---

format_num() {
    local num="${1:-0}"

    if [[ "${num}" -ge 1000000 ]]; then
        printf "%.1fM" "$(echo "scale=1; ${num} / 1000000" | bc)"
    elif [[ "${num}" -ge 1000 ]]; then
        printf "%.1fk" "$(echo "scale=1; ${num} / 1000" | bc)"
    else
        printf "%d" "${num}"
    fi
}

iso8601_to_epoch() {
    local timestamp="$1"

    case "${PLATFORM}" in
        linux)
            # GNU date handles ISO 8601 natively
            date -d "${timestamp}" "+%s" 2>/dev/null
            ;;
        macos)
            # BSD date requires manual format string; strip fractional seconds
            local clean_date="${timestamp%%.*}"
            TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${clean_date}" "+%s" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# --- Credential Retrieval ---

get_oauth_token() {
    local creds=""

    case "${PLATFORM}" in
        macos)
            # macOS: Claude Code stores OAuth credentials in Keychain
            creds=$(security find-generic-password -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null) || return 1
            ;;
        linux)
            # Linux: Claude Code stores OAuth credentials via libsecret (Secret Service API)
            if command -v secret-tool &>/dev/null; then
                creds=$(secret-tool lookup service "${KEYCHAIN_SERVICE}" 2>/dev/null) || return 1
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac

    [[ -z "${creds}" ]] && return 1
    echo "${creds}" | jq -r '.claudeAiOauth.accessToken // empty'
}

# --- API Functions ---

fetch_api_usage() {
    local token="$1"

    curl -s --max-time "${CURL_TIMEOUT}" "${API_URL}" \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/json" \
        -H "anthropic-beta: ${API_BETA_HEADER}" 2>/dev/null || return 1
}

get_api_session_data() {
    local token usage_json utilization resets_at

    token=$(get_oauth_token) || return 1
    [[ -z "${token}" ]] && return 1

    usage_json=$(fetch_api_usage "${token}") || return 1
    [[ -z "${usage_json}" ]] && return 1

    utilization=$(echo "${usage_json}" | jq -r '.five_hour.utilization // empty')
    resets_at=$(echo "${usage_json}" | jq -r '.five_hour.resets_at // empty')

    [[ -z "${utilization}" ]] && return 1

    # Output as tab-separated: utilization\tresets_at
    printf "%s\t%s" "${utilization}" "${resets_at}"
}

# --- ccusage Functions ---

get_ccusage_block() {
    local ccdata active_block

    ccdata=$(ccusage blocks --json 2>/dev/null) || return 1
    [[ -z "${ccdata}" || "${ccdata}" == "null" ]] && return 1

    active_block=$(echo "${ccdata}" | jq '.blocks[] | select(.isActive == true)' 2>/dev/null)
    [[ -z "${active_block}" || "${active_block}" == "null" ]] && return 1

    echo "${active_block}"
}

# --- Time Formatting ---

calculate_time_remaining() {
    local resets_at="$1"
    [[ -z "${resets_at}" ]] && echo "--" && return

    local reset_epoch now_epoch remaining_seconds hours mins

    reset_epoch=$(iso8601_to_epoch "${resets_at}") || { echo "--"; return; }
    now_epoch=$(date "+%s")
    remaining_seconds=$((reset_epoch - now_epoch))

    if [[ "${remaining_seconds}" -le 0 ]]; then
        echo "0h0m"
        return
    fi

    hours=$((remaining_seconds / 3600))
    mins=$(( (remaining_seconds % 3600) / 60 ))
    echo "${hours}h${mins}m"
}

# --- Main ---

main() {
    # Read Claude's JSON input from stdin
    local input term_width model
    input=$(cat)
    term_width="${COLUMNS:-$(tput cols 2>/dev/null || echo "${DEFAULT_TERM_WIDTH}")}"
    model=$(echo "${input}" | jq -r '.model.display_name // "claude"' \
        | sed 's/Claude //' \
        | tr '[:upper:]' '[:lower:]' \
        | tr ' ' '-')

    # --- Session data: API first, ccusage fallback ---
    local session_pct="--"
    local time_left="--"
    local api_data=""

    api_data=$(get_api_session_data) || api_data=""

    if [[ -n "${api_data}" ]]; then
        # API succeeded -- ground truth from Anthropic servers
        local utilization resets_at
        utilization=$(printf "%s" "${api_data}" | cut -f1)
        resets_at=$(printf "%s" "${api_data}" | cut -f2)
        session_pct="${utilization%%.*}"   # 21.0 -> 21
        session_pct="${session_pct:-0}"
        time_left=$(calculate_time_remaining "${resets_at}")
    fi

    # --- Token + cost data from ccusage ---
    local active_block=""
    local input_tokens=0 output_tokens=0 cache_read=0 cost_usd=0 burn_rate=0

    active_block=$(get_ccusage_block) || active_block=""

    if [[ -n "${active_block}" ]]; then
        input_tokens=$(echo "${active_block}" | jq -r '.tokenCounts.inputTokens // 0')
        output_tokens=$(echo "${active_block}" | jq -r '.tokenCounts.outputTokens // 0')
        cache_read=$(echo "${active_block}" | jq -r '.tokenCounts.cacheReadInputTokens // 0')
        cost_usd=$(echo "${active_block}" | jq -r '.costUSD // 0')
        burn_rate=$(echo "${active_block}" | jq -r '.burnRate.costPerHour // 0')

        # If API failed, fall back to ccusage estimation for session %
        if [[ "${session_pct}" == "--" ]]; then
            local total_tokens remaining_min
            total_tokens=$(echo "${active_block}" | jq -r '.totalTokens // 0')
            session_pct=$((total_tokens * 100 / FALLBACK_SESSION_LIMIT))

            remaining_min=$(echo "${active_block}" | jq -r '.projection.remainingMinutes // 0')
            local fb_hours=$((remaining_min / 60))
            local fb_mins=$((remaining_min % 60))
            time_left="${fb_hours}h${fb_mins}m"
        fi
    fi

    # --- Format values ---
    local in_fmt out_fmt cache_fmt cost_fmt burn_fmt
    in_fmt=$(format_num "${input_tokens}")
    out_fmt=$(format_num "${output_tokens}")
    cache_fmt=$(format_num "${cache_read}")
    cost_fmt=$(printf "%.2f" "${cost_usd}")
    burn_fmt=$(printf "%.2f" "${burn_rate}")

    # --- Output based on terminal width ---
    if [[ "${term_width}" -ge "${WIDE_THRESHOLD}" ]]; then
        printf "%s | session: %s%% used | resets: %s | in: %s out: %s | cache: %s | \$%s (\$%s/hr)" \
            "${model}" "${session_pct}" "${time_left}" \
            "${in_fmt}" "${out_fmt}" "${cache_fmt}" \
            "${cost_fmt}" "${burn_fmt}"
    else
        printf "%s | %s%% | %s | %s/%s/%s | \$%s" \
            "${model}" "${session_pct}" "${time_left}" \
            "${in_fmt}" "${out_fmt}" "${cache_fmt}" \
            "${cost_fmt}"
    fi
}

main "$@"
