#!/usr/bin/env bash
# statusline.sh -- Claude Code Statusline (Hybrid: API + ccusage)
# Path: .claude/scripts/statusline.sh
#
# Displays real-time session metrics in Claude Code's status bar.
# Uses Anthropic OAuth API for accurate utilization % and reset timer (ground truth).
# Caches API responses with stale-while-revalidate (SWR) pattern (30s TTL).
# Uses ccusage for token breakdown, cost, and burn rate.
# Falls back to ccusage estimation if API is unavailable.
#
# Wide:   opus-4.5 | session: 21% used | resets: 1h26m | in: 1.5k out: 563 | cache: 6.2M | $5.21 ($2.99/hr)
# Narrow: opus-4.5 | 21% | 1h26m | 1.5k/563/6.2M | $5.21
#
# Prerequisites: jq, curl, bc, ccusage (optional for token/cost data)
# Platforms:     macOS (Keychain), Linux (Secret Service / libsecret),
#                Windows Git Bash (Credential Manager via PowerShell)

set -uo pipefail

# --- Constants ---

readonly API_URL="https://api.anthropic.com/api/oauth/usage"
readonly KEYCHAIN_SERVICE="Claude Code-credentials"
readonly API_BETA_HEADER="oauth-2025-04-20"
readonly CURL_TIMEOUT=10
readonly DEFAULT_TERM_WIDTH=120
readonly WIDE_THRESHOLD=110
readonly FALLBACK_SESSION_LIMIT=17213778
readonly CACHE_FILE="/tmp/claude-statusline-api-cache"
readonly CACHE_TTL=30
readonly CACHE_MAX_AGE=300  # Serve stale data up to 5 min; beyond that, refetch synchronously

# --- Platform Detection ---

detect_platform() {
    case "$(uname -s)" in
        Darwin)            echo "macos" ;;
        Linux)             echo "linux" ;;
        MSYS*|MINGW*|CYGWIN*) echo "windows" ;;
        *)                 echo "unknown" ;;
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
        linux|windows)
            # GNU date handles ISO 8601 natively (Git Bash ships GNU coreutils)
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
        windows)
            # Windows: Claude Code stores OAuth credentials in Windows Credential Manager (via keytar)
            # Read using PowerShell P/Invoke into advapi32.dll CredRead
            if command -v powershell.exe &>/dev/null; then
                local ps_script
                ps_script=$(mktemp "${TMPDIR:-/tmp}/claude-cred-XXXXXX.ps1")
                cat > "${ps_script}" <<'PWSH_SCRIPT'
$ErrorActionPreference = 'Stop'
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct NativeCredential {
    public uint Flags;
    public uint Type;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
    [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
    public long LastWritten;
    public uint CredentialBlobSize;
    public IntPtr CredentialBlob;
    public uint Persist;
    public uint AttributeCount;
    public IntPtr Attributes;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
    [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
}

public class CredentialReader {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    public static extern void CredFree(IntPtr credential);

    public static string Read(string target) {
        IntPtr ptr;
        if (!CredRead(target, 1, 0, out ptr)) return null;
        var nc = (NativeCredential)Marshal.PtrToStructure(ptr, typeof(NativeCredential));
        var secret = Marshal.PtrToStringUni(nc.CredentialBlob, (int)(nc.CredentialBlobSize / 2));
        CredFree(ptr);
        return secret;
    }
}
'@
    Write-Output ([CredentialReader]::Read('Claude Code-credentials'))
} catch {
    exit 1
}
PWSH_SCRIPT
                local ps_path
                ps_path=$(cygpath -w "${ps_script}" 2>/dev/null || echo "${ps_script}")
                creds=$(powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${ps_path}" 2>/dev/null)
                local ps_exit=$?
                rm -f "${ps_script}"
                [[ ${ps_exit} -ne 0 ]] && return 1
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

# --- API Cache (Stale-While-Revalidate) ---

get_file_age() {
    local file="$1"
    local mtime now

    case "${PLATFORM}" in
        macos)         mtime=$(stat -f "%m" "${file}" 2>/dev/null) ;;
        linux|windows) mtime=$(stat -c "%Y" "${file}" 2>/dev/null) ;;
        *) return 1 ;;
    esac

    [[ -z "${mtime}" ]] && return 1
    now=$(date +%s)
    echo $((now - mtime))
}

refresh_api_cache() {
    local data
    data=$(get_api_session_data) || return 1
    [[ -n "${data}" ]] && printf "%s" "${data}" > "${CACHE_FILE}"
}

get_cached_api_data() {
    local cache_age=999999

    if [[ -f "${CACHE_FILE}" ]]; then
        cache_age=$(get_file_age "${CACHE_FILE}") || cache_age=999999
    fi

    # Fresh cache — serve immediately, no API call
    if [[ ${cache_age} -lt ${CACHE_TTL} ]]; then
        cat "${CACHE_FILE}"
        return 0
    fi

    # Stale cache (< 5 min) — serve stale data, refresh in background for next call
    if [[ -f "${CACHE_FILE}" && ${cache_age} -lt ${CACHE_MAX_AGE} ]]; then
        cat "${CACHE_FILE}"
        ( refresh_api_cache ) >/dev/null 2>&1 &
        disown 2>/dev/null
        return 0
    fi

    # No cache or ancient (> 5 min) — synchronous fetch (blocks once)
    local data
    data=$(get_api_session_data) || return 1
    [[ -n "${data}" ]] && printf "%s" "${data}" > "${CACHE_FILE}"
    printf "%s" "${data}"
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

    api_data=$(get_cached_api_data) || api_data=""

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
