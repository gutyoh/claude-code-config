#!/usr/bin/env bash
# auto-rotate-mcp-key.sh
# Path: .claude/hooks/auto-rotate-mcp-key.sh
#
# Claude Code PostToolUse hook that transparently recovers from MCP quota
# exhaustion (Tavily HTTP 432, Brave HTTP 429) using updatedMCPToolOutput.
#
# Flow on quota error:
#   1. Detect 432/429 or quota/rate-limit keywords in .tool_response
#   2. Acquire per-service lock (atomic mkdir)
#   3. Run mcp-key-rotate <service> to advance the Doppler/dotenv pool
#   4. Re-read the now-active key from the secrets backend
#   5. Replay the ORIGINAL request against the vendor HTTP API with the new key
#   6. Return the real results via hookSpecificOutput.updatedMCPToolOutput so
#      Claude sees a successful tool call -- no restart, no user action.
#   7. On replay failure (curl missing, non-replayable tool, network error),
#      emit hookSpecificOutput.additionalContext with a "restart required"
#      message so Claude actually surfaces it to the user.
#
# Supported replay tools:
#   - mcp__tavily__tavily_search           -> https://api.tavily.com/search
#   - mcp__brave-search__brave_web_search  -> https://api.search.brave.com/res/v1/web/search
# All other tavily/brave MCP tools fall through to the additionalContext path.
#
# Configuration (env vars):
#   AUTO_ROTATE_COOLDOWN_SEC       Seconds between rotations (default: 300)
#   AUTO_ROTATE_STATE_DIR          State directory (default: /tmp)
#   AUTO_ROTATE_REPLAY_TIMEOUT     curl --max-time for replay (default: 15)
#   AUTO_ROTATE_REPLAY_KEY_OVERRIDE  Test hook: use this key instead of reading backend
#   AUTO_ROTATE_DISABLE_REPLAY     If set, skip replay entirely (fallback path only)
#   AUTO_ROTATE_BAD_KEY_TTL_SEC    TTL when marking a failing key OPEN (default: 3600)
#   KEY_ROTATE_DOPPLER_PROJECT     Doppler project name (default: claude-code-config)
#   KEY_ROTATE_DOPPLER_CONFIG      Doppler config name (default: dev)
#   KEY_ROTATE_DOTENV              .env file path for dotenv backend
#   MCP_KEY_HEALTH_DIR             Health state dir (default: ~/.claude/state)
#
# Wired in .claude/settings.json as PostToolUse with matcher:
#   mcp__(tavily|brave-search)__.*
#
# Platforms: macOS, Linux

set -euo pipefail

# --- Configuration ---

readonly COOLDOWN_SEC="${AUTO_ROTATE_COOLDOWN_SEC:-300}"
readonly STATE_DIR="${AUTO_ROTATE_STATE_DIR:-/tmp}"
readonly REPLAY_TIMEOUT="${AUTO_ROTATE_REPLAY_TIMEOUT:-15}"
readonly BAD_KEY_TTL_SEC="${AUTO_ROTATE_BAD_KEY_TTL_SEC:-3600}"
readonly DOPPLER_PROJECT="${KEY_ROTATE_DOPPLER_PROJECT:-claude-code-config}"
readonly DOPPLER_CONFIG="${KEY_ROTATE_DOPPLER_CONFIG:-dev}"

# --- Helpers: state / locking / cooldown ---

now_epoch() {
    date +%s
}

cooldown_file() {
    local service="$1"
    echo "${STATE_DIR}/mcp-auto-rotate-${service}.ts"
}

lock_dir() {
    local service="$1"
    echo "${STATE_DIR}/mcp-auto-rotate-${service}.lock"
}

acquire_lock() {
    local service="$1"
    local lockdir
    lockdir="$(lock_dir "${service}")"
    mkdir -p "${STATE_DIR}"

    local retries=0
    local max_retries=20 # 20 * 100ms = 2 seconds max wait
    while ! mkdir "${lockdir}" 2>/dev/null; do
        retries=$((retries + 1))
        if [[ ${retries} -ge ${max_retries} ]]; then
            rm -rf "${lockdir}"
            mkdir "${lockdir}" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
}

release_lock() {
    local service="$1"
    rm -rf "$(lock_dir "${service}")"
}

is_in_cooldown() {
    local service="$1"
    local cf
    cf="$(cooldown_file "${service}")"

    if [[ ! -f "${cf}" ]]; then
        return 1
    fi

    local last_rotate now elapsed
    last_rotate="$(cat "${cf}" 2>/dev/null || echo "0")"
    if [[ ! "${last_rotate}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    now="$(now_epoch)"
    elapsed=$((now - last_rotate))

    if [[ ${elapsed} -lt ${COOLDOWN_SEC} ]]; then
        return 0
    fi
    return 1
}

set_cooldown() {
    local service="$1"
    mkdir -p "${STATE_DIR}"
    now_epoch >"$(cooldown_file "${service}")"
}

# --- Service resolution ---

resolve_service() {
    local tool_name="$1"
    case "${tool_name}" in
        mcp__tavily__*) echo "tavily" ;;
        mcp__brave-search__*) echo "brave" ;;
        *) echo "" ;;
    esac
}

# --- Error detection ---

is_quota_error() {
    local service="$1" result_text="$2"

    case "${service}" in
        tavily)
            # Tavily returns HTTP 432 for quota exhaustion.
            # Anchored patterns: require context words to avoid false positives
            # (e.g. "found 432 results" won't match)
            if [[ "${result_text}" =~ status[[:space:]]*code[[:space:]]*432 ]] ||
                [[ "${result_text}" =~ [Ee]rror[[:space:]:.]*432 ]] ||
                [[ "${result_text}" =~ HTTP[[:space:]]*432 ]] ||
                [[ "${result_text}" =~ [Qq]uota[[:space:]]*(exceeded|exhausted|reached|limit) ]] ||
                [[ "${result_text}" =~ [Rr]ate[[:space:]]*[Ll]imit ]]; then
                return 0
            fi
            ;;
        brave)
            # Brave returns HTTP 429 for rate limit / quota.
            if [[ "${result_text}" =~ status[[:space:]]*code[[:space:]]*429 ]] ||
                [[ "${result_text}" =~ [Ee]rror[[:space:]:.]*429 ]] ||
                [[ "${result_text}" =~ HTTP[[:space:]]*429 ]] ||
                [[ "${result_text}" =~ [Tt]oo[[:space:]]*[Mm]any[[:space:]]*[Rr]equests ]] ||
                [[ "${result_text}" =~ [Rr]ate[[:space:]]*[Ll]imit ]] ||
                [[ "${result_text}" =~ [Qq]uota[[:space:]]*(exceeded|exhausted|reached|limit) ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# --- Locate mcp-key-rotate ---

find_rotate_cmd() {
    local cmd
    cmd="$(command -v mcp-key-rotate 2>/dev/null || echo "")"
    if [[ -n "${cmd}" && -x "${cmd}" ]]; then
        echo "${cmd}"
        return
    fi

    if [[ -x "${HOME}/.local/bin/mcp-key-rotate" ]]; then
        echo "${HOME}/.local/bin/mcp-key-rotate"
        return
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_cmd="${script_dir}/../../bin/mcp-key-rotate"
    if [[ -x "${repo_cmd}" ]]; then
        echo "${repo_cmd}"
        return
    fi

    echo ""
}

# --- Read active key after rotation ---

read_active_key() {
    local service="$1" var_name

    # Test-injection override: set in bats to supply a known key.
    if [[ -n "${AUTO_ROTATE_REPLAY_KEY_OVERRIDE:-}" ]]; then
        echo "${AUTO_ROTATE_REPLAY_KEY_OVERRIDE}"
        return
    fi

    case "${service}" in
        tavily) var_name="TAVILY_API_KEY" ;;
        brave) var_name="BRAVE_API_KEY" ;;
        *) return 1 ;;
    esac

    # 1. Doppler backend
    if command -v doppler &>/dev/null; then
        local val
        val="$(doppler secrets get "${var_name}" --plain \
            -p "${DOPPLER_PROJECT}" -c "${DOPPLER_CONFIG}" 2>/dev/null || echo "")"
        if [[ -n "${val}" ]]; then
            echo "${val}"
            return
        fi
    fi

    # 2. dotenv backend
    local dotenv="${KEY_ROTATE_DOTENV:-}"
    if [[ -z "${dotenv}" ]]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        dotenv="${script_dir}/../../.env"
    fi
    if [[ -f "${dotenv}" ]]; then
        local val
        val="$(grep "^${var_name}=" "${dotenv}" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^"//;s/"$//')"
        if [[ -n "${val}" ]]; then
            echo "${val}"
            return
        fi
    fi

    # 3. Current environment (last resort; almost certainly stale in a PostToolUse hook)
    echo "${!var_name:-}"
}

# --- Direct HTTP replay: Tavily search ---

replay_tavily_search() {
    local api_key="$1" query="$2" search_depth="$3" max_results="$4"
    local body
    body="$(jq -n \
        --arg k "${api_key}" \
        --arg q "${query}" \
        --arg sd "${search_depth}" \
        --argjson mr "${max_results}" \
        '{api_key: $k, query: $q, search_depth: $sd, max_results: $mr}')"
    curl -sS --max-time "${REPLAY_TIMEOUT}" \
        -X POST https://api.tavily.com/search \
        -H "Content-Type: application/json" \
        -d "${body}"
}

# --- Direct HTTP replay: Brave web search ---

replay_brave_web_search() {
    local api_key="$1" query="$2" count="$3"
    curl -sS --max-time "${REPLAY_TIMEOUT}" \
        --get "https://api.search.brave.com/res/v1/web/search" \
        --data-urlencode "q=${query}" \
        --data-urlencode "count=${count}" \
        -H "X-Subscription-Token: ${api_key}" \
        -H "Accept: application/json"
}

# PostToolUseFailure drops updatedMCPToolOutput silently and caps additionalContext
# at 10K chars: https://code.claude.com/docs/en/hooks -- 8500 leaves headroom for
# framing prose + jq JSON escaping.
readonly ADDITIONAL_CONTEXT_MAX_CHARS=8500

emit_updated_output() {
    local hook_event_name="$1" text="$2" note="$3"

    if [[ "${hook_event_name}" == "PostToolUseFailure" ]]; then
        local truncated="${text}"
        if [[ ${#truncated} -gt ${ADDITIONAL_CONTEXT_MAX_CHARS} ]]; then
            truncated="${truncated:0:${ADDITIONAL_CONTEXT_MAX_CHARS}}

[... truncated at ${ADDITIONAL_CONTEXT_MAX_CHARS} chars ...]"
        fi
        local combined="${note}

RECOVERED RESULTS (use these as if they were the tool response; the raw call failed but the auto-rotate hook replayed it successfully against the vendor API with a rotated key):

${truncated}"
        jq -n \
            --arg e "${hook_event_name}" \
            --arg c "${combined}" \
            '{
                hookSpecificOutput: {
                    hookEventName: $e,
                    additionalContext: $c
                }
            }'
    else
        jq -n \
            --arg e "${hook_event_name}" \
            --arg t "${text}" \
            --arg n "${note}" \
            '{
                hookSpecificOutput: {
                    hookEventName: $e,
                    updatedMCPToolOutput: [ { type: "text", text: $t } ],
                    additionalContext: $n
                }
            }'
    fi
}

emit_fallback_context() {
    local hook_event_name="$1" service="$2" detail="$3"
    local context
    context="[auto-rotate] ${service}: API quota exhausted. ${detail} ACTION REQUIRED: Restart Claude Code for the new key to take effect. IMMEDIATE FALLBACK: Use /web-search (Claude built-in, no API key needed)."
    jq -n \
        --arg e "${hook_event_name}" \
        --arg c "${context}" \
        '{
            hookSpecificOutput: {
                hookEventName: $e,
                additionalContext: $c
            }
        }'
}

# --- Transparent replay orchestration ---
# Prints JSON on stdout and returns 0 on success, returns 1 on failure.
try_replay() {
    local hook_event_name="$1" service="$2" tool_name="$3" tool_input_json="$4"

    if [[ -n "${AUTO_ROTATE_DISABLE_REPLAY:-}" ]]; then
        return 1
    fi

    if ! command -v curl &>/dev/null; then
        return 1
    fi

    local new_key
    new_key="$(read_active_key "${service}")" || return 1
    if [[ -z "${new_key}" ]]; then
        return 1
    fi

    case "${tool_name}" in
        mcp__tavily__tavily_search)
            local query search_depth max_results response
            query="$(echo "${tool_input_json}" | jq -r '.query // empty')"
            [[ -z "${query}" ]] && return 1
            search_depth="$(echo "${tool_input_json}" | jq -r '.search_depth // "basic"')"
            max_results="$(echo "${tool_input_json}" | jq -r '(.max_results // 5) | tonumber? // 5')"
            response="$(replay_tavily_search "${new_key}" "${query}" "${search_depth}" "${max_results}" 2>/dev/null)" || return 1
            echo "${response}" | jq -e '.results' >/dev/null 2>&1 || return 1
            local text
            text="$(echo "${response}" | jq -r '
                "# Tavily search results for: " + (.query // "query") + "\n\n" +
                ((.answer // "") | if length > 0 then "**Answer:** " + . + "\n\n" else "" end) +
                (.results | map(
                    "## " + (.title // "Untitled") + "\n" +
                    (.url // "") + "\n\n" +
                    (.content // "")
                ) | join("\n\n---\n\n"))
            ')"
            emit_updated_output "${hook_event_name}" "${text}" "[auto-rotate] tavily: Quota exhausted -- transparently replayed tavily_search via direct HTTP with rotated key. No restart needed."
            return 0
            ;;
        mcp__brave-search__brave_web_search)
            local query count response
            query="$(echo "${tool_input_json}" | jq -r '.query // empty')"
            [[ -z "${query}" ]] && return 1
            count="$(echo "${tool_input_json}" | jq -r '(.count // 10) | tonumber? // 10')"
            response="$(replay_brave_web_search "${new_key}" "${query}" "${count}" 2>/dev/null)" || return 1
            echo "${response}" | jq -e '.web.results' >/dev/null 2>&1 || return 1
            local text
            text="$(echo "${response}" | jq -r '
                "# Brave web search results for: " + (.query.original // "query") + "\n\n" +
                (.web.results | map(
                    "## " + (.title // "Untitled") + "\n" +
                    (.url // "") + "\n\n" +
                    (.description // "")
                ) | join("\n\n---\n\n"))
            ')"
            emit_updated_output "${hook_event_name}" "${text}" "[auto-rotate] brave: Quota exhausted -- transparently replayed brave_web_search via direct HTTP with rotated key. No restart needed."
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# --- Main ---

main() {
    local input
    input=$(cat)

    # Require jq for JSON parsing
    if ! command -v jq &>/dev/null; then
        exit 0
    fi

    # Echo back the firing event name -- Claude Code rejects mismatches.
    local hook_event_name
    hook_event_name=$(echo "${input}" | jq -r '.hook_event_name // "PostToolUse"' 2>/dev/null || true)
    if [[ -z "${hook_event_name}" ]]; then
        hook_event_name="PostToolUse"
    fi

    # Extract tool name
    local tool_name
    tool_name=$(echo "${input}" | jq -r '.tool_name // empty' 2>/dev/null) || true
    if [[ -z "${tool_name}" ]]; then
        exit 0
    fi

    # Resolve service
    local service
    service="$(resolve_service "${tool_name}")"
    if [[ -z "${service}" ]]; then
        exit 0
    fi

    # Extract tool result (real field is tool_response; legacy names kept for backward compat).
    # Claude Code PostToolUse payloads put the tool response in .tool_response as an object.
    local result_text
    result_text=$(echo "${input}" | jq -r '
        [.tool_response, .tool_result, .tool_output, .tool_error, .error] |
        map(select(. != null)) |
        map(tostring) |
        join(" ")
    ' 2>/dev/null) || true

    if [[ -z "${result_text}" ]]; then
        exit 0
    fi

    # Check for quota exhaustion
    if ! is_quota_error "${service}" "${result_text}"; then
        exit 0
    fi

    # --- Quota error detected ---

    # Acquire per-service lock (atomic mkdir) to prevent concurrent rotations
    acquire_lock "${service}"
    trap 'release_lock "${service}"' EXIT

    local tool_input_json
    tool_input_json="$(echo "${input}" | jq -c '.tool_input // {}')"

    # In cooldown: skip rotation, still try replay with the current active key.
    if is_in_cooldown "${service}"; then
        if try_replay "${hook_event_name}" "${service}" "${tool_name}" "${tool_input_json}"; then
            exit 0
        fi
        emit_fallback_context "${hook_event_name}" "${service}" \
            "Key was already rotated within the cooldown window. Replay was not possible for this tool call."
        exit 0
    fi

    # Locate rotation script
    local rotate_cmd
    rotate_cmd="$(find_rotate_cmd)"
    if [[ -z "${rotate_cmd}" ]]; then
        emit_fallback_context "${hook_event_name}" "${service}" \
            "mcp-key-rotate not found on PATH. Run manually: mcp-key-rotate ${service}"
        exit 0
    fi

    # The key the MCP server ACTUALLY used comes from the hook's inherited env
    # -- backend "current" can drift from it after out-of-band rotations.
    local env_var_name failing_key
    case "${service}" in
        tavily) env_var_name="TAVILY_API_KEY" ;;
        brave) env_var_name="BRAVE_API_KEY" ;;
        *) env_var_name="" ;;
    esac
    failing_key="${!env_var_name:-}"

    local recover_output
    if ! recover_output=$("${rotate_cmd}" "${service}" --recover-from-failure "${failing_key}" "${BAD_KEY_TTL_SEC}" 2>&1); then
        emit_fallback_context "${hook_event_name}" "${service}" \
            "Auto-rotation failed: ${recover_output}. Run manually: mcp-key-rotate ${service}"
        exit 0
    fi

    # Cooldown before replay so concurrent failures don't re-recover.
    set_cooldown "${service}"

    if try_replay "${hook_event_name}" "${service}" "${tool_name}" "${tool_input_json}"; then
        exit 0
    fi

    # Only mark newly-active bad if we actually rotated: the no-op drift path
    # didn't test the backend key, so it hasn't been proven to fail.
    if [[ "${recover_output}" != *"No rotation needed"* ]]; then
        local newly_active
        newly_active="$(echo "${recover_output}" | awk -F': ' '/^Active: /{print $2; exit}')"
        if [[ -n "${newly_active}" && "${newly_active}" != "${failing_key}" ]]; then
            "${rotate_cmd}" "${service}" --mark-bad-key "${newly_active}" "${BAD_KEY_TTL_SEC}" >/dev/null 2>&1 || true
        fi
    fi

    emit_fallback_context "${hook_event_name}" "${service}" "${recover_output}"
    exit 0
}

main "$@"
