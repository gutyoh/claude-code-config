# utils.sh -- Utility functions (formatting, time conversion)
# Path: .claude/scripts/lib/statusline/utils.sh
# Sourced by statusline.sh — do not execute directly.

format_num() {
    local num="${1:-0}"

    if [[ "${num}" -ge 1000000 ]]; then
        # Use awk for floating-point division (cross-platform: Linux, macOS, Windows Git Bash)
        awk "BEGIN { printf \"%.1fM\", ${num} / 1000000 }"
    elif [[ "${num}" -ge 1000 ]]; then
        awk "BEGIN { printf \"%.1fk\", ${num} / 1000 }"
    else
        printf "%d" "${num}"
    fi
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
