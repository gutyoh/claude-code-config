# data.sh -- time formatting and data collection
# Path: .claude/scripts/lib/statusline/data.sh
# Sourced by statusline.sh — do not execute directly.
#
# Usage data follows the session's model (providers.sh). For Claude models,
# one reading per account, merged from every session's:
#   - Stdin JSON: rate_limits.five_hour / seven_day, when Claude Code sends them
#   - OAuth API:  /api/oauth/usage, cached and shared, with stale-while-error
# and, only when the account has no reading at all, the hook cache (5-hour).

calculate_time_remaining() {
    local resets_at="$1"
    [[ -z "${resets_at}" ]] && echo "--" && return

    local reset_epoch now_epoch remaining_seconds hours mins

    reset_epoch=$(iso8601_to_epoch "${resets_at}") || {
        echo "--"
        return
    }
    epoch_now
    now_epoch="${_NOW}"
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
    epoch_now
    now_epoch="${_NOW}"
    remaining_seconds=$((reset_epoch - now_epoch))

    if [[ "${remaining_seconds}" -le 0 ]]; then
        echo "0h0m"
        return
    fi

    hours=$((remaining_seconds / 3600))
    mins=$(((remaining_seconds % 3600) / 60))
    echo "${hours}h${mins}m"
}

# Splits a tab-separated line into TABS, keeping empty fields, which `read`
# would merge since a tab is IFS whitespace.
_split_tabs() {
    local rest="$1" tab=$'\t'
    TABS=()
    while [[ "${rest}" == *"${tab}"* ]]; do
        TABS+=("${rest%%"${tab}"*}")
        rest="${rest#*"${tab}"}"
    done
    TABS+=("${rest}")
}

# Field <n> of a tab-separated line, empty when the line has fewer fields.
_tab_field() {
    _split_tabs "${2%%$'\n'*}"
    printf '%s' "${TABS[$(($1 - 1))]:-}"
}

# Rounded percentage, or -- for anything that is not a number, printed and in
# REPLY: Claude Code and the usage APIs send decimals, and truncating showed one
# point low.
_usage_pct() {
    [[ "$1" =~ ^([0-9]+)(\.([0-9]))?[0-9]*$ ]] || {
        REPLY="--"
        printf '%s' "${REPLY}"
        return
    }
    local whole=$((10#${BASH_REMATCH[1]}))
    ((${BASH_REMATCH[3]:-0} >= 5)) && whole=$((whole + 1))
    REPLY="${whole}"
    printf '%s' "${REPLY}"
}

# --- Claude: one reading per account ------------------------------------------
#
# Claude Code sends each session the rate limits of its own last response, so a
# quiet session falls behind while others spend the same account. Every render
# merges what it sees (its stdin and the shared OAuth reading) into one file per
# account and shows that file. A later reset is a newer window; within one
# window the latest reading wins, since a plan change moves it either way.
#
# A window is "pct|reset|seen", epoch seconds; "||" when unknown.

_CL_FIVE="||"
_CL_WEEK="||"

# Prints the account's reading file and leaves it in REPLY.
claude_account_file() {
    usage_state_dir >/dev/null
    REPLY="${REPLY}/claude${_ACCOUNT_SUFFIX:-}"
    printf '%s' "${REPLY}"
}

# The newer of two readings of one window, in REPLY (_newer_window prints it). Only a window that has not
# reset is current, so while both are the one seen last wins, whatever reset it
# names: a reset a plan change moved, or a wrong one, cannot hold the figure.
_merge_window() {
    local p1 r1 s1 p2 r2 s2 now num='^[0-9]+$'
    IFS='|' read -r p1 r1 s1 <<<"$1"
    IFS='|' read -r p2 r2 s2 <<<"$2"
    if ! [[ "${p2}" =~ ${num} && "${r2}" =~ ${num} && "${s2}" =~ ${num} ]]; then
        REPLY="$1"
        return
    elif ! [[ "${p1}" =~ ${num} && "${r1}" =~ ${num} && "${s1}" =~ ${num} ]]; then
        REPLY="$2"
        return
    fi
    epoch_now
    now="${_NOW}"
    local live1=$((r1 > now)) live2=$((r2 > now))
    if ((live1 != live2)); then
        ((live2)) && REPLY="$2" || REPLY="$1"
    elif ((!live1 && r1 != r2)); then
        ((r2 > r1)) && REPLY="$2" || REPLY="$1"
    elif ((s2 > s1 || (s2 == s1 && p2 > p1))); then
        REPLY="$2"
    else
        REPLY="$1"
    fi
}

_newer_window() {
    _merge_window "$@"
    printf '%s' "${REPLY}"
}

# claude_observe <five_pct> <five_reset> <week_pct> <week_reset> <seen>
# An unknown reset counts as 0, so any reading with a reset replaces it.
claude_observe() {
    local five week
    _usage_pct "$1" >/dev/null
    five="${REPLY}"
    _usage_pct "$3" >/dev/null
    week="${REPLY}"
    if [[ "${five}" != "--" ]]; then
        _merge_window "${_CL_FIVE}" "${five}|${2:-0}|$5"
        _CL_FIVE="${REPLY}"
    fi
    if [[ "${week}" != "--" ]]; then
        _merge_window "${_CL_WEEK}" "${week}|${4:-0}|$5"
        _CL_WEEK="${REPLY}"
    fi
    return 0
}

_claude_read_shared() {
    local line=""
    [[ -f "$1" ]] || return 0
    IFS= read -r line <"$1" || true
    _claude_merge_line "${line}"
}

# Merges one account-file line, "five<TAB>week", into this render's readings.
_claude_merge_line() {
    local five="${1%%$'\t'*}" week=""
    [[ "$1" == *$'\t'* ]] && week="${1#*$'\t'}"
    _merge_window "${_CL_FIVE}" "${five}"
    _CL_FIVE="${REPLY}"
    _merge_window "${_CL_WEEK}" "${week}"
    _CL_WEEK="${REPLY}"
}

# Whether every window was seen within CACHE_TTL: responses then keep the
# account current, and the throttled OAuth endpoint has nothing newer.
claude_fresh() {
    local window pct reset seen now
    epoch_now
    now="${_NOW}"
    for window in "${_CL_FIVE}" "${_CL_WEEK}"; do
        IFS='|' read -r pct reset seen <<<"${window}"
        [[ "${seen}" =~ ^[0-9]+$ ]] && ((now - seen < CACHE_TTL)) || return 1
    done
}

# Merges this render's readings with the account file and writes the result
# back. A lock held by another render skips the write, never the read; a lock
# left by a killed render is reclaimed after a few seconds.
claude_share() {
    local file lock age before=""
    claude_account_file >/dev/null
    file="${REPLY}"
    [[ -f "${file}" ]] && { IFS= read -r before <"${file}" || true; }
    _claude_merge_line "${before}"
    # Nothing newer than the file: most renders, so no lock and no write.
    [[ "${_CL_FIVE}"$'\t'"${_CL_WEEK}" == "${before}" ]] && return 0
    [[ -d "${file%/*}" ]] || mkdir -p "${file%/*}" 2>/dev/null || return 0
    lock="${_TMP_DIR:-${TMPDIR:-/tmp}}/claude-account${_ACCOUNT_SUFFIX:-}.lock"
    if [[ -d "${lock}" ]]; then
        age=$(get_file_age "${lock}" 2>/dev/null) || age=0
        ((age > 10)) && rmdir "${lock}" 2>/dev/null
    fi
    if ! mkdir "${lock}" 2>/dev/null; then
        _claude_read_shared "${file}"
        return 0
    fi
    _claude_read_shared "${file}"
    printf '%s\t%s\n' "${_CL_FIVE}" "${_CL_WEEK}" >"${file}.tmp.$$" 2>/dev/null \
        && mv -f "${file}.tmp.$$" "${file}" 2>/dev/null
    rmdir "${lock}" 2>/dev/null
    return 0
}

# Shows the account reading; fails when no window is known.
apply_claude_account() {
    local pct reset seen now shown=1
    epoch_now
    now="${_NOW}"
    IFS='|' read -r pct reset seen <<<"${_CL_FIVE}"
    if [[ "${pct}" =~ ^[0-9]+$ ]]; then
        DATA_SESSION_PCT="${pct}"
        DATA_TIME_LEFT=$(calculate_time_remaining_epoch "${reset}")
        ((now - seen > ${USAGE_STALE_S:-900})) && DATA_SESSION_PCT_STALE=1
        shown=0
    fi
    IFS='|' read -r pct reset seen <<<"${_CL_WEEK}"
    if [[ "${pct}" =~ ^[0-9]+$ ]]; then
        DATA_WEEKLY_PCT="${pct}"
        DATA_WEEKLY_TIME_LEFT=$(calculate_time_remaining_epoch "${reset}")
        ((now - seen > ${USAGE_STALE_S:-900})) && DATA_WEEKLY_PCT_STALE=1
        shown=0
    fi
    return "${shown}"
}

# Every stdin field a render reads, from one jq into IN_*: a process per field
# was most of the render's cost, and processes are slow under Git Bash.
parse_input() {
    local line sep=$'\x1f'
    line=$(jq -r '[(.model.display_name // "claude" | sub("Claude "; "")
            | ascii_downcase | gsub(" "; "-")),
        .model.id, .version, .cost.total_lines_added, .cost.total_lines_removed,
        .cost.total_duration_ms, .cwd, .session_id, .transcript_path,
        .rate_limits.five_hour.used_percentage, .rate_limits.five_hour.resets_at,
        .rate_limits.seven_day.used_percentage, .rate_limits.seven_day.resets_at,
        .cost.total_cost_usd, .context_window.total_input_tokens,
        .context_window.total_output_tokens, .context_window.current_usage.cache_read_input_tokens]
        | map(if . == null then "" else tostring | gsub("[\u001f\n]"; " ") end)
        | join("\u001f")' <<<"$1" 2>/dev/null) || line=""
    IFS="${sep}" read -r IN_MODEL IN_MODEL_ID IN_VERSION IN_LINES_ADDED IN_LINES_REMOVED \
        IN_DURATION_MS IN_CWD IN_SESSION IN_TRANSCRIPT \
        IN_FIVE IN_FIVE_RESET IN_WEEK IN_WEEK_RESET \
        IN_COST IN_CTX_IN IN_CTX_OUT IN_CACHE_READ <<<"${line}" || true
    IN_MODEL="${IN_MODEL:-claude}"
}

# Tokens, cost and burn rate for the token and cost components, from stdin:
#   tokens_in/out  context_window.total_input/output_tokens (the live context;
#                  input includes cache reads and writes)
#   tokens_cache   context_window.current_usage.cache_read_input_tokens
#   cost           cost.total_cost_usd, the session's list-price estimate
#   burn_rate      that cost per hour of session time, once a minute has passed
# A field Claude Code has not sent yet (before the first response, after
# /compact) reads as 0. Non-numeric input never reaches printf.
session_figures() {
    local n v
    for n in IN_CTX_IN IN_CTX_OUT IN_CACHE_READ; do
        v="${!n:-}"
        [[ "${v}" =~ ^[0-9]+$ ]] || v=0
        printf -v "${n}" '%s' "${v}"
    done
    DATA_INPUT_TOKENS="${IN_CTX_IN}"
    DATA_OUTPUT_TOKENS="${IN_CTX_OUT}"
    DATA_CACHE_READ="${IN_CACHE_READ}"
    if [[ "${IN_COST:-}" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]]; then
        DATA_COST_USD="${IN_COST}"
    fi
    if [[ "${IN_DURATION_MS:-}" =~ ^[0-9]+$ ]] && ((IN_DURATION_MS >= 60000)); then
        DATA_BURN_RATE=$(awk -v c="${DATA_COST_USD}" -v ms="${IN_DURATION_MS}" 'BEGIN {printf "%.4f", c / (ms / 3600000)}')
    fi
    return 0
}

# The rate_limits Claude Code passes on stdin, once a session has had a
# response (documented for Pro and Max plans); each window may be absent.
get_native_usage_data() {
    [[ -n "${IN_FIVE}${IN_WEEK}" ]] || return 1
    _native_seen
    claude_observe "${IN_FIVE}" "${IN_FIVE_RESET}" "${IN_WEEK}" "${IN_WEEK_RESET}" "${REPLY}"
}

# When the session last heard from the API, in REPLY: Claude Code repeats its
# last rate_limits on every render, so they are as old as the transcript.
_native_seen() {
    local age
    epoch_now
    REPLY="${_NOW}"
    if [[ -n "${IN_TRANSCRIPT}" ]] && age=$(get_file_age "${IN_TRANSCRIPT}") && ((age > 0)); then
        REPLY=$((_NOW - age))
    fi
}

# A GPT or Muse plan's windows (providers.sh). A window the plan does not have
# is emptied, so its component is hidden.
get_provider_usage_data() {
    local line
    line=$(get_provider_usage "$1") || return 1
    [[ -z "${line}" ]] && return 1

    local five five_reset week week_reset fetched_at week_seen
    _split_tabs "${line%%$'\n'*}"
    five="${TABS[0]:-}" five_reset="${TABS[1]:-}" week="${TABS[2]:-}"
    week_reset="${TABS[3]:-}" fetched_at="${TABS[4]:-}" week_seen="${TABS[5]:-}"

    DATA_SESSION_PCT=""
    DATA_TIME_LEFT=""
    if [[ -n "${five}" ]]; then
        DATA_SESSION_PCT=$(_usage_pct "${five}")
        # An idle window has no reset to count down to
        [[ -n "${five_reset}" ]] && DATA_TIME_LEFT=$(calculate_time_remaining_epoch "${five_reset}")
    fi
    DATA_WEEKLY_PCT=""
    DATA_WEEKLY_TIME_LEFT="--"
    if [[ -n "${week}" ]]; then
        DATA_WEEKLY_PCT=$(_usage_pct "${week}")
        DATA_WEEKLY_TIME_LEFT=$(calculate_time_remaining_epoch "${week_reset}")
    fi
    # Each window is approximate once its own reading is old: a weekly window
    # carried through an idle stretch can be older than the fetch serving it.
    local now
    epoch_now
    now="${_NOW}"
    [[ "${week_seen}" =~ ^[0-9]+$ ]] || week_seen="${fetched_at}"
    if [[ "${fetched_at}" =~ ^[0-9]+$ ]] && ((now - fetched_at > ${USAGE_STALE_S:-900})); then
        DATA_SESSION_PCT_STALE=1
    fi
    if [[ "${week_seen}" =~ ^[0-9]+$ ]] && ((now - week_seen > ${USAGE_STALE_S:-900})); then
        DATA_WEEKLY_PCT_STALE=1
    fi
    return 0
}

# Last resort: the hook cache (PreToolUse Haiku ping headers), 5-hour only
# Staleness: if cache is older than HOOK_STALE_THRESHOLD (default 300s = 5 min),
# prefix percentage with ~ to indicate approximate/stale data.
HOOK_STALE_THRESHOLD="${HOOK_STALE_THRESHOLD:-300}"

get_hook_usage_data() {
    local cache_file="${HOOK_USAGE_CACHE:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/cache/claude-usage.json}"
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
        epoch_now
        cache_age=$((_NOW - mtime))
    fi

    DATA_SESSION_PCT="${pct}"
    if [[ ${cache_age} -gt ${HOOK_STALE_THRESHOLD} ]]; then
        DATA_SESSION_PCT_STALE=1
    fi
    DATA_TIME_LEFT=$(calculate_time_remaining_epoch "${reset_epoch}")
    return 0
}

# An ISO 8601 reset as epoch seconds, 0 when absent or unreadable (`date`
# reads an empty string as today's midnight).
_reset_epoch() {
    [[ -n "$1" ]] && iso8601_to_epoch "$1" 2>/dev/null || echo 0
}

# The account's OAuth usage reading, shared by every session through its cache;
# seen when it was fetched.
get_oauth_usage_data() {
    local api_data="" cache_age five_reset week_reset
    api_data=$(get_cached_api_data) || return 1
    [[ -z "${api_data}" ]] && return 1
    # shellcheck disable=SC2153 # CACHE_FILE is set by statusline.sh
    cache_age=$(get_file_age "${CACHE_FILE}" 2>/dev/null) || cache_age=0
    _split_tabs "${api_data}"
    local five="${TABS[0]:-}" five_iso="${TABS[1]:-}" week="${TABS[2]:-}" week_iso="${TABS[3]:-}"
    five_reset=$(_reset_epoch "${five_iso}")
    week_reset=$(_reset_epoch "${week_iso}")
    epoch_now
    claude_observe "${five}" "${five_reset}" "${week}" "${week_reset}" "$((_NOW - cache_age))"
}

# Records each session's current model for hooks/session-name.sh, which cannot
# see a /model switch itself. The statusline runs often, so it writes only on
# a change. A render passes nothing (parse_input ran); a caller may pass stdin.
# shellcheck disable=SC2120
record_session_model() {
    local session model dir file recorded=""
    [[ "${CLAUDE_SESSION_NAME:-}" == "off" ]] && return 0
    [[ $# -eq 0 ]] || parse_input "$1"
    session="${IN_SESSION}"
    model="${IN_MODEL_ID}"
    [[ "${session}" =~ ^[A-Za-z0-9-]+$ && -n "${model}" ]] || return 0

    dir="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code/session-names"
    file="${dir}/${session}.model"
    [[ -f "${file}" ]] && IFS= read -r recorded <"${file}"
    [[ "${recorded}" == "${model}" ]] && return 0
    mkdir -p "${dir}" 2>/dev/null || return 0
    printf '%s\n' "${model}" >"${file}.$$" && mv -f "${file}.$$" "${file}"
    return 0
}

collect_data() {
    local input="$1"

    debug "=== Data Collection Start ==="
    debug "Platform: ${PLATFORM}"
    debug "Tmp dir: ${_TMP_DIR}"

    epoch_now
    parse_input "${input}"
    record_session_model

    # "Claude Opus 5.5" shows as "opus-5.5"
    DATA_MODEL="${IN_MODEL}"
    debug_var "DATA_MODEL" "${DATA_MODEL}"
    DATA_VERSION="${IN_VERSION}"
    DATA_LINES_ADDED="${IN_LINES_ADDED}"
    DATA_LINES_REMOVED="${IN_LINES_REMOVED}"
    DATA_SESSION_TIME_MS="${IN_DURATION_MS}"
    DATA_CWD="${IN_CWD}"

    # Account email. `|| true` because jq exits non-zero when .claude.json is
    # missing — which is the normal state on a fresh install — and a bare
    # assignment would abort any caller running under `set -e`. Claude Code keeps
    # that file inside CLAUDE_CONFIG_DIR when set, beside ~/.claude otherwise; the
    # default home named explicitly still has its account beside it.
    local claude_json="${HOME}/.claude.json" dir="${CLAUDE_CONFIG_DIR:-}"
    while [[ "${dir}" == */ ]]; do dir="${dir%/}"; done
    if [[ -n "${dir}" ]]; then
        claude_json="${dir}/.claude.json"
        [[ -f "${claude_json}" || "${dir}" != "${HOME}/.claude" ]] || claude_json="${HOME}/.claude.json"
    fi
    DATA_EMAIL=$(jq -r '.oauthAccount.emailAddress // empty' "${claude_json}" 2>/dev/null || true)
    DATA_EMAIL="${DATA_EMAIL:-N/A}"
    debug_var "DATA_EMAIL" "${DATA_EMAIL}"

    # Claude Code service health status (cached, non-blocking)
    collect_service_status

    # Usage data: the plan behind the session's model
    local model_id="${IN_MODEL_ID}"
    DATA_USAGE_PROVIDER=$(usage_provider "${model_id}")
    debug "--- Usage Data (${DATA_USAGE_PROVIDER}) ---"
    case "${DATA_USAGE_PROVIDER}" in
        claude)
            _CL_FIVE="||"
            _CL_WEEK="||"
            get_native_usage_data && debug "Observed: native stdin JSON (rate_limits)"
            claude_account_file >/dev/null
            _claude_read_shared "${REPLY}"
            if claude_fresh; then
                debug "Skipped: OAuth API, every window was seen within ${CACHE_TTL}s"
            elif get_oauth_usage_data; then
                debug "Observed: OAuth API (/api/oauth/usage)"
            fi
            claude_share
            if apply_claude_account; then
                debug "Source: account reading (${_CL_FIVE} / ${_CL_WEEK})"
            elif get_hook_usage_data; then
                debug "Source: hook cache (claude-usage.json)"
            else
                debug "Source: NONE - all data sources failed"
            fi
            ;;
        openai | muse)
            get_provider_usage_data "${DATA_USAGE_PROVIDER}" \
                || debug "Source: NONE - ${DATA_USAGE_PROVIDER} usage unavailable"
            ;;
        *)
            debug "Source: NONE - no usage reader for model ${model_id}"
            ;;
    esac
    debug_var "DATA_SESSION_PCT" "${DATA_SESSION_PCT}"
    debug_var "DATA_WEEKLY_PCT" "${DATA_WEEKLY_PCT}"
    debug_var "DATA_TIME_LEFT" "${DATA_TIME_LEFT}"

    # Tokens and cost: this session's own figures, which Claude Code sends on
    # stdin. No process and no transcript scan; the plan's real usage is the
    # usage/weekly bars above. cost.total_cost_usd is a list-price estimate.
    debug "--- Session tokens and cost (stdin) ---"
    session_figures
    debug_var "DATA_INPUT_TOKENS" "${DATA_INPUT_TOKENS}"
    debug_var "DATA_OUTPUT_TOKENS" "${DATA_OUTPUT_TOKENS}"
    debug_var "DATA_COST_USD" "${DATA_COST_USD}"

    debug "=== Data Collection End ==="
}
