# bar.sh -- Progress bar rendering
# Path: .claude/scripts/lib/statusline/bar.sh
# Sourced by statusline.sh — do not execute directly.

render_progress_bar() {
    local pct="$1"
    local style="${2:-text}"
    local width="${3:-20}"
    local show_inner="${4:-false}"

    # Handle non-numeric pct
    if [[ "${pct}" == "--" || -z "${pct}" ]]; then
        case "${style}" in
            text)
                printf "session: %s" "--"
                return
                ;;
            spark)
                printf "%s" "--"
                return
                ;;
            *)
                # Empty bar
                local empty_bar=""
                local i
                for ((i = 0; i < width; i++)); do
                    case "${style}" in
                        block) empty_bar+="·" ;;
                        thin) empty_bar+="╌" ;;
                        *) empty_bar+="░" ;;
                    esac
                done
                case "${style}" in
                    block) printf "[%s] --" "${empty_bar}" ;;
                    *) printf "%s --" "${empty_bar}" ;;
                esac
                return
                ;;
        esac
    fi

    # Clamp 0-100
    local clamped=${pct}
    ((clamped < 0)) && clamped=0
    ((clamped > 100)) && clamped=100

    case "${style}" in
        text)
            printf "session: %s%% used" "${clamped}"
            ;;

        block)
            # [████████············] 21%
            local filled=$((clamped * width / 100))
            local empty=$((width - filled))
            local bar=""
            local i
            for ((i = 0; i < filled; i++)); do bar+="█"; done
            for ((i = 0; i < empty; i++)); do bar+="·"; done

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}" "█" "·"
            fi

            printf "[%s]" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        smooth)
            # Full unicode block bar with 1/8th sub-character precision
            # Partial block chars: ▏(1/8) ▎(2/8) ▍(3/8) ▌(4/8) ▋(5/8) ▊(6/8) ▉(7/8) █(8/8)
            local partials=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            local total_eighths=$((clamped * width * 8 / 100))
            local full_blocks=$((total_eighths / 8))
            local remainder=$((total_eighths % 8))
            local empty_blocks=$((width - full_blocks - (remainder > 0 ? 1 : 0)))

            local bar=""
            local i
            for ((i = 0; i < full_blocks; i++)); do bar+="█"; done
            if [[ ${remainder} -gt 0 ]]; then
                bar+="${partials[${remainder}]}"
            fi
            for ((i = 0; i < empty_blocks; i++)); do bar+="░"; done

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}" "█" "░"
            fi

            printf "%s" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        gradient)
            # Powerline gradient: █▓▒░
            # Filled region uses █, transition uses ▓▒, empty uses ░
            local filled=$((clamped * width / 100))
            local empty=$((width - filled))
            local bar=""
            local i

            if [[ ${filled} -eq 0 ]]; then
                # All empty
                for ((i = 0; i < width; i++)); do bar+="░"; done
            elif [[ ${empty} -eq 0 ]]; then
                # All filled
                for ((i = 0; i < width; i++)); do bar+="█"; done
            else
                # Filled blocks (leave room for ▓ transition)
                for ((i = 0; i < filled; i++)); do bar+="█"; done

                # Gradient transition: replace last empty char(s) with ▓ then ▒
                local remaining=$((empty))
                if [[ ${remaining} -ge 1 ]]; then
                    bar+="▓"
                    remaining=$((remaining - 1))
                fi
                if [[ ${remaining} -ge 1 ]]; then
                    bar+="▒"
                    remaining=$((remaining - 1))
                fi

                # Remaining empty
                for ((i = 0; i < remaining; i++)); do bar+="░"; done
            fi

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}" "█" "░"
            fi

            printf "%s" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        thin)
            # ━━━━━━━━╌╌╌╌╌╌╌╌╌╌╌╌ 21%
            local filled=$((clamped * width / 100))
            local empty=$((width - filled))
            local bar=""
            local i
            for ((i = 0; i < filled; i++)); do bar+="━"; done
            for ((i = 0; i < empty; i++)); do bar+="╌"; done

            if [[ "${show_inner}" == "true" ]]; then
                _overlay_pct_inside bar "${clamped}" "${width}" "━" "╌"
            fi

            printf "%s" "${bar}"
            if [[ "${show_inner}" != "true" ]]; then
                printf " %s%%" "${clamped}"
            fi
            ;;

        spark)
            # Compact spark-style vertical bars (5 chars wide)
            # Maps percentage to spark chars: ▁▂▃▄▅▆▇█
            local spark_chars=("▁" "▂" "▃" "▄" "▅" "▆" "▇" "█")
            local spark_width=5
            local bar=""
            local i

            for ((i = 0; i < spark_width; i++)); do
                # Each position represents a segment of the percentage
                local seg_start=$((i * 100 / spark_width))
                local seg_end=$(((i + 1) * 100 / spark_width))

                if [[ ${clamped} -ge ${seg_end} ]]; then
                    # Fully filled segment
                    bar+="█"
                elif [[ ${clamped} -le ${seg_start} ]]; then
                    # Empty segment
                    bar+="▁"
                else
                    # Partial segment — map within-segment percentage to spark char
                    local seg_range=$((seg_end - seg_start))
                    local seg_fill=$((clamped - seg_start))
                    local idx=$((seg_fill * 7 / seg_range))
                    ((idx > 7)) && idx=7
                    bar+="${spark_chars[${idx}]}"
                fi
            done

            printf "%s %s%%" "${bar}" "${clamped}"
            ;;

        *)
            # Unknown style, fall back to text
            printf "session: %s%% used" "${clamped}"
            ;;
    esac
}

# Helper: overlay " NN% " at center of bar string (passed by nameref)
# Builds the bar in three segments (left chars + ASCII label + right chars)
# instead of iterating/splicing multi-byte characters, which breaks on
# Windows Git Bash: https://github.com/actions/runner-images/issues/13585
_overlay_pct_inside() {
    local -n _bar="$1"
    local pct="$2"
    local width="$3"
    local filled_char="$4"   # e.g. █ ━
    local empty_char="$5"    # e.g. · ░ ╌

    local pct_str=" ${pct}% "
    local pct_len=${#pct_str}

    # Only overlay if bar is wide enough
    if [[ ${width} -ge $((pct_len + 2)) ]]; then
        local start=$(((width - pct_len) / 2))
        local after=$((start + pct_len))
        local tail=$((width - after))

        # Rebuild: left filled/empty chars + ASCII label + right filled/empty chars
        # Determine how many of the left segment are filled vs empty
        local filled=$((pct * width / 100))

        local new_bar=""
        local i

        # Left segment (0..start-1)
        for ((i = 0; i < start; i++)); do
            if [[ ${i} -lt ${filled} ]]; then
                new_bar+="${filled_char}"
            else
                new_bar+="${empty_char}"
            fi
        done

        # Middle: ASCII percentage label
        new_bar+="${pct_str}"

        # Right segment (after..width-1)
        for ((i = after; i < width; i++)); do
            if [[ ${i} -lt ${filled} ]]; then
                new_bar+="${filled_char}"
            else
                new_bar+="${empty_char}"
            fi
        done

        _bar="${new_bar}"
    fi
}
