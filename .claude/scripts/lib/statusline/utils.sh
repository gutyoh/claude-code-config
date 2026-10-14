# utils.sh -- Utility functions (formatting, time conversion)
# Path: .claude/scripts/lib/statusline/utils.sh
# Sourced by statusline.sh — do not execute directly.

# Sets _NOW to the epoch second once per render: bash 5 has it built in, and
# the bash 3.2 macOS ships pays for one `date`.
epoch_now() {
    [[ -n "${_NOW:-}" ]] && return 0
    _NOW="${EPOCHSECONDS:-}"
    [[ -n "${_NOW}" ]] || _NOW=$(date +%s)
}

# 1234 -> 1.2k, 6200000 -> 6.2M, in integer arithmetic (no awk process).
format_num() {
    local num="${1:-0}" unit="" div=1 tenths
    num="${num%%.*}"
    [[ "${num}" =~ ^[0-9]+$ ]] || num=0
    if ((num >= 1000000)); then
        unit="M" div=1000000
    elif ((num >= 1000)); then
        unit="k" div=1000
    else
        printf "%d" "${num}"
        return
    fi
    tenths=$(((num * 10 + div / 2) / div))
    printf "%d.%d%s" "$((tenths / 10))" "$((tenths % 10))" "${unit}"
}

iso8601_to_epoch() {
    local timestamp="$1"

    case "${PLATFORM}" in
        linux | windows)
            date -d "${timestamp}" "+%s" 2>/dev/null
            ;;
        macos)
            local clean_date="${timestamp%%.*}"
            TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${clean_date}" "+%s" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

format_duration_ms() {
    local ms="${1:-0}"
    local total_sec=$((ms / 1000))
    local hours=$((total_sec / 3600))
    local mins=$(((total_sec % 3600) / 60))

    if [[ ${hours} -gt 0 ]]; then
        echo "${hours}h${mins}m"
    else
        echo "${mins}m"
    fi
}
