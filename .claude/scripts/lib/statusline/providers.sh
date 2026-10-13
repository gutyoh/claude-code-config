# providers.sh -- Plan usage for the provider behind the session's model
# Path: .claude/scripts/lib/statusline/providers.sh
# Sourced by statusline.sh — do not execute directly.
#
# Claude Code can run GPT and Muse models through a router; the statusline then
# shows that plan's limits instead of Claude's. Each reader uses the provider's
# own login read-only, never refreshing it: a login has exactly one refresher,
# and a refresh token spent here would sign that refresher out.
#
# Readers print one normalized line, which is also the cache format:
#   session_pct<TAB>session_reset<TAB>weekly_pct<TAB>weekly_reset<TAB>fetched_at<TAB>weekly_seen_at
# Times are epoch seconds; weekly_seen_at is when the provider last reported the
# weekly window, older than fetched_at when a reading is carried. An empty field
# means the plan reports no such window, so the statusline hides it.
#
# Readings live in the state directory, not a temp one: a weekly reading carried
# through an idle window must outlive a reboot.

# Both endpoints answer in under a second; Claude Code cancels a long render.
readonly PROVIDER_CONNECT_TIMEOUT=2
readonly PROVIDER_CURL_TIMEOUT=4
readonly PROVIDER_CACHE_TTL=120
readonly OPENAI_USAGE_URL="https://chatgpt.com/backend-api/wham/usage"
readonly MUSE_USAGE_URL="https://api.meta.ai/muse-code/key"

# usage_provider <model id>: claude, openai, muse, or none for a model whose
# plan has no reader. No id at all is Claude, as before models were routed.
usage_provider() {
    case "$1" in
        "" | *claude* | opus* | sonnet* | haiku* | fable* | default | best) echo "claude" ;;
        gpt-* | o[0-9]* | codex-* | chatgpt-*) echo "openai" ;;
        muse-* | muse) echo "muse" ;;
        *) echo "none" ;;
    esac
}

# Login files. STATUSLINE_*_AUTH points at a login kept elsewhere, such as a
# model router's; it may be a glob, and the first match is used.
openai_auth_path() {
    printf '%s' "${STATUSLINE_OPENAI_AUTH:-${CODEX_HOME:-${HOME}/.codex}/auth.json}"
}

muse_auth_path() {
    printf '%s' "${STATUSLINE_MUSE_AUTH:-${MUSE_AUTH_PATH:-${XDG_CONFIG_HOME:-${HOME}/.config}/muse/auth.json}}"
}

# First existing file a path or glob names. Plain globbing, not compgen, which
# non-interactive bash builds leave out; IFS stays empty so spaces never split.
_first_file() {
    local IFS="" match nullglob
    nullglob=$(shopt -p nullglob)
    shopt -s nullglob
    # shellcheck disable=SC2206 # the pattern is meant to expand
    local matches=($1)
    eval "${nullglob}"
    for match in ${matches[@]+"${matches[@]}"}; do
        [[ -f "${match}" ]] && printf '%s' "${match}" && return 0
    done
    return 1
}

# curl with the bearer token on stdin, so it never shows in the process list,
# and with the statusline's own proxy (curl_proxy_config in api.sh).
_curl_bearer() {
    local token="$1"
    shift
    {
        curl_proxy_config
        printf 'header = "Authorization: Bearer %s"\n' "${token}"
    } | curl -sf -K - --connect-timeout "${PROVIDER_CONNECT_TIMEOUT}" \
        --max-time "${PROVIDER_CURL_TIMEOUT}" \
        -H "Accept: application/json" "$@" 2>/dev/null
}

# ChatGPT plan windows. Windows are told apart by their length, never by slot:
# some plans report only the weekly window, as the primary one.
fetch_openai_usage() {
    local auth token account body
    auth=$(_first_file "$(openai_auth_path)") || return 1
    token=$(jq -r '.tokens.access_token // empty' "${auth}" 2>/dev/null)
    account=$(jq -r '.tokens.account_id // empty' "${auth}" 2>/dev/null)
    [[ -n "${token}" ]] || return 1

    local args=()
    [[ -n "${account}" ]] && args=(-H "ChatGPT-Account-Id: ${account}")
    body=$(_curl_bearer "${token}" ${args[@]+"${args[@]}"} "${OPENAI_USAGE_URL}") || return 1

    printf '%s' "${body}" | jq -er --arg now "$(date +%s)" '
        [.rate_limit.primary_window, .rate_limit.secondary_window]
        | map(select(type == "object" and .used_percent != null)) as $w
        | ($w | map(select((.limit_window_seconds // 0) < 86400)) | first) as $s
        | ($w | map(select((.limit_window_seconds // 0) >= 86400)) | first) as $k
        | select($s != null or $k != null)
        | [$s.used_percent, $s.reset_at, $k.used_percent, $k.reset_at, $now,
           (if $k != null then $now else null end)]
        | map(if . == null then "" else tostring end) | join("\t")' 2>/dev/null
}

# Muse Code plan windows. The response omits them while the 5-hour window is
# idle: that window is then at 0, and the weekly one keeps its last reading,
# and when it was seen, until it resets.
fetch_muse_usage() {
    local auth token body now
    auth=$(_first_file "$(muse_auth_path)") || return 1
    # The Muse CLI's own login, or a router's copy of the same device login.
    token=$(jq -r '.providers.meta.accessToken // .dca_token // empty' "${auth}" 2>/dev/null)
    [[ "${token}" == dca:* ]] || return 1

    body=$(_curl_bearer "${token}" -X POST -H "x-api-version: 1.0.0" \
        -H "Content-Type: application/json" -d '{}' "${MUSE_USAGE_URL}") || return 1
    now=$(date +%s)

    local previous=""
    [[ -f "${CACHE_FILE}" ]] && previous=$(cat "${CACHE_FILE}" 2>/dev/null)
    printf '%s' "${body}" | jq -er --arg now "${now}" --arg prev "${previous}" '
        select(.is_subs_active == true)
        | ($now | tonumber) as $t
        | ($prev | split("\t")) as $p
        | if .subs_usage == null then
            ((($p[3] // "") | tonumber? // 0) > $t) as $keep
            | [0, "",
               (if $keep then $p[2] else "" end),
               (if $keep then $p[3] else "" end),
               $t,
               (if $keep then ([$p[5], $p[4]] | map(select(. != null and . != "")) | first // "")
                else "" end)]
          else
            .subs_usage as $u
            | [(if ($u.window.resets_at // 0) > $t then $u.window.used_percent else 0 end),
               (if ($u.window.resets_at // 0) > $t then $u.window.resets_at else "" end),
               $u.weekly.used_percent, $u.weekly.resets_at, $t,
               (if $u.weekly.used_percent != null then $t else null end)]
          end
        | map(if . == null then "" else tostring end) | join("\t")' 2>/dev/null
}

usage_state_dir() {
    printf '%s' "${_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code/statusline}"
}

# Serves a provider's line through its own cache, keyed by login file so two
# logins never share a reading. Lock and backoff stay in the temp directory.
get_provider_usage() {
    local provider="$1" auth key dir
    case "${provider}" in
        openai) auth=$(openai_auth_path) ;;
        muse) auth=$(muse_auth_path) ;;
        *) return 1 ;;
    esac
    key="${provider}-$(printf '%s' "${auth}" | cksum | cut -d' ' -f1)"
    dir=$(usage_state_dir)
    mkdir -p "${dir}" 2>/dev/null || dir="${_TMP_DIR}"
    local CACHE_FILE="${dir}/usage-${key}"
    local LOCK_DIR="${_TMP_DIR}/usage-${key}.lock"
    local BACKOFF_FILE="${_TMP_DIR}/usage-${key}.backoff"
    local CACHE_TTL="${PROVIDER_CACHE_TTL}"
    cached_fetch "fetch_${provider}_usage"
}

# The model router's judgment of each plan's prompt cache: a warning naming
# every plan whose recent warm turns reused nothing, else nothing at all.
router_health_warning() {
    [[ ${CONF_ROUTER_HEALTH:-on} == off ]] && return 0
    local file=${STATUSLINE_ROUTER_HEALTH:-} plans
    [[ -n ${file} && -s ${file} ]] || return 0
    plans=$(jq -r '[(.cache // {}) | to_entries[] | select(.value.cache == "missing") | .key]
        | join(", ")' "${file}" 2>/dev/null) || return 0
    [[ -n ${plans} ]] && printf '⚠ %s cache missing' "${plans}"
    return 0
}
