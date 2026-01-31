# preview.sh -- Statusline preview rendering for setup TUI
# Path: lib/setup/preview.sh
# Sourced by setup.sh — do not execute directly.

_preview_overlay_pct() {
    # Overlay " NN% " at center of a bar string
    # Usage: _preview_overlay_pct BAR_VAR pct width
    local -n _pbar="$1"
    local pct="$2"
    local width="$3"
    local pstr=" ${pct}% "
    local plen=${#pstr}

    if [[ ${width} -ge $((plen + 2)) ]]; then
        local start=$(((width - plen) / 2))
        local after=$((start + plen))
        local new_bar="${_pbar:0:${start}}${pstr}${_pbar:${after}}"
        _pbar="${new_bar:0:${width}}"
    fi
}

render_bar_preview() {
    local style="$1"
    local pct_inside="$2"
    local pct=42
    local width=20

    case "${style}" in
        text)
            printf "session: %d%% used" ${pct}
            ;;
        block)
            local filled=$((pct * width / 100))
            local empty=$((width - filled))
            local bar=""
            for ((i = 0; i < filled; i++)); do bar+="█"; done
            for ((i = 0; i < empty; i++)); do bar+="·"; done
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "[%s]" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        smooth)
            local partials=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            local total_eighths=$((pct * width * 8 / 100))
            local full_blocks=$((total_eighths / 8))
            local remainder=$((total_eighths % 8))
            local has_partial=0
            [[ ${remainder} -gt 0 ]] && has_partial=1
            local empty_blocks=$((width - full_blocks - has_partial))
            local bar=""
            for ((i = 0; i < full_blocks; i++)); do bar+="█"; done
            [[ ${remainder} -gt 0 ]] && bar+="${partials[${remainder}]}"
            for ((i = 0; i < empty_blocks; i++)); do bar+="░"; done
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "%s" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        gradient)
            local filled=$((pct * width / 100))
            local empty=$((width - filled))
            local bar=""
            if [[ ${filled} -eq 0 ]]; then
                for ((i = 0; i < width; i++)); do bar+="░"; done
            elif [[ ${empty} -eq 0 ]]; then
                for ((i = 0; i < width; i++)); do bar+="█"; done
            else
                for ((i = 0; i < filled; i++)); do bar+="█"; done
                local remaining=$((empty))
                if [[ ${remaining} -ge 1 ]]; then
                    bar+="▓"
                    remaining=$((remaining - 1))
                fi
                if [[ ${remaining} -ge 1 ]]; then
                    bar+="▒"
                    remaining=$((remaining - 1))
                fi
                for ((i = 0; i < remaining; i++)); do bar+="░"; done
            fi
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "%s" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        thin)
            local filled=$((pct * width / 100))
            local empty=$((width - filled))
            local bar=""
            for ((i = 0; i < filled; i++)); do bar+="━"; done
            for ((i = 0; i < empty; i++)); do bar+="╌"; done
            [[ "${pct_inside}" == "true" ]] && _preview_overlay_pct bar ${pct} ${width}
            printf "%s" "${bar}"
            [[ "${pct_inside}" != "true" ]] && printf " %d%%" ${pct}
            ;;
        spark)
            local spark_chars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
            local sw=5
            local bar=""
            for ((i = 0; i < sw; i++)); do
                local seg_start=$((i * 100 / sw))
                local seg_end=$(((i + 1) * 100 / sw))
                if [[ ${pct} -ge ${seg_end} ]]; then
                    bar+="█"
                elif [[ ${pct} -le ${seg_start} ]]; then
                    bar+="▁"
                else
                    local seg_range=$((seg_end - seg_start))
                    local seg_fill=$((pct - seg_start))
                    local idx=$((seg_fill * 7 / seg_range))
                    ((idx > 7)) && idx=7
                    bar+="${spark_chars[${idx}]}"
                fi
            done
            printf "%s %d%%" "${bar}" ${pct}
            ;;
    esac
}

show_statusline_preview() {
    local is_compact="${STATUSLINE_COMPACT}"
    local bar_style="${STATUSLINE_BAR_STYLE}"
    local pct_inside="${STATUSLINE_BAR_PCT_INSIDE}"

    # In compact + text mode, usage is just plain percentage
    local usage_str
    if [[ "${is_compact}" == "true" && "${bar_style}" == "text" ]]; then
        usage_str="42%"
    else
        usage_str=$(render_bar_preview "${bar_style}" "${pct_inside}")
    fi

    # Icon prefix (styled)
    local icon_prefix=""
    if [[ -n "${STATUSLINE_ICON}" ]]; then
        case "${STATUSLINE_ICON_STYLE}" in
            bold) icon_prefix="${STATUSLINE_ICON} " ;;
            bracketed) icon_prefix="[${STATUSLINE_ICON}] " ;;
            rounded) icon_prefix="(${STATUSLINE_ICON}) " ;;
            reverse) icon_prefix=" ${STATUSLINE_ICON}  " ;;
            bold-color) icon_prefix="${STATUSLINE_ICON} " ;;
            angle) icon_prefix="⟨${STATUSLINE_ICON}⟩ " ;;
            double-bracket) icon_prefix="⟦${STATUSLINE_ICON}⟧ " ;;
            *) icon_prefix="${STATUSLINE_ICON} " ;;
        esac
    fi

    # Build wide-mode preview from components
    IFS=',' read -ra comp_arr <<<"${STATUSLINE_COMPONENTS}"

    local parts=()
    local part_keys=()

    for key in "${comp_arr[@]}"; do
        case "${key}" in
            model)
                parts+=("opus-4.5")
                part_keys+=("model")
                ;;
            usage)
                parts+=("${usage_str}")
                part_keys+=("usage")
                ;;
            weekly)
                if [[ "${is_compact}" == "true" ]]; then
                    local weekly_str="63%"
                else
                    local weekly_str="weekly: 63%"
                fi
                if [[ "${STATUSLINE_WEEKLY_SHOW_RESET}" == "true" ]]; then
                    weekly_str+=" (4d2h)"
                fi
                parts+=("${weekly_str}")
                part_keys+=("weekly")
                ;;
            reset)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("2h15m")
                else
                    parts+=("resets: 2h15m")
                fi
                part_keys+=("reset")
                ;;
            tokens_in)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("15.4k")
                else
                    parts+=("in: 15.4k")
                fi
                part_keys+=("tokens_in")
                ;;
            tokens_out)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("2.1k")
                else
                    parts+=("out: 2.1k")
                fi
                part_keys+=("tokens_out")
                ;;
            tokens_cache)
                if [[ "${is_compact}" == "true" ]]; then
                    parts+=("6.2M")
                else
                    parts+=("cache: 6.2M")
                fi
                part_keys+=("tokens_cache")
                ;;
            cost)
                parts+=("\$5.21")
                part_keys+=("cost")
                ;;
            burn_rate)
                # Hidden in compact mode
                if [[ "${is_compact}" != "true" ]]; then
                    parts+=("(\$2.99/hr)")
                    part_keys+=("burn_rate")
                fi
                ;;
            email)
                parts+=("user@email.com")
                part_keys+=("email")
                ;;
            version)
                parts+=("v2.0.37")
                part_keys+=("version")
                ;;
            lines)
                parts+=("+2109 -103")
                part_keys+=("lines")
                ;;
            session_time)
                parts+=("37m")
                part_keys+=("session_time")
                ;;
            cwd)
                parts+=("~/project")
                part_keys+=("cwd")
                ;;
        esac
    done

    # Join with " | ", merging adjacent tokens with "/" when compact
    local result=""
    local idx=0
    local total=${#parts[@]}

    while [[ ${idx} -lt ${total} ]]; do
        local cur_key="${part_keys[${idx}]}"
        local cur_val="${parts[${idx}]}"

        # Compact: merge adjacent related components with /
        # Groups: tokens (tokens_in/out/cache), usage (usage/weekly)
        if [[ "${is_compact}" == "true" ]]; then
            local merge_group=""
            case "${cur_key}" in
                tokens_in | tokens_out | tokens_cache) merge_group="tokens" ;;
                usage | weekly) merge_group="usage" ;;
            esac

            if [[ -n "${merge_group}" ]]; then
                local merged="${cur_val}"
                local next=$((idx + 1))
                while [[ ${next} -lt ${total} ]]; do
                    local next_group=""
                    case "${part_keys[${next}]}" in
                        tokens_in | tokens_out | tokens_cache) next_group="tokens" ;;
                        usage | weekly) next_group="usage" ;;
                    esac
                    if [[ "${next_group}" == "${merge_group}" ]]; then
                        merged+="/${parts[${next}]}"
                        next=$((next + 1))
                    else
                        break
                    fi
                done
                [[ -n "${result}" ]] && result+=" | "
                result+="${merged}"
                idx=${next}
                continue
            fi
        fi

        [[ -n "${result}" ]] && result+=" | "
        result+="${cur_val}"
        idx=$((idx + 1))
    done

    printf "%s%s" "${icon_prefix}" "${result}"
}

show_preview_box() {
    local preview
    preview=$(show_statusline_preview)

    echo ""
    local mode_label="wide, compact"
    [[ "${STATUSLINE_COMPACT}" != "true" ]] && mode_label="wide, verbose"

    # Dynamic box width: content + 2 padding chars, min 66
    local content_len=${#preview}
    local box_inner=$((content_len + 2))
    [[ ${box_inner} -lt 66 ]] && box_inner=66

    # Top border
    local header="─ Preview (${mode_label} mode, 42% usage) "
    local header_len=${#header}
    local top_pad=$((box_inner - header_len))
    [[ ${top_pad} -lt 0 ]] && top_pad=0
    printf "  ┌%s" "${header}"
    for ((i = 0; i < top_pad; i++)); do printf "─"; done
    printf "┐\n"

    # Content line
    printf "  │ %s" "${preview}"
    local pad=$((box_inner - content_len))
    [[ ${pad} -lt 0 ]] && pad=0
    printf "%*s│\n" "${pad}" ""

    # Bottom border
    printf "  └"
    for ((i = 0; i < box_inner; i++)); do printf "─"; done
    printf "┘\n"
    echo ""
    echo "  Settings:"
    local icon_display="${STATUSLINE_ICON:-none}"
    local compact_display="no"
    [[ "${STATUSLINE_COMPACT}" == "true" ]] && compact_display="yes"
    local style_display="${STATUSLINE_ICON_STYLE}"
    [[ -z "${STATUSLINE_ICON}" ]] && style_display="n/a"
    echo "    theme: ${STATUSLINE_THEME} | compact: ${compact_display} | color: ${STATUSLINE_COLOR_SCOPE} | bar: ${STATUSLINE_BAR_STYLE} | icon: ${icon_display} (${style_display})"
    local comp_display="${STATUSLINE_COMPONENTS//,/, }"
    if [[ ${#comp_display} -gt 60 ]]; then
        comp_display="${comp_display:0:57}..."
    fi
    echo "    components: ${comp_display}"
}
