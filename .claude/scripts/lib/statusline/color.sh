# color.sh -- Utilization color helpers
# Path: .claude/scripts/lib/statusline/color.sh
# Sourced by statusline.sh — do not execute directly.

# Severity level of a utilization percentage, in REPLY:
# 0 under 25%, 1 to 49%, 2 to 74%, 3 to 89%, 4 at 90% and above.
level_for_pct() {
    local pct="$1"
    if ((pct >= 90)); then REPLY=4
    elif ((pct >= 75)); then REPLY=3
    elif ((pct >= 50)); then REPLY=2
    elif ((pct >= 25)); then REPLY=1
    else REPLY=0; fi
}

# Returns the ANSI color code for a severity level (0-4).
get_color_for_level() {
    case "$1" in
        4) printf "%s" "${COLOR_CRIT}" ;;
        3) printf "%s" "${COLOR_WARN}" ;;
        2) printf "%s" "${COLOR_CAUTION}" ;;
        1) printf "%s" "${COLOR_OK}" ;;
        *) printf "%s" "${COLOR_IDLE}" ;;
    esac
}

# Returns the ANSI color code for a given utilization percentage.
# Usage: get_color_for_pct <pct>
get_color_for_pct() {
    local pct="$1"
    [[ "${pct}" =~ ^[0-9]+$ ]] || return
    level_for_pct "${pct}"
    get_color_for_level "${REPLY}"
}

# Returns the ANSI color code for the current session utilization level.
get_utilization_color() {
    get_color_for_pct "${DATA_SESSION_PCT}"
}

# Returns the ANSI color code for a Claude Code service status label.
# Usage: get_cc_status_color <label>
#   label: on, degraded, partial, outage, maintenance
get_cc_status_color() {
    case "$1" in
        degraded) printf "%s" "${COLOR_CAUTION}" ;;
        partial) printf "%s" "${COLOR_WARN}" ;;
        outage) printf "%s" "${COLOR_CRIT}" ;;
        maintenance) printf "%s" "${COLOR_CAUTION}" ;;
    esac
}
