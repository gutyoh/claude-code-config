# components.sh -- Individual component renderers
# Path: .claude/scripts/lib/statusline/components.sh
# Sourced by statusline.sh — do not execute directly.

render_component_model() {
    printf "%s" "${DATA_MODEL}"
}

render_component_usage() {
    local raw=""
    local display_pct="${DATA_SESSION_PCT}"
    # Prefix with ~ when data is stale (cache older than HOOK_STALE_THRESHOLD)
    if [[ "${DATA_SESSION_PCT_STALE}" == "1" && "${DATA_SESSION_PCT}" != "--" ]]; then
        display_pct="~${DATA_SESSION_PCT}"
    fi

    if [[ "${IS_WIDE}" == "true" ]]; then
        if [[ "${CONF_COMPACT}" == "true" && "${CONF_BAR_STYLE}" == "text" ]]; then
            raw=$(printf "%s%%" "${display_pct}")
        else
            # Pass numeric DATA_SESSION_PCT to bar renderer (not display_pct)
            raw=$(render_progress_bar "${DATA_SESSION_PCT}" "${CONF_BAR_STYLE}" 20 "${CONF_BAR_PCT_INSIDE}")
        fi
    else
        raw=$(printf "%s%%" "${display_pct}")
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
