# api.sh -- Credential retrieval and API functions
# Path: .claude/scripts/lib/statusline/api.sh
# Sourced by statusline.sh — do not execute directly.

get_oauth_token() {
    local creds=""

    debug "get_oauth_token: platform=${PLATFORM}"

    case "${PLATFORM}" in
        macos)
            creds=$(security find-generic-password -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null) || return 1
            ;;
        linux)
            if command -v secret-tool &>/dev/null; then
                creds=$(secret-tool lookup service "${KEYCHAIN_SERVICE}" 2>/dev/null) || return 1
            else
                return 1
            fi
            ;;
        windows)
            # Windows: read from ~/.claude/.credentials.json file
            local creds_file="${HOME}/.claude/.credentials.json"
            if [[ -f "${creds_file}" ]]; then
                creds=$(cat "${creds_file}" 2>/dev/null)
                debug "get_oauth_token: read from ${creds_file}"
            else
                debug "get_oauth_token: credentials file not found: ${creds_file}"
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac

    if [[ -z "${creds}" ]]; then
        debug "get_oauth_token: no credentials found"
        return 1
    fi

    debug "get_oauth_token: credentials found (${#creds} chars)"
    local token
    token=$(echo "${creds}" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    if [[ -z "${token}" ]]; then
        debug "get_oauth_token: failed to extract accessToken from JSON"
        return 1
    fi
    debug "get_oauth_token: token extracted (${#token} chars)"
    echo "${token}"
}

fetch_api_usage() {
    local token="$1"

    curl -s --max-time "${CURL_TIMEOUT}" "${API_URL}" \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/json" \
        -H "anthropic-beta: ${API_BETA_HEADER}" 2>/dev/null || return 1
}

get_api_session_data() {
    local token usage_json utilization resets_at

    debug "get_api_session_data: fetching OAuth token..."
    token=$(get_oauth_token) || {
        debug "get_api_session_data: failed to get OAuth token"
        return 1
    }
    [[ -z "${token}" ]] && return 1

    debug "get_api_session_data: calling API..."
    usage_json=$(fetch_api_usage "${token}") || {
        debug "get_api_session_data: API call failed"
        return 1
    }
    if [[ -z "${usage_json}" ]]; then
        debug "get_api_session_data: empty API response"
        return 1
    fi
    debug "get_api_session_data: got response (${#usage_json} chars)"

    utilization=$(echo "${usage_json}" | jq -r '.five_hour.utilization // empty')
    resets_at=$(echo "${usage_json}" | jq -r '.five_hour.resets_at // empty')

    if [[ -z "${utilization}" ]]; then
        debug "get_api_session_data: no utilization in response"
        debug "get_api_session_data: response preview: ${usage_json:0:200}"
        return 1
    fi
    debug "get_api_session_data: utilization=${utilization}"

    local weekly_util weekly_reset
    weekly_util=$(echo "${usage_json}" | jq -r '.seven_day.utilization // empty')
    weekly_reset=$(echo "${usage_json}" | jq -r '.seven_day.resets_at // empty')

    printf "%s\t%s\t%s\t%s" "${utilization}" "${resets_at}" "${weekly_util}" "${weekly_reset}"
}
