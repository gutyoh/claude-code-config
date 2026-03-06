# statusline-conf.sh -- Statusline config file (statusline.conf) management
# Path: lib/setup/statusline-conf.sh
# Sourced by setup.sh — do not execute directly.

configure_statusline_conf() {
    local conf_file="${CLAUDE_DIR}/statusline.conf"
    local force="${1:-false}" # "true" when user explicitly customized via TUI

    if [[ -f "${conf_file}" ]]; then
        # In merge mode (force=false), preserve existing config — don't overwrite
        # user's customizations with defaults. Only overwrite when user explicitly
        # customized via the TUI (force=true) or used --overwrite-settings.
        if [[ "${force}" != "true" ]]; then
            echo "  ✓ Statusline config already exists (preserved)"
            return
        fi

        local matches="true"

        local cur_theme="" cur_components="" cur_bar_style="" cur_pct_inside="" cur_compact="" cur_color_scope="" cur_icon="" cur_icon_style="" cur_weekly_show_reset=""
        local cur_cc_status_position="" cur_cc_status_visibility="" cur_cc_status_color=""

        local first_line
        first_line=$(head -n1 "${conf_file}" 2>/dev/null | tr -d '[:space:]')

        if [[ -n "${first_line}" && "${first_line}" != *"="* ]]; then
            matches="false"
        else
            while IFS='=' read -r key value; do
                [[ -z "${key}" || "${key}" == \#* ]] && continue
                key=$(echo "${key}" | tr -d '[:space:]')
                # Don't strip spaces from value for icon (it could be "A\")
                value=$(echo "${value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                case "${key}" in
                    theme) cur_theme="${value}" ;;
                    components) cur_components="${value}" ;;
                    bar_style) cur_bar_style="${value}" ;;
                    bar_pct_inside) cur_pct_inside="${value}" ;;
                    compact) cur_compact="${value}" ;;
                    color_scope) cur_color_scope="${value}" ;;
                    icon) cur_icon="${value}" ;;
                    icon_style) cur_icon_style="${value}" ;;
                    weekly_show_reset) cur_weekly_show_reset="${value}" ;;
                    cc_status_position) cur_cc_status_position="${value}" ;;
                    cc_status_visibility) cur_cc_status_visibility="${value}" ;;
                    cc_status_color) cur_cc_status_color="${value}" ;;
                esac
            done <"${conf_file}"

            [[ "${cur_theme}" != "${STATUSLINE_THEME}" ]] && matches="false"
            [[ "${cur_components}" != "${STATUSLINE_COMPONENTS}" ]] && matches="false"
            [[ "${cur_bar_style}" != "${STATUSLINE_BAR_STYLE}" ]] && matches="false"
            [[ "${cur_pct_inside}" != "${STATUSLINE_BAR_PCT_INSIDE}" ]] && matches="false"
            [[ "${cur_compact}" != "${STATUSLINE_COMPACT}" ]] && matches="false"
            [[ "${cur_color_scope}" != "${STATUSLINE_COLOR_SCOPE}" ]] && matches="false"
            [[ "${cur_icon}" != "${STATUSLINE_ICON}" ]] && matches="false"
            [[ "${cur_icon_style}" != "${STATUSLINE_ICON_STYLE}" ]] && matches="false"
            [[ "${cur_weekly_show_reset}" != "${STATUSLINE_WEEKLY_SHOW_RESET}" ]] && matches="false"
            [[ "${cur_cc_status_position}" != "${STATUSLINE_CC_STATUS_POSITION}" ]] && matches="false"
            [[ "${cur_cc_status_visibility}" != "${STATUSLINE_CC_STATUS_VISIBILITY}" ]] && matches="false"
            [[ "${cur_cc_status_color}" != "${STATUSLINE_CC_STATUS_COLOR}" ]] && matches="false"
        fi

        if [[ "${matches}" == "true" ]]; then
            echo "  ✓ Statusline config already up to date"
            return
        fi
    fi

    cat >"${conf_file}" <<EOF
theme=${STATUSLINE_THEME}
components=${STATUSLINE_COMPONENTS}
bar_style=${STATUSLINE_BAR_STYLE}
bar_pct_inside=${STATUSLINE_BAR_PCT_INSIDE}
compact=${STATUSLINE_COMPACT}
color_scope=${STATUSLINE_COLOR_SCOPE}
icon=${STATUSLINE_ICON}
icon_style=${STATUSLINE_ICON_STYLE}
weekly_show_reset=${STATUSLINE_WEEKLY_SHOW_RESET}
cc_status_position=${STATUSLINE_CC_STATUS_POSITION}
cc_status_visibility=${STATUSLINE_CC_STATUS_VISIBILITY}
cc_status_color=${STATUSLINE_CC_STATUS_COLOR}
EOF
    echo "  ✓ Statusline config written (theme=${STATUSLINE_THEME}, bar=${STATUSLINE_BAR_STYLE})"
}
