# api.sh -- Credential retrieval and API functions
# Path: .claude/scripts/lib/statusline/api.sh
# Sourced by statusline.sh — do not execute directly.

# curl config line for the statusline's own requests. STATUSLINE_HTTPS_PROXY
# overrides the session's proxy, and set but empty means direct: a router that
# intercepts Claude Code's traffic would otherwise fail these requests' TLS.
curl_proxy_config() {
    [[ -n "${STATUSLINE_HTTPS_PROXY+set}" ]] || return 0
    printf 'proxy = "%s"\n' "${STATUSLINE_HTTPS_PROXY}"
}

# Claude Code names its login entry after CLAUDE_CONFIG_DIR, exactly as set:
# the base name plus "-" and the first 8 hex digits of its SHA-256.
keychain_service() {
    local dir="${CLAUDE_CONFIG_DIR:-}" sum
    if [[ -z "${dir}" ]]; then
        printf '%s' "${KEYCHAIN_SERVICE}"
        return
    fi
    sum=$(printf '%s' "${dir}" | { shasum -a 256 2>/dev/null || sha256sum; } | cut -c1-8)
    printf '%s-%s' "${KEYCHAIN_SERVICE}" "${sum}"
}

get_oauth_token() {
    local creds="" service
    service=$(keychain_service)
    # An empty service would ask the keychain for the first password item of
    # any kind, a System keychain one included: never query without a name.
    [[ -n "${service}" ]] || return 1

    debug "get_oauth_token: platform=${PLATFORM}"

    case "${PLATFORM}" in
        macos)
            creds=$(security find-generic-password -s "${service}" -w 2>/dev/null) || return 1
            ;;
        linux)
            # Desktop sessions keep the login in the keyring; headless hosts
            # (servers, containers) have only the credentials file.
            if command -v secret-tool &>/dev/null; then
                creds=$(secret-tool lookup service "${service}" 2>/dev/null) || creds=""
            fi
            if [[ -z "${creds}" ]]; then
                local creds_file="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/.credentials.json"
                [[ -f "${creds_file}" ]] && creds=$(cat "${creds_file}" 2>/dev/null)
                debug "get_oauth_token: linux fallback ${creds_file}"
            fi
            ;;
        windows)
            # Windows: read from the credentials file
            local creds_file="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/.credentials.json"
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
    local token="$1" headers body
    headers="${BACKOFF_FILE}.headers.$$"

    # The token goes in on stdin, so it never shows in the process list.
    body=$({
        curl_proxy_config
        printf 'header = "Authorization: Bearer %s"\n' "${token}"
    } | curl -s -K - -D "${headers}" --max-time "${CURL_TIMEOUT}" "${API_URL}" \
        -H "Accept: application/json" \
        -H "anthropic-beta: ${API_BETA_HEADER}" 2>/dev/null) || {
        rm -f "${headers}"
        return 1
    }
    record_retry_after "${headers}" || return 1
    printf '%s' "${body}"
}

# A 429's Retry-After, in seconds, for increase_backoff to wait at least that
# long; fails on a 429, so its body is never read as usage.
record_retry_after() {
    local headers="$1" status wait
    [[ -f "${headers}" ]] || return 0
    # Header lines end in CRLF; the last status line is the final response.
    status=$(awk '{ sub(/\r$/, "") } toupper($1) ~ /^HTTP\// { code = $2 } END { print code }' "${headers}")
    wait=$(awk -F': *' '{ sub(/\r$/, "") } tolower($1) == "retry-after" { v = $2 } END { print v }' "${headers}")
    rm -f "${headers}"
    [[ "${status}" == "429" ]] || return 0
    [[ "${wait}" =~ ^[0-9]+$ ]] && printf '%s' "${wait}" >"${BACKOFF_FILE}.retry-after"
    return 1
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
