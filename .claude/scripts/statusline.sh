#!/usr/bin/env bash
# statusline.sh -- Claude Code Statusline (Modular Component System)
# Path: .claude/scripts/statusline.sh
#
# Displays real-time session metrics in Claude Code's status bar.
# Uses Anthropic OAuth API for accurate utilization % and reset timer (ground truth).
# Caches API responses with stale-while-revalidate (SWR) pattern (30s TTL).
# Uses ccusage for token breakdown, cost, and burn rate.
# Falls back to ccusage estimation if API is unavailable.
#
# Components (configurable order):
#   model, usage, weekly, reset, tokens_in, tokens_out, tokens_cache,
#   cost, burn_rate, email, version, lines, session_time, cwd
#
# Bar styles (for 'usage' component, wide mode):
#   text      session: 21% used
#   block     [████████············] 21%
#   smooth    ████████░░░░░░░░░░░░░ 21%    (1/8th sub-character precision)
#   gradient  █████████▓▒░░░░░░░░░ 21%
#   thin      ━━━━━━━━╌╌╌╌╌╌╌╌╌╌╌╌ 21%
#   spark     ▄█▁ 21%                      (compact 5-char vertical bars)
#
# Config: ~/.claude/statusline.conf (key=value). Respects NO_COLOR env var.
# Legacy: single-line theme name still supported (auto-detected).
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
readonly CONF_FILE="${HOME}/.claude/statusline.conf"

# --- Config Globals (overridden by load_config) ---

CONF_THEME="dark"
CONF_COMPONENTS="model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
CONF_BAR_STYLE="text"
CONF_BAR_PCT_INSIDE="false"
CONF_COMPACT="true"  # Compact mode: no verbose prefixes, tokens merged with /, burn_rate hidden
CONF_COLOR_SCOPE="percentage"  # "percentage" = color usage component only, "full" = color entire line
CONF_ICON=""  # Prefix icon: e.g. "✻", "A\\", "❋", or "" for none
CONF_ICON_STYLE="plain"  # plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket
CONF_WEEKLY_SHOW_RESET="false"  # Show weekly reset countdown inline with weekly %

# --- Color Globals ---
# Four tiers: ok (<50%), caution (>=50%), warn (>=75%), crit (>=90%)
# Colors apply ONLY to the usage/percentage component, not the full statusline.

COLOR_OK=""
COLOR_CAUTION=""
COLOR_WARN=""
COLOR_CRIT=""
COLOR_RESET=""

# --- Data Globals (populated by collect_data) ---

DATA_MODEL=""
DATA_SESSION_PCT="--"
DATA_TIME_LEFT="--"
DATA_INPUT_TOKENS=0
DATA_OUTPUT_TOKENS=0
DATA_CACHE_READ=0
DATA_COST_USD=0
DATA_BURN_RATE=0
DATA_WEEKLY_PCT="--"
DATA_WEEKLY_TIME_LEFT="--"
DATA_EMAIL=""
DATA_VERSION=""
DATA_LINES_ADDED=""
DATA_LINES_REMOVED=""
DATA_SESSION_TIME_MS=""
DATA_CWD=""

# --- Width Flag ---

IS_WIDE="false"

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

# --- Config Loading ---

load_config() {
    [[ ! -f "${CONF_FILE}" ]] && return

    local first_line
    first_line=$(head -n1 "${CONF_FILE}" 2>/dev/null | tr -d '[:space:]')
    [[ -z "${first_line}" ]] && return

    # Legacy format detection: first non-empty line has no '='
    if [[ "${first_line}" != *"="* ]]; then
        CONF_THEME="${first_line}"
        return
    fi

    # Key=value format
    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "${key}" || "${key}" == \#* ]] && continue
        key=$(echo "${key}" | tr -d '[:space:]')
        value=$(echo "${value}" | tr -d '[:space:]')
        case "${key}" in
            theme)           CONF_THEME="${value}" ;;
            components)      CONF_COMPONENTS="${value}" ;;
            bar_style)       CONF_BAR_STYLE="${value}" ;;
            bar_pct_inside)  CONF_BAR_PCT_INSIDE="${value}" ;;
            compact)         CONF_COMPACT="${value}" ;;
            color_scope)     CONF_COLOR_SCOPE="${value}" ;;
            icon)            CONF_ICON="${value}" ;;
            icon_style)      CONF_ICON_STYLE="${value}" ;;
            weekly_show_reset) CONF_WEEKLY_SHOW_RESET="${value}" ;;
        esac
    done < "${CONF_FILE}"
}

# --- Theme Loading ---

load_theme() {
    # NO_COLOR convention (https://no-color.org/) — disable all color output
    if [[ -n "${NO_COLOR:-}" ]]; then
        COLOR_OK=""
        COLOR_CAUTION=""
        COLOR_WARN=""
        COLOR_CRIT=""
        COLOR_RESET=""
        return
    fi

    case "${CONF_THEME}" in
        dark)
            COLOR_OK=$'\033[0;34m'               # blue
            COLOR_CAUTION=$'\033[0;33m'           # yellow
            COLOR_WARN=$'\033[38;5;208m'          # orange (256-color)
            COLOR_CRIT=$'\033[0;31m'              # red
            COLOR_RESET=$'\033[0m'
            ;;
        light)
            COLOR_OK=$'\033[0;34m'               # blue
            COLOR_CAUTION=$'\033[0;33m'           # yellow
            COLOR_WARN=$'\033[38;5;208m'          # orange (256-color)
            COLOR_CRIT=$'\033[0;31m'              # red
            COLOR_RESET=$'\033[0m'
            ;;
        colorblind)
            COLOR_OK=$'\033[1;34m'               # bold blue
            COLOR_CAUTION=$'\033[1;33m'           # bold yellow
            COLOR_WARN=$'\033[1;36m'              # bold cyan
            COLOR_CRIT=$'\033[1;35m'              # bold magenta
            COLOR_RESET=$'\033[0m'
            ;;
        none)
            COLOR_OK=""
            COLOR_CAUTION=""
            COLOR_WARN=""
            COLOR_CRIT=""
            COLOR_RESET=""
            ;;
        *)
            COLOR_OK=$'\033[0;34m'
            COLOR_CAUTION=$'\033[0;33m'
            COLOR_WARN=$'\033[38;5;208m'
            COLOR_CRIT=$'\033[0;31m'
            COLOR_RESET=$'\033[0m'
            ;;
    esac
}

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
            date -d "${timestamp}" "+%s" 2>/dev/null
            ;;
        macos)
            local clean_date="${timestamp%%.*}"
            TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${clean_date}" "+%s" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

format_duration_ms() {
    local ms="${1:-0}"
    local total_sec=$((ms / 1000))
    local hours=$((total_sec / 3600))
    local mins=$(( (total_sec % 3600) / 60 ))

    if [[ ${hours} -gt 0 ]]; then
        echo "${hours}h${mins}m"
    else
        echo "${mins}m"
    fi
}

# --- Credential Retrieval ---

get_oauth_token() {
    local creds=""

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

    local weekly_util weekly_reset
    weekly_util=$(echo "${usage_json}" | jq -r '.seven_day.utilization // empty')
    weekly_reset=$(echo "${usage_json}" | jq -r '.seven_day.resets_at // empty')

    printf "%s\t%s\t%s\t%s" "${utilization}" "${resets_at}" "${weekly_util}" "${weekly_reset}"
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

    if [[ ${cache_age} -lt ${CACHE_TTL} ]]; then
        cat "${CACHE_FILE}"
        return 0
    fi

    if [[ -f "${CACHE_FILE}" && ${cache_age} -lt ${CACHE_MAX_AGE} ]]; then
        cat "${CACHE_FILE}"
        ( refresh_api_cache ) >/dev/null 2>&1 &
        disown 2>/dev/null
        return 0
    fi

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

# --- Data Collection ---

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

    # Session data: API first, ccusage fallback
    local api_data=""
    api_data=$(get_cached_api_data) || api_data=""

    if [[ -n "${api_data}" ]]; then
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

        # If API failed, fall back to ccusage estimation
        if [[ "${DATA_SESSION_PCT}" == "--" ]]; then
            local total_tokens remaining_min
            total_tokens=$(echo "${active_block}" | jq -r '.totalTokens // 0')
            DATA_SESSION_PCT=$((total_tokens * 100 / FALLBACK_SESSION_LIMIT))

            remaining_min=$(echo "${active_block}" | jq -r '.projection.remainingMinutes // 0')
            local fb_hours=$((remaining_min / 60))
            local fb_mins=$((remaining_min % 60))
            DATA_TIME_LEFT="${fb_hours}h${fb_mins}m"
        fi
    fi
}

# --- Progress Bar Rendering ---

render_progress_bar() {
    local pct="$1"
    local style="${2:-text}"
    local width="${3:-20}"
    local show_inner="${4:-false}"

    # Handle non-numeric pct
    if [[ "${pct}" == "--" || -z "${pct}" ]]; then
        case "${style}" in
            text)  printf "session: %s" "--"; return ;;
            spark) printf "%s" "--"; return ;;
            *)
                # Empty bar
                local empty_bar=""
                local i
                for ((i = 0; i < width; i++)); do
                    case "${style}" in
                        block)    empty_bar+="·" ;;
                        thin)     empty_bar+="╌" ;;
                        *)        empty_bar+="░" ;;
                    esac
                done
                case "${style}" in
                    block) printf "[%s] --" "${empty_bar}" ;;
                    *)     printf "%s --" "${empty_bar}" ;;
                esac
                return
                ;;
        esac
    fi

    # Clamp 0-100
    local clamped=${pct}
    (( clamped < 0 )) && clamped=0
    (( clamped > 100 )) && clamped=100

    case "${style}" in
        text)
            printf "session: %s%% used" "${clamped}"
            ;;

        block)
            # [████████············] 21%
            local filled=$(( clamped * width / 100 ))
            local empty=$(( width - filled ))
            local bar=""
            local i
            for ((i = 0; i < filled; i++)); do bar+="█"; done
            for ((i = 0; i < empty; i++)); do bar+="·"; done

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}"
            fi

            printf "[%s]" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        smooth)
            # Full unicode block bar with 1/8th sub-character precision
            # Partial block chars: ▏(1/8) ▎(2/8) ▍(3/8) ▌(4/8) ▋(5/8) ▊(6/8) ▉(7/8) █(8/8)
            local partials=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            local total_eighths=$(( clamped * width * 8 / 100 ))
            local full_blocks=$(( total_eighths / 8 ))
            local remainder=$(( total_eighths % 8 ))
            local empty_blocks=$(( width - full_blocks - (remainder > 0 ? 1 : 0) ))

            local bar=""
            local i
            for ((i = 0; i < full_blocks; i++)); do bar+="█"; done
            if [[ ${remainder} -gt 0 ]]; then
                bar+="${partials[${remainder}]}"
            fi
            for ((i = 0; i < empty_blocks; i++)); do bar+="░"; done

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}"
            fi

            printf "%s" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        gradient)
            # Powerline gradient: █▓▒░
            # Filled region uses █, transition uses ▓▒, empty uses ░
            local filled=$(( clamped * width / 100 ))
            local empty=$(( width - filled ))
            local bar=""
            local i

            if [[ ${filled} -eq 0 ]]; then
                # All empty
                for ((i = 0; i < width; i++)); do bar+="░"; done
            elif [[ ${empty} -eq 0 ]]; then
                # All filled
                for ((i = 0; i < width; i++)); do bar+="█"; done
            else
                # Filled blocks (leave room for ▓ transition)
                for ((i = 0; i < filled; i++)); do bar+="█"; done

                # Gradient transition: replace last empty char(s) with ▓ then ▒
                local remaining=$((empty))
                if [[ ${remaining} -ge 1 ]]; then
                    bar+="▓"
                    remaining=$((remaining - 1))
                fi
                if [[ ${remaining} -ge 1 ]]; then
                    bar+="▒"
                    remaining=$((remaining - 1))
                fi

                # Remaining empty
                for ((i = 0; i < remaining; i++)); do bar+="░"; done
            fi

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}"
            fi

            printf "%s" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        thin)
            # ━━━━━━━━╌╌╌╌╌╌╌╌╌╌╌╌ 21%
            local filled=$(( clamped * width / 100 ))
            local empty=$(( width - filled ))
            local bar=""
            local i
            for ((i = 0; i < filled; i++)); do bar+="━"; done
            for ((i = 0; i < empty; i++)); do bar+="╌"; done

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}"
            fi

            printf "%s" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        spark)
            # Compact spark-style vertical bars (5 chars wide)
            # Maps percentage to spark chars: ▁▂▃▄▅▆▇█
            local spark_chars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
            local spark_width=5
            local bar=""
            local i

            for ((i = 0; i < spark_width; i++)); do
                # Each position represents a segment of the percentage
                local seg_start=$(( i * 100 / spark_width ))
                local seg_end=$(( (i + 1) * 100 / spark_width ))

                if [[ ${clamped} -ge ${seg_end} ]]; then
                    # Fully filled segment
                    bar+="█"
                elif [[ ${clamped} -le ${seg_start} ]]; then
                    # Empty segment
                    bar+="▁"
                else
                    # Partial segment — map within-segment percentage to spark char
                    local seg_range=$((seg_end - seg_start))
                    local seg_fill=$((clamped - seg_start))
                    local idx=$(( seg_fill * 7 / seg_range ))
                    (( idx > 7 )) && idx=7
                    bar+="${spark_chars[${idx}]}"
                fi
            done

            printf "%s %s%%" "${bar}" "${clamped}"
            ;;

        *)
            # Unknown style, fall back to text
            printf "session: %s%% used" "${clamped}"
            ;;
    esac
}

# Helper: overlay " NN% " at center of bar string (passed by nameref)
_overlay_pct_inside() {
    local -n _bar="$1"
    local pct="$2"
    local width="$3"

    local pct_str=" ${pct}% "
    local pct_len=${#pct_str}

    # Only overlay if bar is wide enough
    if [[ ${width} -ge $((pct_len + 2)) ]]; then
        local start=$(( (width - pct_len) / 2 ))
        # Build new bar with overlay
        local new_bar=""
        local i=0
        local char_idx=0

        # We need to iterate character by character accounting for multi-byte
        local bar_chars=()
        local tmp="${_bar}"
        while [[ -n "${tmp}" ]]; do
            # Extract one character (handles multi-byte UTF-8)
            local ch="${tmp:0:1}"
            # Check if it's a multi-byte char by checking byte length
            local byte_len=${#ch}
            if [[ ${byte_len} -eq 0 ]]; then
                # Try getting more bytes for multi-byte char
                ch=$(printf '%s' "${tmp}" | head -c 3)
                byte_len=${#ch}
            fi
            bar_chars+=("${ch}")
            tmp="${tmp:${#ch}}"
        done

        local total_chars=${#bar_chars[@]}
        new_bar=""
        for ((i = 0; i < total_chars; i++)); do
            if [[ ${i} -ge ${start} && ${char_idx} -lt ${pct_len} ]]; then
                new_bar+="${pct_str:${char_idx}:1}"
                char_idx=$((char_idx + 1))
            else
                new_bar+="${bar_chars[${i}]}"
            fi
        done

        _bar="${new_bar}"
    fi
}

# --- Utilization Color Helpers ---

# Returns the ANSI color code for a given utilization percentage.
# Usage: get_color_for_pct <pct>
get_color_for_pct() {
    local pct="$1"

    if [[ "${pct}" == "--" || -z "${pct}" ]]; then
        return
    fi

    if [[ "${pct}" -ge 90 ]]; then
        printf "%s" "${COLOR_CRIT}"
    elif [[ "${pct}" -ge 75 ]]; then
        printf "%s" "${COLOR_WARN}"
    elif [[ "${pct}" -ge 50 ]]; then
        printf "%s" "${COLOR_CAUTION}"
    else
        printf "%s" "${COLOR_OK}"
    fi
}

# Returns the ANSI color code for the current session utilization level.
get_utilization_color() {
    get_color_for_pct "${DATA_SESSION_PCT}"
}

# --- Component Renderers ---

render_component_model() {
    printf "%s" "${DATA_MODEL}"
}

render_component_usage() {
    local raw=""

    if [[ "${IS_WIDE}" == "true" ]]; then
        if [[ "${CONF_COMPACT}" == "true" && "${CONF_BAR_STYLE}" == "text" ]]; then
            raw=$(printf "%s%%" "${DATA_SESSION_PCT}")
        else
            raw=$(render_progress_bar "${DATA_SESSION_PCT}" "${CONF_BAR_STYLE}" 20 "${CONF_BAR_PCT_INSIDE}")
        fi
    else
        raw=$(printf "%s%%" "${DATA_SESSION_PCT}")
    fi

    # Wrap in color when color_scope=percentage
    if [[ "${CONF_COLOR_SCOPE}" == "percentage" ]]; then
        local ucolor
        ucolor=$(get_utilization_color)
        if [[ -n "${ucolor}" ]]; then
            printf "%s%s%s" "${ucolor}" "${raw}" "${COLOR_RESET}"
        else
            printf "%s" "${raw}"
        fi
    else
        printf "%s" "${raw}"
    fi
}

render_component_weekly() {
    local raw=""

    if [[ "${IS_WIDE}" == "true" && "${CONF_COMPACT}" != "true" ]]; then
        raw=$(printf "weekly: %s%%" "${DATA_WEEKLY_PCT}")
    else
        raw=$(printf "%s%%" "${DATA_WEEKLY_PCT}")
    fi

    # Append reset countdown if configured
    if [[ "${CONF_WEEKLY_SHOW_RESET}" == "true" && "${DATA_WEEKLY_TIME_LEFT}" != "--" ]]; then
        raw+=" (${DATA_WEEKLY_TIME_LEFT})"
    fi

    # Wrap in color when color_scope=percentage
    if [[ "${CONF_COLOR_SCOPE}" == "percentage" ]]; then
        local wcolor
        wcolor=$(get_color_for_pct "${DATA_WEEKLY_PCT}")
        if [[ -n "${wcolor}" ]]; then
            printf "%s%s%s" "${wcolor}" "${raw}" "${COLOR_RESET}"
        else
            printf "%s" "${raw}"
        fi
    else
        printf "%s" "${raw}"
    fi
}

render_component_reset() {
    if [[ "${IS_WIDE}" == "true" && "${CONF_COMPACT}" != "true" ]]; then
        printf "resets: %s" "${DATA_TIME_LEFT}"
    else
        printf "%s" "${DATA_TIME_LEFT}"
    fi
}

render_component_tokens_in() {
    local in_fmt
    in_fmt=$(format_num "${DATA_INPUT_TOKENS}")
    if [[ "${IS_WIDE}" == "true" && "${CONF_COMPACT}" != "true" ]]; then
        printf "in: %s" "${in_fmt}"
    else
        printf "%s" "${in_fmt}"
    fi
}

render_component_tokens_out() {
    local out_fmt
    out_fmt=$(format_num "${DATA_OUTPUT_TOKENS}")
    if [[ "${IS_WIDE}" == "true" && "${CONF_COMPACT}" != "true" ]]; then
        printf "out: %s" "${out_fmt}"
    else
        printf "%s" "${out_fmt}"
    fi
}

render_component_tokens_cache() {
    local cache_fmt
    cache_fmt=$(format_num "${DATA_CACHE_READ}")
    if [[ "${IS_WIDE}" == "true" && "${CONF_COMPACT}" != "true" ]]; then
        printf "cache: %s" "${cache_fmt}"
    else
        printf "%s" "${cache_fmt}"
    fi
}

render_component_cost() {
    local cost_fmt
    cost_fmt=$(printf "%.2f" "${DATA_COST_USD}")
    printf "\$%s" "${cost_fmt}"
}

render_component_burn_rate() {
    # Hidden in narrow mode and compact mode
    [[ "${IS_WIDE}" != "true" || "${CONF_COMPACT}" == "true" ]] && return

    local burn_fmt
    burn_fmt=$(printf "%.2f" "${DATA_BURN_RATE}")
    printf "(\$%s/hr)" "${burn_fmt}"
}

render_component_email() {
    printf "%s" "${DATA_EMAIL}"
}

render_component_version() {
    [[ -z "${DATA_VERSION}" ]] && return
    printf "%s" "${DATA_VERSION}"
}

render_component_lines() {
    [[ -z "${DATA_LINES_ADDED}" && -z "${DATA_LINES_REMOVED}" ]] && return

    local added="${DATA_LINES_ADDED:-0}"
    local removed="${DATA_LINES_REMOVED:-0}"

    if [[ "${IS_WIDE}" == "true" ]]; then
        printf "+%s -%s" "${added}" "${removed}"
    else
        local a_fmt r_fmt
        a_fmt=$(format_num "${added}")
        r_fmt=$(format_num "${removed}")
        printf "+%s/-%s" "${a_fmt}" "${r_fmt}"
    fi
}

render_component_session_time() {
    [[ -z "${DATA_SESSION_TIME_MS}" ]] && return
    format_duration_ms "${DATA_SESSION_TIME_MS}"
}

render_component_cwd() {
    [[ -z "${DATA_CWD}" ]] && return

    if [[ "${IS_WIDE}" == "true" ]]; then
        # Replace $HOME with ~
        local display="${DATA_CWD/#${HOME}/\~}"
        printf "%s" "${display}"
    else
        # Narrow: basename only
        printf "%s" "$(basename "${DATA_CWD}")"
    fi
}

# --- Component Assembly ---

render_all_components() {
    local IFS=','
    local components_arr=(${CONF_COMPONENTS})
    unset IFS

    local outputs=()
    local keys=()
    local i

    for i in "${!components_arr[@]}"; do
        local key="${components_arr[$i]}"
        # Trim whitespace
        key=$(echo "${key}" | tr -d '[:space:]')

        # Check if render function exists
        if ! declare -f "render_component_${key}" &>/dev/null; then
            continue
        fi

        local output
        output=$(render_component_"${key}")

        # Skip empty outputs
        [[ -z "${output}" ]] && continue

        outputs+=("${output}")
        keys+=("${key}")
    done

    # Build final string with token merging in narrow mode
    local result=""
    local idx=0
    local total=${#outputs[@]}

    while [[ ${idx} -lt ${total} ]]; do
        local current_key="${keys[${idx}]}"
        local current_out="${outputs[${idx}]}"

        # Component merging: merge adjacent related components with /
        # Groups: tokens (tokens_in/out/cache), usage (usage/weekly)
        # Active in narrow mode always, and in wide mode when compact
        if [[ "${IS_WIDE}" != "true" || "${CONF_COMPACT}" == "true" ]]; then
            local merge_group=""
            case "${current_key}" in
                tokens_in|tokens_out|tokens_cache) merge_group="tokens" ;;
                usage|weekly) merge_group="usage" ;;
            esac

            if [[ -n "${merge_group}" ]]; then
                local merged="${current_out}"
                local next=$((idx + 1))

                while [[ ${next} -lt ${total} ]]; do
                    local next_group=""
                    case "${keys[${next}]}" in
                        tokens_in|tokens_out|tokens_cache) next_group="tokens" ;;
                        usage|weekly) next_group="usage" ;;
                    esac
                    if [[ "${next_group}" == "${merge_group}" ]]; then
                        merged+="/${outputs[${next}]}"
                        next=$((next + 1))
                    else
                        break
                    fi
                done

                if [[ -n "${result}" ]]; then
                    result+=" | "
                fi
                result+="${merged}"
                idx=${next}
                continue
            fi
        fi

        if [[ -n "${result}" ]]; then
            result+=" | "
        fi
        result+="${current_out}"
        idx=$((idx + 1))
    done

    printf "%s" "${result}"
}

# --- Main ---

main() {
    load_config
    load_theme

    # Read Claude's JSON input from stdin
    local input term_width
    input=$(cat)
    # Skip tput cols — in piped subprocesses (how Claude Code runs this script),
    # tput succeeds but returns a bogus 80. Use $COLUMNS if set (interactive shell),
    # otherwise assume a modern wide terminal (120). Claude Code truncates on its side.
    term_width="${COLUMNS:-${DEFAULT_TERM_WIDTH}}"

    if [[ "${term_width}" -ge "${WIDE_THRESHOLD}" ]]; then
        IS_WIDE="true"
    fi

    # Collect all data
    collect_data "${input}"

    # Render all components (usage component self-colors when color_scope=percentage)
    local output
    output=$(render_all_components)

    # Prepend icon if configured, styled per icon_style
    local icon_prefix=""
    if [[ -n "${CONF_ICON}" ]]; then
        local bold=$'\033[1m'
        local reverse=$'\033[7m'
        local blue=$'\033[0;34m'
        local rst=$'\033[0m'

        case "${CONF_ICON_STYLE}" in
            bold)
                icon_prefix="${bold}${CONF_ICON}${rst} "
                ;;
            bracketed)
                icon_prefix="[${CONF_ICON}] "
                ;;
            rounded)
                icon_prefix="(${CONF_ICON}) "
                ;;
            reverse)
                icon_prefix="${reverse} ${CONF_ICON} ${rst} "
                ;;
            bold-color)
                icon_prefix="${bold}${blue}${CONF_ICON}${rst} "
                ;;
            angle)
                icon_prefix="⟨${CONF_ICON}⟩ "
                ;;
            double-bracket)
                icon_prefix="⟦${CONF_ICON}⟧ "
                ;;
            *)
                # plain
                icon_prefix="${CONF_ICON} "
                ;;
        esac
    fi

    # Apply full-line color only when color_scope=full
    # Use the most critical (highest) utilization across session and weekly
    if [[ "${CONF_COLOR_SCOPE}" == "full" ]]; then
        local color="" max_pct="${DATA_SESSION_PCT}"
        if [[ "${max_pct}" == "--" ]]; then
            max_pct="${DATA_WEEKLY_PCT}"
        elif [[ "${DATA_WEEKLY_PCT}" != "--" && "${DATA_WEEKLY_PCT}" -gt "${max_pct}" ]]; then
            max_pct="${DATA_WEEKLY_PCT}"
        fi
        color=$(get_color_for_pct "${max_pct}")
        if [[ -n "${color}" ]]; then
            printf "%s%s%s%s" "${color}" "${icon_prefix}" "${output}" "${COLOR_RESET}"
        else
            printf "%s%s" "${icon_prefix}" "${output}"
        fi
    else
        printf "%s%s" "${icon_prefix}" "${output}"
    fi
}

# Source guard: only run main() when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
