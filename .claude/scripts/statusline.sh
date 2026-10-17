#!/usr/bin/env bash
# statusline.sh -- Claude Code Statusline (Modular Component System)
# Path: .claude/scripts/statusline.sh
#
# Displays real-time session metrics in Claude Code's status bar.
#
# Usage follows the session's model (lib/statusline/providers.sh):
#   Claude models:
#     1. Stdin JSON rate_limits.five_hour / seven_day (when Claude Code sends them)
#     2. OAuth API /api/oauth/usage, cached with stale-while-error
#     3. Hook cache ~/.claude/cache/claude-usage.json (5-hour only)
#   GPT models:  the ChatGPT plan's windows, from the Codex login
#   Muse models: the Muse Code plan's windows, from the Muse login
# Every read is read-only: no login is ever refreshed here.
#
# Uses ccusage for token breakdown, cost, and burn rate.
#
# Components (configurable order):
#   model, usage, weekly, reset, tokens_in, tokens_out, tokens_cache,
#   cost, burn_rate, email, host, cc_status, version, lines, session_time, cwd
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
# statusline.d/*.conf, then statusline.local.conf, override its keys: the first
# for files other tools own, the second for that profile alone.
# style.<component>= colors one component (lib/statusline/style.sh).
# Legacy: single-line theme name still supported (auto-detected).
#
# Prerequisites: jq, curl, awk, cksum, ccusage (optional for token/cost data)
# Platforms:     macOS (Keychain), Linux (Secret Service / libsecret),
#                Windows Git Bash (Credential Manager via PowerShell)

set -uo pipefail

# --- Debug Mode ---
# Enable with: STATUSLINE_DEBUG=1 ~/.claude/scripts/statusline.sh
# Output goes to stderr so it doesn't interfere with statusline output

DEBUG="${STATUSLINE_DEBUG:-0}"

debug() {
    [[ "${DEBUG}" != "1" ]] && return
    printf "[DEBUG] %s\n" "$*" >&2
}

debug_var() {
    [[ "${DEBUG}" != "1" ]] && return
    local name="$1"
    local value="$2"
    printf "[DEBUG]   %s = %s\n" "${name}" "${value}" >&2
}

# --- Constants ---

readonly API_URL="https://api.anthropic.com/api/oauth/usage"
readonly KEYCHAIN_SERVICE="Claude Code-credentials"
readonly API_BETA_HEADER="oauth-2025-04-20"
readonly CURL_TIMEOUT=10
readonly DEFAULT_TERM_WIDTH=120
readonly WIDE_THRESHOLD=110
# Use TMPDIR if set (cross-platform), otherwise /tmp (Unix) or $TEMP (Windows)
readonly _TMP_DIR="${TMPDIR:-${TEMP:-/tmp}}/claude-statusline-${UID:-$(id -u 2>/dev/null || echo $$)}"
# Keyed by Claude account, so profiles in their own CLAUDE_CONFIG_DIR never
# show each other's usage. Not readonly: each provider scopes its own copy.
_ACCOUNT_SUFFIX=""
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    _ACCOUNT_SUFFIX="$(printf '%s' "${CLAUDE_CONFIG_DIR}" | cksum)"
    _ACCOUNT_SUFFIX="-${_ACCOUNT_SUFFIX%% *}"
fi
# Readings live in the state directory, so a weekly window survives a reboot
# followed by a failed fetch. Locks and backoff stay in the temp directory.
_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code/statusline"
CACHE_FILE="${_STATE_DIR}/api-cache${_ACCOUNT_SUFFIX}"
CACHE_TTL=180 # The usage endpoint throttles hard; one call per 3 minutes per account
LOCK_DIR="${_TMP_DIR}/api-lock${_ACCOUNT_SUFFIX}"
readonly LOCK_MAX_AGE_S=30 # Force-remove stale locks from killed processes
BACKOFF_FILE="${_TMP_DIR}/api-backoff${_ACCOUNT_SUFFIX}"
readonly USAGE_STALE_S=900    # Older readings are marked with ~
readonly BACKOFF_INITIAL_S=30 # First backoff after 429/failure
readonly BACKOFF_MAX_S=300    # Cap at 5 minutes
readonly CONF_FILE="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/statusline.conf"
readonly CONF_DROPIN_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/statusline.d"
readonly CONF_LOCAL_FILE="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/statusline.local.conf"

# --- Config Globals (overridden by load_config) ---

CONF_THEME="dark"
CONF_COMPONENTS="model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email"
CONF_BAR_STYLE="text"
CONF_BAR_PCT_INSIDE="false"
CONF_COMPACT="true"                # Compact mode: no verbose prefixes, tokens merged with /, burn_rate hidden
CONF_COLOR_SCOPE="percentage"      # "percentage" = color usage component only, "full" = color entire line
CONF_ICON=""                       # Prefix icon: e.g. "✻", "A\\", "❋", or "" for none
CONF_ICON_CLAUDE=""                # Per plan, over icon: "A\\" for Claude, and the
CONF_ICON_OPENAI=""                # Nerd Font glyphs U+EC81 (OpenAI) and U+F06E4 (Muse);
CONF_ICON_MUSE=""                  # "֍" and "∞" need no Nerd Font
CONF_HOST_ICON=""                  # Before the host name, for example a Nerd Font OS logo
CONF_ICON_STYLE="plain"            # plain|bold|bracketed|rounded|reverse|bold-color|angle|double-bracket
CONF_WEEKLY_SHOW_RESET="false"     # Show weekly reset countdown inline with weekly %
CONF_CC_STATUS_POSITION="inline"   # inline | newline
CONF_CC_STATUS_VISIBILITY="always" # always | problem_only
CONF_CC_STATUS_COLOR="full"        # none | full | status_only

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
DATA_WEEKLY_PCT_STALE=0
DATA_USAGE_PROVIDER="claude"
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
DATA_CC_STATUS=""

# --- Width Flag ---

IS_WIDE="false"

# --- Platform Detection ---

# From bash's own OSTYPE, so no process; uname only where it is unset. Prints
# the platform and leaves it in REPLY.
detect_platform() {
    local os="${OSTYPE:-}"
    [[ -n "${os}" ]] || os="$(uname -s)"
    case "${os}" in
        darwin* | Darwin) REPLY="macos" ;;
        linux* | Linux) REPLY="linux" ;;
        msys* | cygwin* | win* | MSYS* | MINGW* | CYGWIN* | *_NT*) REPLY="windows" ;;
        *) REPLY="unknown" ;;
    esac
    echo "${REPLY}"
}

detect_platform >/dev/null
PLATFORM="${REPLY}"

# jq past mise's shim, which starts mise on every call at many times the cost of
# jq itself. Without a jq of its own on PATH, mise's installed one serves.
_resolve_jq() {
    local dir found="" IFS=:
    for dir in ${PATH}; do
        [[ "${dir}" == */mise/shims ]] && continue
        [[ -x "${dir}/jq" ]] && found="${dir}/jq" && break
    done
    if [[ -z "${found}" ]]; then
        for dir in "${MISE_DATA_DIR:-${HOME}/.local/share/mise}"/installs/jq/*/jq \
            "${MISE_DATA_DIR:-${HOME}/.local/share/mise}"/installs/jq/*/bin/jq; do
            [[ -x "${dir}" ]] && found="${dir}"
        done
    fi
    [[ -n "${found}" ]] || return 0
    _JQ="${found}"
    jq() { "${_JQ}" "$@"; }
}
_resolve_jq
readonly PLATFORM

# --- Source Modules ---

_STATUSLINE_DIR="${BASH_SOURCE[0]%/*}"
[[ "${BASH_SOURCE[0]}" == */* ]] || _STATUSLINE_DIR="."
source "${_STATUSLINE_DIR}/lib/statusline/config.sh"
source "${_STATUSLINE_DIR}/lib/statusline/utils.sh"
source "${_STATUSLINE_DIR}/lib/statusline/api.sh"
source "${_STATUSLINE_DIR}/lib/statusline/cache.sh"
source "${_STATUSLINE_DIR}/lib/statusline/providers.sh"
source "${_STATUSLINE_DIR}/lib/statusline/data.sh"
source "${_STATUSLINE_DIR}/lib/statusline/bar.sh"
source "${_STATUSLINE_DIR}/lib/statusline/color.sh"
source "${_STATUSLINE_DIR}/lib/statusline/style.sh"
source "${_STATUSLINE_DIR}/lib/statusline/status.sh"
source "${_STATUSLINE_DIR}/lib/statusline/components.sh"
source "${_STATUSLINE_DIR}/lib/statusline/assembly.sh"

# --- Main ---

main() {
    # Ensure user-specific tmp dir exists (prevents /tmp symlink attacks)
    [[ ! -d "${_TMP_DIR}" ]] && mkdir -p "${_TMP_DIR}" 2>/dev/null
    [[ -d "${_STATE_DIR}" ]] || mkdir -p "${_STATE_DIR}" 2>/dev/null || CACHE_FILE="${_TMP_DIR}/api-cache${_ACCOUNT_SUFFIX}"
    epoch_now

    load_config
    load_theme

    # Read Claude's JSON input from stdin
    local input="" term_width
    IFS= read -r -d '' input || true
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

    # The icon of the plan behind the model, when one is set, over the default
    case "${DATA_USAGE_PROVIDER}" in
        claude) CONF_ICON="${CONF_ICON_CLAUDE:-${CONF_ICON}}" ;;
        openai) CONF_ICON="${CONF_ICON_OPENAI:-${CONF_ICON}}" ;;
        muse) CONF_ICON="${CONF_ICON_MUSE:-${CONF_ICON}}" ;;
    esac

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
        if [[ "${max_pct}" == "--" || -z "${max_pct}" ]]; then
            max_pct="${DATA_WEEKLY_PCT}"
        elif [[ "${DATA_WEEKLY_PCT}" =~ ^[0-9]+$ && "${DATA_WEEKLY_PCT}" -gt "${max_pct}" ]]; then
            max_pct="${DATA_WEEKLY_PCT}"
        fi
        color=$(get_color_for_pct "${max_pct}")
        if [[ -n "${color}" ]]; then
            # A styled icon or component resets; the line color resumes after it.
            local line="${icon_prefix}${output}"
            printf "%s%s%s" "${color}" "${line//"${COLOR_RESET}"/${COLOR_RESET}${color}}" "${COLOR_RESET}"
        else
            printf "%s%s" "${icon_prefix}" "${output}"
        fi
    else
        printf "%s%s" "${icon_prefix}" "${output}"
    fi

    # Shown whatever the components: a lost prompt cache costs the plan quota.
    local warning
    warning=$(router_health_warning)
    [[ -n ${warning} ]] && printf ' %s%s%s' $'\033[0;31m' "${warning}" $'\033[0m'

    # Newline mode: emit cc_status as a second line
    if [[ ",${CONF_COMPONENTS}," == *",cc_status,"* &&
        "${CONF_CC_STATUS_POSITION}" == "newline" &&
        -n "${DATA_CC_STATUS}" ]]; then

        # problem_only: skip when operational
        if [[ "${CONF_CC_STATUS_VISIBILITY}" == "problem_only" &&
            "${DATA_CC_STATUS}" == "on" ]]; then
            : # no second line
        else
            local cc_label="${DATA_CC_STATUS}"
            local cc_color=""

            if [[ "${CONF_CC_STATUS_COLOR}" != "none" ]]; then
                cc_color=$(get_cc_status_color "${cc_label}")
            fi

            printf "\n"
            if [[ "${CONF_CC_STATUS_COLOR}" == "full" && -n "${cc_color}" ]]; then
                # Color both prefix and label
                printf "%scc status %s%s" "${cc_color}" "${cc_label}" "${COLOR_RESET}"
            elif [[ "${CONF_CC_STATUS_COLOR}" == "status_only" && -n "${cc_color}" ]]; then
                # Color only the label
                printf "cc status %s%s%s" "${cc_color}" "${cc_label}" "${COLOR_RESET}"
            else
                # No color
                printf "cc status %s" "${cc_label}"
            fi
        fi
    fi
}

# Source guard: only run main() when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
