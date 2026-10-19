#!/usr/bin/env bash
# session-remote-title.sh
# Path: .claude/hooks/session-remote-title.sh
#
# Gives a session's Remote Control entry (claude.ai/code and the Claude app)
# the session's own name. Resuming a session, above all as another account,
# can register a new remote session under an auto-generated name such as
# myhost-graceful-unicorn, and neither --name nor /rename reaches it then.
# This sets the title through the same endpoint the claude.ai rename uses.
#
# Events:
#   SessionStart, UserPromptSubmit  start a background check of this session
#                                   and return at once.
#
# The check watches <config>/sessions/<pid>.json for the wait: once the
# session's remote id is there, it sets the remote title to the session's
# name, and again when the name changes, once per remote session and name,
# with one check per session at a time. Only names someone chose
# count: /rename, --name, a hook such as session-name.sh, or another session;
# an unnamed session is left alone. It never refreshes the login: with an
# expired token it does nothing. The token reaches curl on stdin, never in the
# process list. Any error prints nothing and exits 0, so a session always
# starts.
#
# The endpoint, PUT /v1/code/sessions/<id>, is not documented; if it changes,
# this does nothing and Remote Control keeps its own title.
#
# Environment:
#   CLAUDE_REMOTE_TITLE        set to "off" to disable
#   CLAUDE_REMOTE_TITLE_WAIT   seconds to wait for the remote id (default 90)
#   CLAUDE_REMOTE_TITLE_FOREGROUND  set to 1 to run the check in the
#                              foreground, to debug it
#   CLAUDE_REMOTE_TITLE_HTTPS_PROXY  proxy for the request; set but empty
#                              means direct. Unset, STATUSLINE_HTTPS_PROXY
#                              applies: a router that intercepts the
#                              session's traffic would fail the request's TLS
#
# Usage:     Configured in .claude/settings.json (SessionStart, UserPromptSubmit)
# Platforms: macOS, Linux, Windows Git Bash

set -uo pipefail

readonly API="https://api.anthropic.com"
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code/remote-titles"
readonly KEYCHAIN_SERVICE="Claude Code-credentials"

home_dir() {
    local home="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
    printf '%s' "${home%/}"
}

# The account's file: ~/.claude keeps it beside the folder, other homes inside.
account_file() {
    if [[ $1 == "${HOME}/.claude" ]]; then
        printf '%s' "${HOME}/.claude.json"
    else
        printf '%s' "$1/.claude.json"
    fi
}

# Claude Code's login, as JSON: on macOS the Keychain entry each
# CLAUDE_CONFIG_DIR has, named after the variable exactly as set; elsewhere
# <config>/.credentials.json.
credentials() {
    local service="${KEYCHAIN_SERVICE}" sum creds=""
    if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
        sum=$(printf '%s' "${CLAUDE_CONFIG_DIR}" | { shasum -a 256 2>/dev/null || sha256sum; } | cut -c1-8)
        service="${service}-${sum}"
    fi
    [[ "$(uname -s)" == Darwin ]] && creds=$(security find-generic-password -s "${service}" -w 2>/dev/null)
    [[ -n "${creds}" ]] || creds=$(cat "$1/.credentials.json" 2>/dev/null)
    printf '%s' "${creds}"
}

# curl config line for the proxy, when one of the overrides is set at all.
proxy_config() {
    if [[ -n "${CLAUDE_REMOTE_TITLE_HTTPS_PROXY+set}" ]]; then
        printf 'proxy = "%s"\n' "${CLAUDE_REMOTE_TITLE_HTTPS_PROXY}"
    elif [[ -n "${STATUSLINE_HTTPS_PROXY+set}" ]]; then
        printf 'proxy = "%s"\n' "${STATUSLINE_HTTPS_PROXY}"
    fi
}

# The session's registry entry: <config>/sessions/<pid>.json naming its id.
# A process that crashed leaves its file behind, and a resume of the same
# session writes a new one; the newest is the running process.
registry_entry() {
    local file newest=""
    for file in "$1"/sessions/*.json; do
        [[ -f "${file}" ]] || continue
        grep -qF "\"$2\"" "${file}" 2>/dev/null || continue
        jq -e --arg id "$2" '.sessionId == $id' "${file}" >/dev/null 2>&1 || continue
        [[ -z "${newest}" || "${file}" -nt "${newest}" ]] && newest="${file}"
    done
    [[ -n "${newest}" ]] && cat "${newest}"
}

# One check per session at a time: a later event returns at once while one
# runs. A lock whose holder is gone, or older than the wait, is a check that
# died, and is taken over.
check() {
    local session="$1" wait lock holder
    wait="${CLAUDE_REMOTE_TITLE_WAIT:-90}"
    [[ "${wait}" =~ ^[0-9]+$ ]] || wait=90
    mkdir -p "${STATE_DIR}" 2>/dev/null || return 0
    lock="${STATE_DIR}/${session}.lock"
    if ! mkdir "${lock}" 2>/dev/null; then
        holder=$(cat "${lock}/pid" 2>/dev/null) || holder=""
        if ! { [[ "${holder}" =~ ^[0-9]+$ ]] && ! kill -0 "${holder}" 2>/dev/null; } \
            && [[ -z "$(find "${lock}" -maxdepth 0 -mmin "+$(((wait + 59) / 60 + 1))" 2>/dev/null)" ]]; then
            return 0
        fi
        rm -rf "${lock}"
        mkdir "${lock}" 2>/dev/null || return 0
    fi
    # This process's own pid: $$ names the parent shell in a subshell, and
    # bash 3.2 has no BASHPID.
    sh -c 'echo "${PPID}"' >"${lock}/pid" 2>/dev/null
    # A global: an EXIT trap runs after this function's locals are gone, and
    # a check killed midway must not hold the lock until it goes stale.
    LOCK_DIR="${lock}"
    trap 'rm -rf "${LOCK_DIR:-}"' EXIT
    sync_title "${session}" "${wait}"
}

# Watches the session's registry entry for the wait: its remote id appears
# once Remote Control has connected, and a name can still change after the
# event that started the check, when a hook renames the session at the same
# prompt. Each name is tried once.
sync_title() {
    local session="$1" wait="$2" home entry bridge name source tried=""
    home=$(home_dir)
    while :; do
        entry=$(registry_entry "${home}" "${session}") || entry=""
        bridge=$(printf '%s' "${entry}" | jq -r '.bridgeSessionId // empty' 2>/dev/null)
        name=$(printf '%s' "${entry}" | jq -r '.name // empty' 2>/dev/null)
        source=$(printf '%s' "${entry}" | jq -r '.nameSource // empty' 2>/dev/null)
        # A name nobody chose will not become one while this waits.
        case "${source}" in "" | user | hook | peer) ;; *) return 0 ;; esac
        if [[ -n "${source}" && -n "${bridge}" && -n "${name}" && "${bridge}:${name}" != "${tried}" ]]; then
            tried="${bridge}:${name}"
            set_title "${home}" "${bridge}" "${name}"
        fi
        ((wait <= 0)) && return 0
        sleep 2
        wait=$((wait - 2))
    done
}

# set_title <home> <bridge id> <name>: sets the remote title unless it was
# already set to that name.
set_title() {
    local home="$1" bridge="$2" name="$3" creds token expires org account remote state status
    [[ "${bridge}" =~ ^(session|cse)_[A-Za-z0-9]+$ ]] || return 0
    remote="cse_${bridge#*_}"
    state="${STATE_DIR}/${remote}"
    [[ "$(cat "${state}" 2>/dev/null)" == "${name}" ]] && return 0

    # A pipe, not a here-string: bash before 5.1 writes those to a temp file.
    creds=$(credentials "${home}")
    token=$(printf '%s' "${creds}" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    expires=$(printf '%s' "${creds}" | jq -r '.claudeAiOauth.expiresAt // 0' 2>/dev/null)
    creds=
    [[ -n "${token}" && "${expires}" =~ ^[0-9]+$ ]] || return 0
    # Never refresh: an expired login is Claude Code's to renew.
    ((expires / 1000 > $(date +%s) + 60)) || return 0
    account=$(account_file "${home}")
    org=$(jq -r '.oauthAccount.organizationUuid // empty' "${account}" 2>/dev/null)
    [[ "${org}" =~ ^[A-Za-z0-9-]+$ ]] || return 0

    status=$({
        proxy_config
        printf 'header = "%s"\n' \
            "Authorization: Bearer ${token}" \
            "anthropic-version: 2023-06-01" \
            "anthropic-beta: ccr-byoc-2025-07-29" \
            "x-organization-uuid: ${org}" \
            "content-type: application/json"
    } | curl -sS --connect-timeout 10 --max-time 30 --config - -X PUT -o /dev/null -w '%{http_code}' \
        --data "$(jq -nc --arg t "${name}" '{title: $t}')" \
        "${API}/v1/code/sessions/${remote}" 2>/dev/null)
    [[ "${status}" =~ ^2 ]] || return 0
    printf '%s' "${name}" >"${state}"
    return 0
}

main() {
    local input session
    [[ "${CLAUDE_REMOTE_TITLE:-}" == "off" ]] && return 0
    # Only interactive sessions have a Remote Control entry; a `claude -p`
    # started inside another session must not touch that session's.
    [[ "${CLAUDE_CODE_ENTRYPOINT:-cli}" == "cli" ]] || return 0
    # Remote Control talks to the Anthropic API only.
    [[ -z "${ANTHROPIC_BASE_URL:-}" || "${ANTHROPIC_BASE_URL%/}" == "${API}" ]] || return 0
    command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || return 0
    input=$(cat) || return 0
    session=$(jq -r '.session_id // empty' <<<"${input}" 2>/dev/null) || return 0
    [[ "${session}" =~ ^[A-Za-z0-9-]+$ ]] || return 0
    if [[ "${CLAUDE_REMOTE_TITLE_FOREGROUND:-}" == 1 ]]; then
        check "${session}"
        return 0
    fi
    # Detached from the hook's output, which Claude Code reads to the end.
    check "${session}" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

main
exit 0
