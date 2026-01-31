# tui.sh -- TUI primitives (interactive menus, arrow keys, ANSI)
# Path: lib/setup/tui.sh
# Sourced by setup.sh — do not execute directly.

# Read a single keypress and return a logical key name.
# Arrow keys are multi-byte: ESC [ A/B/C/D
tui_readkey() {
    local key
    IFS= read -rsn1 key </dev/tty

    case "${key}" in
        $'\x1b')
            # Escape sequence — read 2 more chars (arrow keys: [A [B etc)
            local seq
            IFS= read -rsn2 -t 0.1 seq </dev/tty || true
            case "${seq}" in
                '[A') echo "up" ;;
                '[B') echo "down" ;;
                '[C') echo "right" ;;
                '[D') echo "left" ;;
                *) echo "escape" ;;
            esac
            ;;
        '') echo "enter" ;;  # Enter key
        ' ') echo "space" ;; # Space bar
        [qQ]) echo "quit" ;;
        *) echo "${key}" ;;
    esac
}

# Single-select menu: arrow keys to navigate, enter to confirm.
# Usage: tui_select RESULT_VAR "header" "opt1" "opt2" ...
# Sets RESULT_VAR to the selected option string.
tui_select() {
    local -n _result_var="$1"
    local header="$2"
    shift 2
    local options=("$@")
    local count=${#options[@]}
    local cur=0

    # Save cursor and hide it
    tput civis 2>/dev/null || true

    # Print header
    echo ""
    printf "  \033[1m%s\033[0m\n" "${header}"
    echo ""

    # Initial draw
    local i
    for ((i = 0; i < count; i++)); do
        if [[ ${i} -eq ${cur} ]]; then
            printf "  \033[7m > %s \033[0m\n" "${options[$i]}"
        else
            printf "    %s\n" "${options[$i]}"
        fi
    done

    # Input loop
    while true; do
        local key
        key=$(tui_readkey)

        case "${key}" in
            up)
                [[ ${cur} -gt 0 ]] && cur=$((cur - 1))
                ;;
            down)
                [[ ${cur} -lt $((count - 1)) ]] && cur=$((cur + 1))
                ;;
            enter)
                break
                ;;
            quit | escape)
                break
                ;;
        esac

        # Move cursor up to redraw
        printf "\033[%dA" "${count}"

        for ((i = 0; i < count; i++)); do
            printf "\r\033[2K"
            if [[ ${i} -eq ${cur} ]]; then
                printf "  \033[7m > %s \033[0m\n" "${options[$i]}"
            else
                printf "    %s\n" "${options[$i]}"
            fi
        done
    done

    # Restore cursor
    tput cnorm 2>/dev/null || true

    _result_var="${options[$cur]}"
}

# Multi-select menu: arrow keys to navigate, space to toggle, enter to confirm.
# Usage: tui_multiselect RESULT_ARRAY_VAR "header" SELECTED_ARRAY OPTIONS_ARRAY DESCS_ARRAY
# Sets RESULT_ARRAY_VAR to array of selected indices.
tui_multiselect() {
    local -n _ms_result="$1"
    local header="$2"
    local -n _ms_selected="$3"
    local -n _ms_options="$4"
    local -n _ms_descs="$5"
    local count=${#_ms_options[@]}
    local cur=0

    # Build checked state from initial selection
    local checked=()
    for ((i = 0; i < count; i++)); do
        checked+=("false")
    done
    for idx in "${_ms_selected[@]}"; do
        if [[ ${idx} -ge 0 && ${idx} -lt ${count} ]]; then
            checked[${idx}]="true"
        fi
    done

    tput civis 2>/dev/null || true

    echo ""
    printf "  \033[1m%s\033[0m\n" "${header}"
    printf "  \033[2m(arrow keys: navigate, space: toggle, enter: confirm)\033[0m\n"
    echo ""

    # Draw function
    _ms_draw() {
        local i
        for ((i = 0; i < count; i++)); do
            local checkbox="[ ]"
            [[ "${checked[$i]}" == "true" ]] && checkbox="[x]"

            local desc=""
            if [[ ${#_ms_descs[@]} -gt ${i} && -n "${_ms_descs[$i]}" ]]; then
                desc=" \033[2m${_ms_descs[$i]}\033[0m"
            fi

            printf "\r\033[2K"
            if [[ ${i} -eq ${cur} ]]; then
                printf "  \033[7m %s %s \033[0m%b\n" "${checkbox}" "${_ms_options[$i]}" "${desc}"
            else
                printf "   %s %s%b\n" "${checkbox}" "${_ms_options[$i]}" "${desc}"
            fi
        done
    }

    _ms_draw

    while true; do
        local key
        key=$(tui_readkey)

        case "${key}" in
            up)
                [[ ${cur} -gt 0 ]] && cur=$((cur - 1))
                ;;
            down)
                [[ ${cur} -lt $((count - 1)) ]] && cur=$((cur + 1))
                ;;
            space)
                if [[ "${checked[$cur]}" == "true" ]]; then
                    checked[$cur]="false"
                else
                    checked[$cur]="true"
                fi
                ;;
            enter)
                break
                ;;
            a)
                # Select all
                for ((i = 0; i < count; i++)); do
                    checked[$i]="true"
                done
                ;;
            n)
                # Select none
                for ((i = 0; i < count; i++)); do
                    checked[$i]="false"
                done
                ;;
            quit | escape)
                break
                ;;
        esac

        printf "\033[%dA" "${count}"
        _ms_draw
    done

    tput cnorm 2>/dev/null || true

    # Collect selected indices
    _ms_result=()
    for ((i = 0; i < count; i++)); do
        if [[ "${checked[$i]}" == "true" ]]; then
            _ms_result+=("${i}")
        fi
    done
}

# Yes/No confirm: arrow keys to toggle, enter to confirm.
# Usage: tui_confirm "question" [default_yes]
# Returns 0 for yes, 1 for no.
tui_confirm() {
    local question="$1"
    local default="${2:-no}" # "yes" or "no"
    local selected=1         # 0=yes, 1=no
    [[ "${default}" == "yes" ]] && selected=0

    tput civis 2>/dev/null || true

    echo ""

    _cf_draw() {
        printf "\r\033[2K"
        printf "  %s  " "${question}"
        if [[ ${selected} -eq 0 ]]; then
            printf "\033[7m Yes \033[0m  No"
        else
            printf "Yes  \033[7m No \033[0m"
        fi
    }

    _cf_draw

    while true; do
        local key
        key=$(tui_readkey)

        case "${key}" in
            left | up | h | y | Y)
                selected=0
                ;;
            right | down | l | n | N)
                selected=1
                ;;
            enter)
                echo ""
                tput cnorm 2>/dev/null || true
                return ${selected}
                ;;
            quit | escape)
                echo ""
                tput cnorm 2>/dev/null || true
                return 1
                ;;
        esac

        _cf_draw
    done
}
