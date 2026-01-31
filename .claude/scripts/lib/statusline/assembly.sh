# assembly.sh -- Component assembly (joins rendered components)
# Path: .claude/scripts/lib/statusline/assembly.sh
# Sourced by statusline.sh — do not execute directly.

render_all_components() {
    IFS=',' read -ra components_arr <<<"${CONF_COMPONENTS}"

    local outputs=()
    local keys=()
    local i

    for i in "${!components_arr[@]}"; do
        local key="${components_arr[$i]}"
        # Trim whitespace
        key=$(echo "${key}" | tr -d '[:space:]')

        # Check if render function exists
        if ! declare -f "render_component_${key}" &>/dev/null; then
            continue
        fi

        local output
        output=$(render_component_"${key}")

        # Skip empty outputs
        [[ -z "${output}" ]] && continue

        outputs+=("${output}")
        keys+=("${key}")
    done

    # Build final string with token merging in narrow mode
    local result=""
    local idx=0
    local total=${#outputs[@]}

    while [[ ${idx} -lt ${total} ]]; do
        local current_key="${keys[${idx}]}"
        local current_out="${outputs[${idx}]}"

        # Component merging: merge adjacent related components with /
        # Groups: tokens (tokens_in/out/cache), usage (usage/weekly)
        # Active in narrow mode always, and in wide mode when compact
        if [[ "${IS_WIDE}" != "true" || "${CONF_COMPACT}" == "true" ]]; then
            local merge_group=""
            case "${current_key}" in
                tokens_in | tokens_out | tokens_cache) merge_group="tokens" ;;
                usage | weekly) merge_group="usage" ;;
            esac

            if [[ -n "${merge_group}" ]]; then
                local merged="${current_out}"
                local next=$((idx + 1))

                while [[ ${next} -lt ${total} ]]; do
                    local next_group=""
                    case "${keys[${next}]}" in
                        tokens_in | tokens_out | tokens_cache) next_group="tokens" ;;
                        usage | weekly) next_group="usage" ;;
                    esac
                    if [[ "${next_group}" == "${merge_group}" ]]; then
                        merged+="/${outputs[${next}]}"
                        next=$((next + 1))
                    else
                        break
                    fi
                done

                if [[ -n "${result}" ]]; then
                    result+=" | "
                fi
                result+="${merged}"
                idx=${next}
                continue
            fi
        fi

        if [[ -n "${result}" ]]; then
            result+=" | "
        fi
        result+="${current_out}"
        idx=$((idx + 1))
    done

    printf "%s" "${result}"
}
