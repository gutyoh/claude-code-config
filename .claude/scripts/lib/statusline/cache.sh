# cache.sh -- API cache with global lock, exponential backoff+jitter, stale-while-error
# Path: .claude/scripts/lib/statusline/cache.sh
# Sourced by statusline.sh — do not execute directly.
#
# Design (SOTA 2026):
#   1. Global cross-session lock (mkdir atomic): only ONE process fetches the API.
#      Other processes serve from cache. Prevents thundering herd across N sessions.
#      Stale locks (from killed processes) auto-recovered after LOCK_MAX_AGE_S.
#   2. Capped exponential backoff with jitter on 429/failure: 30s → 60s → 120s → 300s.
#      Uses AWS "decorrelated jitter" pattern to spread retries across sessions.
#      Stored in a shared backoff file so all sessions respect it.
#   3. Stale-while-error: if the API fails, ALWAYS serve the last known good value
#      regardless of cache age. Real stale data >> token-based estimation.
#
# References:
#   - AWS Builders' Library: "Timeouts, retries, and backoff with jitter"
#   - AWS Architecture Blog: "Exponential Backoff And Jitter" (Marc Brooker)
#   - Greg's Wiki BashFAQ/045 (mkdir atomic locking)

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

# --- Global Lock (mkdir atomic, POSIX-portable) ---

try_acquire_lock() {
    # Recover stale locks from killed/crashed processes
    if [[ -d "${LOCK_DIR}" ]]; then
        local lock_age
        lock_age=$(get_file_age "${LOCK_DIR}") || lock_age=0
        if [[ ${lock_age} -gt ${LOCK_MAX_AGE_S} ]]; then
            rm -rf "${LOCK_DIR}" 2>/dev/null
        fi
    fi

    mkdir "${LOCK_DIR}" 2>/dev/null
}

release_lock() {
    rm -rf "${LOCK_DIR}" 2>/dev/null
}

# --- Capped Exponential Backoff with Decorrelated Jitter ---
# Shared state in BACKOFF_FILE: next_retry_epoch<TAB>current_delay_s
#
# Decorrelated jitter (AWS recommended for shared state):
#   next_delay = random_between(base, min(cap, prev_delay * 3))
# This spreads retry times across sessions sharing the same backoff file.

read_backoff() {
    [[ ! -f "${BACKOFF_FILE}" ]] && return 1
    cat "${BACKOFF_FILE}"
}

should_backoff() {
    local backoff_data
    backoff_data=$(read_backoff) || return 1

    local next_retry
    next_retry=$(printf "%s" "${backoff_data}" | cut -f1)
    local now
    now=$(date +%s)

    [[ ${now} -lt ${next_retry} ]]
}

increase_backoff() {
    local now current_delay next_delay next_retry jitter_max
    now=$(date +%s)

    local backoff_data
    backoff_data=$(read_backoff 2>/dev/null) || backoff_data=""

    if [[ -n "${backoff_data}" ]]; then
        current_delay=$(printf "%s" "${backoff_data}" | cut -f2)
    else
        current_delay=0
    fi

    # Decorrelated jitter: random_between(base, min(cap, prev * 3))
    if [[ ${current_delay} -eq 0 ]]; then
        next_delay=${BACKOFF_INITIAL_S}
    else
        jitter_max=$((current_delay * 3))
        [[ ${jitter_max} -gt ${BACKOFF_MAX_S} ]] && jitter_max=${BACKOFF_MAX_S}
        # RANDOM is 0-32767; scale to [base, jitter_max]
        local range=$((jitter_max - BACKOFF_INITIAL_S))
        if [[ ${range} -le 0 ]]; then
            next_delay=${BACKOFF_INITIAL_S}
        else
            next_delay=$((BACKOFF_INITIAL_S + (RANDOM % (range + 1))))
        fi
    fi
    [[ ${next_delay} -gt ${BACKOFF_MAX_S} ]] && next_delay=${BACKOFF_MAX_S}

    next_retry=$((now + next_delay))
    local tmp_backoff="${BACKOFF_FILE}.tmp.$$"
    printf "%s\t%s" "${next_retry}" "${next_delay}" >"${tmp_backoff}"
    mv -f "${tmp_backoff}" "${BACKOFF_FILE}"
}

reset_backoff() {
    rm -f "${BACKOFF_FILE}" 2>/dev/null
}

# --- Cache Refresh ---

refresh_api_cache() {
    local data
    data=$(get_api_session_data) || return 1
    if [[ -n "${data}" ]]; then
        local tmp_cache="${CACHE_FILE}.tmp.$$"
        printf "%s" "${data}" >"${tmp_cache}"
        mv -f "${tmp_cache}" "${CACHE_FILE}"
    fi
}

# --- Main Entry Point ---

get_cached_api_data() {
    local cache_age=999999

    debug "get_cached_api_data: checking cache at ${CACHE_FILE}"

    if [[ -f "${CACHE_FILE}" ]]; then
        cache_age=$(get_file_age "${CACHE_FILE}") || cache_age=999999
        debug "get_cached_api_data: cache age = ${cache_age}s (TTL=${CACHE_TTL}s)"
    else
        debug "get_cached_api_data: no cache file exists"
    fi

    # 1. Fresh cache (< TTL): serve immediately, no API call
    if [[ ${cache_age} -lt ${CACHE_TTL} ]]; then
        debug "get_cached_api_data: serving fresh cache"
        cat "${CACHE_FILE}"
        return 0
    fi

    # 2. Stale cache: try to refresh (with lock + backoff)
    debug "get_cached_api_data: attempting API refresh..."
    if try_acquire_lock; then
        debug "get_cached_api_data: acquired lock"
        if ! should_backoff; then
            debug "get_cached_api_data: calling get_api_session_data..."
            local data
            if data=$(get_api_session_data) && [[ -n "${data}" ]]; then
                debug "get_cached_api_data: API success, caching data"
                local tmp_cache="${CACHE_FILE}.tmp.$$"
                printf "%s" "${data}" >"${tmp_cache}"
                mv -f "${tmp_cache}" "${CACHE_FILE}"
                reset_backoff
                release_lock
                cat "${CACHE_FILE}"
                return 0
            else
                debug "get_cached_api_data: API failed, increasing backoff"
                increase_backoff
            fi
        else
            debug "get_cached_api_data: in backoff period, skipping API call"
        fi
        release_lock
    else
        debug "get_cached_api_data: could not acquire lock"
    fi

    # 3. Stale-while-error: serve last known good value regardless of age
    if [[ -f "${CACHE_FILE}" ]]; then
        debug "get_cached_api_data: serving stale cache"
        cat "${CACHE_FILE}"
        return 0
    fi

    # 4. No cache ever existed — true cold start
    debug "get_cached_api_data: cold start, no data available"
    return 1
}
