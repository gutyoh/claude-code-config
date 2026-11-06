# forecast.sh -- Run-out forecast for the 5-hour and weekly windows
# Path: .claude/scripts/lib/statusline/forecast.sh
# Sourced by statusline.sh — do not execute directly.
#
# The usage-forecast mod writes FORECAST_FILE from its reading history (recent
# pace, idle-aware). Without a fresh file, the window's average pace is used.

FORECAST_FILE="${FORECAST_FILE:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/cache/usage-forecast.tsv}"
FORECAST_FRESH_S="${FORECAST_FRESH_S:-600}"
_FC_LOADED=0
_FC_MOD_FIVE=""
_FC_MOD_WEEK=""

# Reads the mod's forecast when the file is fresh: one line per window,
# "<kind>\t<resets_at epoch>\t<state>\t<seconds to full>". No subprocess.
_forecast_load_mod() {
    ((_FC_LOADED)) && return 0
    _FC_LOADED=1
    [[ -f "${FORECAST_FILE}" ]] || return 0
    local age kind reset state full
    age=$(get_file_age "${FORECAST_FILE}" 2>/dev/null) || return 0
    ((age > FORECAST_FRESH_S)) && return 0
    while IFS=$'\t' read -r kind reset state full; do
        case "${kind}" in
            five_hour) _FC_MOD_FIVE="${reset}|${state}|${full}" ;;
            seven_day) _FC_MOD_WEEK="${reset}|${state}|${full}" ;;
        esac
    done <"${FORECAST_FILE}"
}

# Short duration: 12m, 1h10m, 1d4h.
_fc_dur() {
    local m=$((($1 + 30) / 60)) h d
    if ((m < 60)); then
        REPLY="${m}m"
        return
    fi
    h=$((m / 60))
    if ((h < 24)); then
        ((m % 60)) && REPLY="${h}h$((m % 60))m" || REPLY="${h}h"
        return
    fi
    d=$((h / 24))
    ((h % 24)) && REPLY="${d}d$((h % 24))h" || REPLY="${d}d"
}

# forecast_window <five_hour|seven_day> <pct> <reset_epoch>
# Sets FC_SUFFIX ("⇥1h12m" when the window runs out before it resets, else
# empty) and FC_LEVEL (0, 3 when it runs out early, 4 when that is soon or
# the limit is reached).
forecast_window() {
    FC_SUFFIX="" FC_LEVEL=0
    local kind="$1" pct="$2" reset="$3"
    [[ "${pct}" =~ ^[0-9]+$ && "${reset}" =~ ^[0-9]+$ ]] || return 0
    if ((pct >= 100)); then
        FC_LEVEL=4
        return 0
    fi
    epoch_now
    local now="${_NOW}" left win urgent min_elapsed full=-1
    left=$((reset - now))
    ((left > 0)) || return 0
    if [[ "${kind}" == "five_hour" ]]; then
        win=18000 urgent=1800 min_elapsed=900
    else
        win=604800 urgent=43200 min_elapsed=21600
    fi

    _forecast_load_mod
    local mod m_reset m_state m_full
    [[ "${kind}" == "five_hour" ]] && mod="${_FC_MOD_FIVE}" || mod="${_FC_MOD_WEEK}"
    if [[ -n "${mod}" ]]; then
        IFS='|' read -r m_reset m_state m_full <<<"${mod}"
        # Same window (the service jitters resets_at by seconds)
        if [[ "${m_reset}" =~ ^[0-9]+$ ]] && ((m_reset - reset < 300 && reset - m_reset < 300)); then
            if [[ "${m_state}" == "hits" && "${m_full}" =~ ^[0-9]+$ ]]; then
                full="${m_full}"
            else
                full=-2 # the mod judged it: no run-out before the reset
            fi
        fi
    fi

    if ((full == -1)); then
        local elapsed=$((win - left))
        ((elapsed > 0 && pct > 0)) || return 0
        ((elapsed < min_elapsed && pct < 25)) && return 0
        full=$(((100 - pct) * elapsed / pct))
    fi
    ((full >= 0 && full < left)) || return 0
    _fc_dur "${full}"
    FC_SUFFIX="⇥${REPLY}"
    ((full <= urgent)) && FC_LEVEL=4 || FC_LEVEL=3
}

# Color for a window: the worse of its percentage and its forecast, in the
# window's own shade ("weekly" as the second argument).
forecast_color() {
    local pct="$1" shade="${2:-}"
    [[ "${pct}" =~ ^[0-9]+$ ]] || return
    level_for_pct "${pct}"
    ((FC_LEVEL > REPLY)) && REPLY="${FC_LEVEL}"
    get_color_for_level "${REPLY}" "${shade}"
}
