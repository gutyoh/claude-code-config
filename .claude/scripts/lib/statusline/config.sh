# config.sh -- Config and theme loading
# Path: .claude/scripts/lib/statusline/config.sh
# Sourced by statusline.sh — do not execute directly.

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
            theme) CONF_THEME="${value}" ;;
            components) CONF_COMPONENTS="${value}" ;;
            bar_style) CONF_BAR_STYLE="${value}" ;;
            bar_pct_inside) CONF_BAR_PCT_INSIDE="${value}" ;;
            compact) CONF_COMPACT="${value}" ;;
            color_scope) CONF_COLOR_SCOPE="${value}" ;;
            icon) CONF_ICON="${value}" ;;
            icon_style) CONF_ICON_STYLE="${value}" ;;
            weekly_show_reset) CONF_WEEKLY_SHOW_RESET="${value}" ;;
            cc_status_position) CONF_CC_STATUS_POSITION="${value}" ;;
            cc_status_visibility) CONF_CC_STATUS_VISIBILITY="${value}" ;;
            cc_status_color) CONF_CC_STATUS_COLOR="${value}" ;;
        esac
    done <"${CONF_FILE}"
}

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
            COLOR_OK=$'\033[0;34m'       # blue
            COLOR_CAUTION=$'\033[0;33m'  # yellow
            COLOR_WARN=$'\033[38;5;208m' # orange (256-color)
            COLOR_CRIT=$'\033[0;31m'     # red
            COLOR_RESET=$'\033[0m'
            ;;
        light)
            COLOR_OK=$'\033[0;34m'       # blue
            COLOR_CAUTION=$'\033[0;33m'  # yellow
            COLOR_WARN=$'\033[38;5;208m' # orange (256-color)
            COLOR_CRIT=$'\033[0;31m'     # red
            COLOR_RESET=$'\033[0m'
            ;;
        colorblind)
            COLOR_OK=$'\033[1;34m'      # bold blue
            COLOR_CAUTION=$'\033[1;33m' # bold yellow
            COLOR_WARN=$'\033[1;36m'    # bold cyan
            COLOR_CRIT=$'\033[1;35m'    # bold magenta
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
