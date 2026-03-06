# color.sh -- Utilization color helpers
# Path: .claude/scripts/lib/statusline/color.sh
# Sourced by statusline.sh — do not execute directly.

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

# Returns the ANSI color code for a Claude Code service status label.
# Usage: get_cc_status_color <label>
#   label: on, degraded, partial, outage, maintenance
get_cc_status_color() {
    case "$1" in
        degraded)    printf "%s" "${COLOR_CAUTION}" ;;
        partial)     printf "%s" "${COLOR_WARN}" ;;
        outage)      printf "%s" "${COLOR_CRIT}" ;;
        maintenance) printf "%s" "${COLOR_CAUTION}" ;;
    esac
}
