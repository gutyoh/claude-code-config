#!/usr/bin/env bash
# statusline.sh -- Claude Code Statusline (Modular Component System)
# Path: .claude/scripts/statusline.sh
#
# Displays real-time session metrics in Claude Code's status bar.
#
# Usage data priority chain (future-proof):
#   1. Stdin JSON rate_limit.* fields (future Anthropic native — not yet available)
#   2. Hook cache ~/.claude/cache/claude-usage.json (PreToolUse Haiku ping headers)
#   3. OAuth API /api/oauth/usage with stale-while-error (legacy fallback)
#
# The PreToolUse/Stop hooks (refresh-usage-cache.sh) fire a tiny Haiku API
# call (~$0.00001) every 60s and cache rate limit headers. The statusline
# reads the cache file — zero API calls in the render path.
#
# Uses ccusage for token breakdown, cost, and burn rate.
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
readonly _TMP_DIR="/tmp/claude-statusline-${UID}"
readonly CACHE_FILE="${_TMP_DIR}/api-cache"
readonly CACHE_TTL=30
readonly LOCK_DIR="${_TMP_DIR}/api-lock"
readonly LOCK_MAX_AGE_S=30              # Force-remove stale locks from killed processes
readonly BACKOFF_FILE="${_TMP_DIR}/api-backoff"
readonly BACKOFF_INITIAL_S=30           # First backoff after 429/failure
readonly BACKOFF_MAX_S=300              # Cap at 5 minutes
readonly CONF_FILE="${HOME}/.claude/statusline.conf"

# --- Config Globals (overridden by load_config) ---

CONF_THEME="dark"
CONF_COMPONENTS="model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
CONF_BAR_STYLE="text"
CONF_BAR_PCT_INSIDE="false"
CONF_COMPACT="true"            # Compact mode: no verbose prefixes, tokens merged with /, burn_rate hidden
CONF_COLOR_SCOPE="percentage"  # "percentage" = color usage component only, "full" = color entire line
CONF_ICON=""                   # Prefix icon: e.g. "✻", "A\\", "❋", or "" for none
CONF_ICON_STYLE="plain"        # plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket
CONF_WEEKLY_SHOW_RESET="false" # Show weekly reset countdown inline with weekly %

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
DATA_SESSION_PCT_STALE=0
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
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        MSYS* | MINGW* | CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

PLATFORM="$(detect_platform)"
readonly PLATFORM

# --- Source Modules ---

_STATUSLINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_STATUSLINE_DIR}/lib/statusline/config.sh"
source "${_STATUSLINE_DIR}/lib/statusline/utils.sh"
source "${_STATUSLINE_DIR}/lib/statusline/api.sh"
source "${_STATUSLINE_DIR}/lib/statusline/cache.sh"
source "${_STATUSLINE_DIR}/lib/statusline/data.sh"
source "${_STATUSLINE_DIR}/lib/statusline/bar.sh"
source "${_STATUSLINE_DIR}/lib/statusline/color.sh"
source "${_STATUSLINE_DIR}/lib/statusline/components.sh"
source "${_STATUSLINE_DIR}/lib/statusline/assembly.sh"

# --- Main ---

main() {
    # Ensure user-specific tmp dir exists (prevents /tmp symlink attacks)
    [[ ! -d "${_TMP_DIR}" ]] && mkdir -p "${_TMP_DIR}" 2>/dev/null

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
