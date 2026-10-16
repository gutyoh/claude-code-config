# config.sh -- Config and theme loading
# Path: .claude/scripts/lib/statusline/config.sh
# Sourced by statusline.sh — do not execute directly.

# statusline.conf, then statusline.local.conf beside it. Profiles may share the
# first (claude-as links it into every home); the second is the profile's own,
# so a key there, such as style.email, differs per account.
load_config() {
    _load_conf_file "${CONF_FILE}" legacy
    _load_conf_file "${CONF_LOCAL_FILE}"
}

# Reads key=value pairs from $1. With $2 = legacy, a first line without '='
# is the old single-theme format.
_load_conf_file() {
    [[ -f "$1" ]] || return 0

    local first_line=""
    IFS= read -r first_line <"$1" 2>/dev/null || true
    first_line="${first_line//[[:space:]]/}"

    if [[ "${2:-}" == legacy && -n "${first_line}" && "${first_line}" != *"="* ]]; then
        CONF_THEME="${first_line}"
        return 0
    fi

    local key value
    while IFS='=' read -r key value || [[ -n "${key}" ]]; do
        # Skip empty lines and comments
        [[ -z "${key}" || "${key}" == \#* ]] && continue
        key="${key//[[:space:]]/}"
        # A style keeps its inner spaces, which separate its words.
        if [[ "${key}" =~ ^style\.([a-z0-9_]+)$ ]]; then
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            printf -v "CONF_STYLE_${BASH_REMATCH[1]}" '%s' "${value}"
            continue
        fi
        value="${value//[[:space:]]/}"
        case "${key}" in
            theme) CONF_THEME="${value}" ;;
            components) CONF_COMPONENTS="${value}" ;;
            router_health) CONF_ROUTER_HEALTH="${value}" ;;
            bar_style) CONF_BAR_STYLE="${value}" ;;
            bar_pct_inside) CONF_BAR_PCT_INSIDE="${value}" ;;
            compact) CONF_COMPACT="${value}" ;;
            color_scope) CONF_COLOR_SCOPE="${value}" ;;
            icon) CONF_ICON="${value}" ;;
            icon_claude) CONF_ICON_CLAUDE="${value}" ;;
            icon_openai) CONF_ICON_OPENAI="${value}" ;;
            icon_muse) CONF_ICON_MUSE="${value}" ;;
            icon_style) CONF_ICON_STYLE="${value}" ;;
            weekly_show_reset) CONF_WEEKLY_SHOW_RESET="${value}" ;;
            cc_status_position) CONF_CC_STATUS_POSITION="${value}" ;;
            cc_status_visibility) CONF_CC_STATUS_VISIBILITY="${value}" ;;
            cc_status_color) CONF_CC_STATUS_COLOR="${value}" ;;
        esac
    done <"$1"
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
