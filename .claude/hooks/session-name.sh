#!/usr/bin/env bash
# session-name.sh
# Path: .claude/hooks/session-name.sh
#
# Names each session <provider>-<YYYYMMDDTHHMMSS><zone>, for example
# claude-20261011T193012Z, and swaps the provider prefix when the model moves
# to another provider. The timestamp never changes once set.
#
# Events:
#   SessionStart      (startup) records when an untitled session started.
#   UserPromptSubmit  names an untitled session with that time and swaps the
#                     prefix after a provider switch. Claude Code shows a name
#                     on the prompt bar only when a prompt hook changes it.
#
# Only names matching the automatic pattern are ever changed: a name set with
# /rename or --name always wins. Any error prints nothing and exits 0, so a
# prompt is never blocked.
#
# Environment:
#   CLAUDE_SESSION_NAME_TZ  IANA time zone for the timestamp (default UTC)
#   CLAUDE_SESSION_NAME     set to "off" to disable naming
#
# Usage:     Configured in .claude/settings.json (SessionStart, UserPromptSubmit)
# Platforms: macOS, Linux, Windows Git Bash

set -uo pipefail

readonly AUTO_NAME='^[a-z0-9]+-[0-9]{8}T[0-9]{6}(Z|[+-][0-9]{4})$'
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code/session-names"
readonly STATE_MAX_AGE_DAYS=30

# claude-opus-5-5 -> claude, gpt-6.1-sol -> gpt; aliases without a dash
# (opus, sonnet) and unknown models count as claude.
provider_of() {
    local model segment
    model=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    [[ "${model}" == *-* ]] || {
        echo "claude"
        return
    }
    segment="${model%%-*}"
    segment="${segment//[^a-z0-9]/}"
    echo "${segment:-claude}"
}

timestamp() {
    local stamp
    stamp=$(TZ="${CLAUDE_SESSION_NAME_TZ:-UTC}" date +%Y%m%dT%H%M%S%z) || return 1
    case "${stamp: -5}" in
        +0000 | -0000) echo "${stamp:0:15}Z" ;;
        *) echo "${stamp}" ;;
    esac
}

emit() {
    jq -n --arg event "$1" --arg title "$2" \
        '{hookSpecificOutput: {hookEventName: $event, sessionTitle: $title}}'
}

recorded_model() {
    local file="${STATE_DIR}/$1.model"
    [[ -f "${file}" ]] && head -n 1 "${file}"
}

on_start() {
    local title="$1" session="$2" model="$3" stamp
    find "${STATE_DIR}" -type f -mtime +"${STATE_MAX_AGE_DAYS}" -delete 2>/dev/null
    [[ -z "${title}" ]] || return 0
    stamp=$(timestamp) || return 0
    mkdir -p "${STATE_DIR}" 2>/dev/null || return 0
    printf '%s\n' "${stamp}" >"${STATE_DIR}/${session}.start"
    # The statusline keeps this current; without it the start model still counts.
    if [[ -n "${model}" && ! -e "${STATE_DIR}/${session}.model" ]]; then
        printf '%s\n' "${model}" >"${STATE_DIR}/${session}.model"
    fi
}

on_prompt() {
    local title="$1" session="$2" model stamp
    model=$(recorded_model "${session}")
    if [[ -z "${title}" ]]; then
        stamp=$(head -n 1 "${STATE_DIR}/${session}.start" 2>/dev/null)
        [[ -n "${stamp}" ]] || stamp=$(timestamp) || return 0
        emit UserPromptSubmit "$(provider_of "${model}")-${stamp}"
        return 0
    fi
    [[ "${title}" =~ ${AUTO_NAME} ]] || return 0
    if [[ -n "${model}" && "$(provider_of "${model}")" != "${title%%-*}" ]]; then
        emit UserPromptSubmit "$(provider_of "${model}")-${title#*-}"
    fi
}

main() {
    local fields event title model session
    [[ "${CLAUDE_SESSION_NAME:-}" == "off" ]] && exit 0
    command -v jq &>/dev/null || exit 0

    # One field per line: a tab-separated read would drop an empty title.
    fields=$(jq -r '.hook_event_name // "", .session_title // "", .model // "",
        .session_id // ""' 2>/dev/null) || exit 0
    {
        read -r event
        read -r title
        read -r model
        read -r session
    } <<<"${fields}"
    # The session id becomes a file name; anything unexpected is ignored.
    [[ "${session}" =~ ^[A-Za-z0-9-]+$ ]] || exit 0

    case "${event}" in
        SessionStart) on_start "${title}" "${session}" "${model}" ;;
        UserPromptSubmit) on_prompt "${title}" "${session}" ;;
    esac
    exit 0
}

main
