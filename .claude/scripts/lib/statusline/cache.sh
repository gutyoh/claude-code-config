# cache.sh -- API cache with stale-while-revalidate pattern
# Path: .claude/scripts/lib/statusline/cache.sh
# Sourced by statusline.sh — do not execute directly.

get_file_age() {
    local file="$1"
    local mtime now

    case "${PLATFORM}" in
        macos) mtime=$(stat -f "%m" "${file}" 2>/dev/null) ;;
        linux | windows) mtime=$(stat -c "%Y" "${file}" 2>/dev/null) ;;
        *) return 1 ;;
    esac

    [[ -z "${mtime}" ]] && return 1
    now=$(date +%s)
    echo $((now - mtime))
}

refresh_api_cache() {
    local data
    data=$(get_api_session_data) || return 1
    [[ -n "${data}" ]] && printf "%s" "${data}" >"${CACHE_FILE}"
}

get_cached_api_data() {
    local cache_age=999999

    if [[ -f "${CACHE_FILE}" ]]; then
        cache_age=$(get_file_age "${CACHE_FILE}") || cache_age=999999
    fi

    if [[ ${cache_age} -lt ${CACHE_TTL} ]]; then
        cat "${CACHE_FILE}"
        return 0
    fi

    if [[ -f "${CACHE_FILE}" && ${cache_age} -lt ${CACHE_MAX_AGE} ]]; then
        cat "${CACHE_FILE}"
        (refresh_api_cache) >/dev/null 2>&1 &
        disown 2>/dev/null
        return 0
    fi

    local data
    data=$(get_api_session_data) || return 1
    [[ -n "${data}" ]] && printf "%s" "${data}" >"${CACHE_FILE}"
    printf "%s" "${data}"
}
