#!/usr/bin/env bash
# session-account.sh
# Path: .claude/hooks/session-account.sh
#
# Remembers the account each session runs as, so `claude-as -r <id>` resumes
# it as that account, and says so when a session resumes as another one.
# Claude Code keeps one login per config directory: a session's account is
# its CLAUDE_CONFIG_DIR, ~/.claude when unset. claude-as homes share the
# session history, so any account can resume any session, and nothing in
# Claude Code shows that the account changed.
#
# Events:
#   SessionStart  (every source) records the session's home; on a resume
#                 under another account than last time, shows both.
#
# The record is $XDG_STATE_HOME/claude-as/sessions, one tab-separated line
# per start: session id, home, epoch seconds. bin/claude-as reads it. Any
# error prints nothing and exits 0, so a session always starts.
#
# Usage:     Configured in .claude/settings.json (SessionStart)
# Platforms: macOS, Linux, Windows Git Bash

set -uo pipefail

readonly LEDGER="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-as/sessions"
readonly LEDGER_MAX_BYTES=1048576
readonly LEDGER_KEEP_LINES=4000

# The email <home> is signed in with; ~/.claude keeps it beside the folder.
email_of() {
    local file="$1/.claude.json"
    [[ $1 == "${HOME}/.claude" ]] && file="${HOME}/.claude.json"
    jq -r '.oauthAccount.emailAddress // empty' "${file}" 2>/dev/null
}

main() {
    local input id source home last was now
    command -v jq >/dev/null 2>&1 || return 0
    input=$(cat) || return 0
    id=$(jq -r '.session_id // empty' <<<"${input}" 2>/dev/null) || return 0
    source=$(jq -r '.source // empty' <<<"${input}" 2>/dev/null) || return 0
    [[ ${id} =~ ^[A-Za-z0-9-]+$ ]] || return 0
    home=${CLAUDE_CONFIG_DIR:-${HOME}/.claude}
    home=${home%/}

    last=""
    [[ -r ${LEDGER} ]] && last=$(awk -F'\t' -v id="${id}" '$1 == id { h = $2 } END { print h }' "${LEDGER}")
    mkdir -p "${LEDGER%/*}" 2>/dev/null || return 0
    printf '%s\t%s\t%s\n' "${id}" "${home}" "$(date +%s)" >>"${LEDGER}" 2>/dev/null || return 0
    if (($(wc -c <"${LEDGER}") > LEDGER_MAX_BYTES)); then
        tail -n "${LEDGER_KEEP_LINES}" "${LEDGER}" >"${LEDGER}.$$" && mv "${LEDGER}.$$" "${LEDGER}"
    fi

    [[ ${source} == resume && -n ${last} && ${last} != "${home}" ]] || return 0
    was=$(email_of "${last}")
    now=$(email_of "${home}")
    # Two homes signed in to one account are still that account.
    [[ -n ${was} && -n ${now} && ${was} != "${now}" ]] || return 0
    jq -nc --arg m "This session last ran as ${was} and now runs as ${now}. To go back: /exit, then claude-as ${was} -r ${id}" \
        '{systemMessage: $m}'
}

main
exit 0
