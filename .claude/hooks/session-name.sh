#!/usr/bin/env bash
# session-name.sh
# Path: .claude/hooks/session-name.sh
#
# Names each session <provider>-<YYYYMMDDTHHMMSS><zone>-<topic>, for example
# claude-20261012T141205Z-btree-page-splits. The provider and start time are
# the session's identity: the timestamp never changes, and the prefix follows
# the model to another provider. The topic is written in the background by a
# small model from the first prompt, and refreshed every few prompts.
#
# In herdr, the session's tab gets the same topic after the plan's icon, the
# icon_claude, icon_openai or icon_muse of statusline.conf, else its name.
#
# Events:
#   SessionStart      (startup) records when an untitled session started.
#   UserPromptSubmit  names the session, adds or refreshes the topic, and swaps
#                     the prefix after a provider switch. Claude Code applies a
#                     title only from this event, so a new topic shows on the
#                     next prompt; the tab shows it as soon as it is written.
#
# A session title is also the session's address for messages between
# sessions, so it stays letters, digits and hyphens, and changes rarely.
#
# Only names matching the automatic pattern are ever changed: a name set with
# /rename, --name or from the Claude app always wins, and so does a tab named
# by hand or holding several panes. Non-interactive runs are never named. Any
# error prints nothing and exits 0, so a prompt is never blocked.
#
# Environment:
#   CLAUDE_SESSION_NAME_TZ       IANA time zone for the timestamp (default UTC)
#   CLAUDE_SESSION_NAME          set to "off" to disable naming
#   CLAUDE_SESSION_NAME_TOPIC    set to "off" to name sessions without a topic
#   CLAUDE_SESSION_NAME_REFRESH  prompts between topic refreshes (default 10,
#                                0 keeps the first topic)
#   CLAUDE_SESSION_NAME_MODEL    model that writes the topic (default haiku)
#
# Usage:     Configured in .claude/settings.json (SessionStart, UserPromptSubmit)
# Platforms: macOS, Linux, Windows Git Bash

set -uo pipefail

readonly STAMP='[0-9]{8}T[0-9]{6}(Z|[+-][0-9]{4})'
readonly AUTO_NAME="^([a-z0-9]+)-(${STAMP})(-([a-z0-9-]+))?$"
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code/session-names"
readonly STATE_MAX_AGE_DAYS=30
readonly TOPIC_MAX=40 # characters of topic in the title
readonly TAB_TOPIC_MAX=24
readonly TOPIC_TEXT_MAX=600 # characters of prompt text the model reads

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
    local stamp tzdir="${TZDIR:-}"
    # NixOS keeps zones in /etc/zoneinfo; without TZDIR, date silently uses UTC.
    if [[ -z "${tzdir}" && ! -d /usr/share/zoneinfo && -d /etc/zoneinfo ]]; then
        tzdir=/etc/zoneinfo
    fi
    stamp=$(TZDIR="${tzdir}" TZ="${CLAUDE_SESSION_NAME_TZ:-UTC}" date +%Y%m%dT%H%M%S%z) || return 1
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

# Lowercase ASCII words joined by hyphens, at most <max> characters, cut at a
# word boundary: a title must stay an address other sessions can type.
slug() {
    local text="$1" max="$2" ascii
    ascii=$(printf '%s' "${text}" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null) || ascii="${text}"
    # macOS iconv spells an accent as a mark before the letter: an'alisis.
    ascii=$(printf '%s' "${ascii}" | tr -d "'\"^\`~" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-')
    ascii="${ascii#-}"
    ascii="${ascii%-}"
    while ((${#ascii} > max)) && [[ "${ascii}" == *-* ]]; do
        ascii="${ascii%-*}"
    done
    printf '%s' "${ascii:0:max}"
}

# The plan's icon from statusline.conf, else the provider's name. Claude falls
# back to the single icon too, as the statusline does: it is Claude's.
plan_icon() {
    local provider="$1" key conf icon=""
    case "${provider}" in
        claude) key=icon_claude ;;
        gpt | o[0-9]* | codex | chatgpt) key=icon_openai ;;
        muse) key=icon_muse ;;
        *) key="" ;;
    esac
    conf="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/statusline.conf"
    if [[ -n "${key}" && -f "${conf}" ]]; then
        icon=$(grep -m1 "^${key}=" "${conf}" 2>/dev/null | cut -d= -f2-)
        [[ -z "${icon}" && "${key}" == icon_claude ]] &&
            icon=$(grep -m1 "^icon=" "${conf}" 2>/dev/null | cut -d= -f2-)
    fi
    printf '%s' "${icon:-${provider}}"
}

# Names the herdr tab holding this session "<icon> <topic>", unless the tab
# holds other panes or carries a name this hook did not give it.
sync_tab() {
    local session="$1" provider="$2" topic="$3" herdr tab label panes last name
    [[ "${HERDR_ENV:-}" == "1" && -n "${HERDR_TAB_ID:-}" && -n "${topic}" ]] || return 0
    herdr="${HERDR_BIN_PATH:-herdr}"
    command -v "${herdr}" &>/dev/null || return 0
    tab=$(timeout 5 "${herdr}" tab get "${HERDR_TAB_ID}" 2>/dev/null) || return 0
    label=$(jq -r '.result.tab.label // empty' <<<"${tab}" 2>/dev/null)
    panes=$(jq -r '.result.tab.pane_count // 0' <<<"${tab}" 2>/dev/null)
    [[ "${panes}" == "1" ]] || return 0
    last=$(head -n 1 "${STATE_DIR}/${session}.tab" 2>/dev/null)
    [[ "${label}" =~ ^[0-9]+$ || (-n "${last}" && "${label}" == "${last}") ]] || return 0
    name="$(plan_icon "${provider}") $(slug "${topic}" "${TAB_TOPIC_MAX}")"
    [[ "${name}" == "${label}" ]] && return 0
    # herdr takes every argument after the id as the label, "--" included.
    timeout 5 "${herdr}" tab rename "${HERDR_TAB_ID}" "${name}" >/dev/null 2>&1 || return 0
    printf '%s\n' "${name}" >"${STATE_DIR}/${session}.tab"
}

# The last few prompts typed in the session, for a refreshed topic. Tool
# results share the user role but carry arrays, so only strings count.
recent_prompts() {
    [[ -f "$1" ]] || return 0
    tail -n 2000 "$1" 2>/dev/null | jq -r 'select(.type == "user")
        | .message.content | select(type == "string")' 2>/dev/null | tail -n 12
}

# Asks a small model for the topic, without hooks, tools, MCP servers or a
# saved transcript, and outside herdr: the run must not name, report or log a
# session of its own. Falls back to the text's first words.
write_topic() {
    local session="$1" provider="$2" text="$3" answer topic lock
    lock="${STATE_DIR}/${session}.topic.lock"
    if [[ -d "${lock}" && -n "$(find "${lock}" -mmin +2 2>/dev/null)" ]]; then
        rmdir "${lock}" 2>/dev/null
    fi
    mkdir "${lock}" 2>/dev/null || return 0
    answer=$(env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID \
        -u HERDR_SOCKET_PATH CLAUDE_SESSION_NAME=off \
        timeout 60 claude -p --model "${CLAUDE_SESSION_NAME_MODEL:-haiku}" \
        --setting-sources "" --strict-mcp-config --tools "" --no-session-persistence \
        "Name the topic of this coding session as 2 to 4 lowercase ASCII words joined by hyphens, and reply with nothing else. Use the language of the text. Text: ${text:0:${TOPIC_TEXT_MAX}}" \
        </dev/null 2>/dev/null | head -n 1)
    topic=$(slug "${answer}" "${TOPIC_MAX}")
    [[ -n "${topic}" ]] || topic=$(slug "$(printf '%s' "${text}" | tr -s '[:space:]' ' ' | cut -d' ' -f1-4)" "${TOPIC_MAX}")
    if [[ -n "${topic}" ]]; then
        printf '%s\n' "${topic}" >"${STATE_DIR}/${session}.topic.$$" &&
            mv -f "${STATE_DIR}/${session}.topic.$$" "${STATE_DIR}/${session}.topic"
        sync_tab "${session}" "${provider}" "${topic}"
    fi
    rmdir "${lock}" 2>/dev/null
}

# Windows Git Bash kills a backgrounded job when the hook exits, so there the
# topic is written before the prompt goes on.
spawn_topic() {
    [[ "${CLAUDE_SESSION_NAME_TOPIC:-}" == "off" ]] && return 0
    [[ -n "${3// /}" ]] || return 0
    command -v claude &>/dev/null || return 0
    case "$(uname -s)" in
        MSYS* | MINGW* | CYGWIN*) write_topic "$@" ;;
        *)
            (write_topic "$@") </dev/null >/dev/null 2>&1 &
            disown 2>/dev/null || true
            ;;
    esac
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
    local title="$1" session="$2" prompt="$3" transcript="$4"
    local model provider stamp topic count refresh want
    mkdir -p "${STATE_DIR}" 2>/dev/null || return 0
    model=$(recorded_model "${session}")

    if [[ -z "${title}" ]]; then
        stamp=$(head -n 1 "${STATE_DIR}/${session}.start" 2>/dev/null)
        [[ -n "${stamp}" ]] || stamp=$(timestamp) || return 0
        provider=$(provider_of "${model}")
        emit UserPromptSubmit "${provider}-${stamp}"
        printf '1\n' >"${STATE_DIR}/${session}.prompts"
        spawn_topic "${session}" "${provider}" "${prompt}"
        return 0
    fi

    [[ "${title}" =~ ${AUTO_NAME} ]] || return 0
    provider="${BASH_REMATCH[1]}"
    stamp="${BASH_REMATCH[2]}"
    [[ -n "${model}" ]] && provider=$(provider_of "${model}")
    topic=$(head -n 1 "${STATE_DIR}/${session}.topic" 2>/dev/null)
    [[ -n "${topic}" ]] || topic="${BASH_REMATCH[5]}"

    want="${provider}-${stamp}${topic:+-${topic}}"
    # Claude Code appends a suffix when another live session holds the name;
    # re-sending ours would trade it for a new suffix on every prompt.
    if [[ "${title}" != "${want}" && "${title}" != "${want}-"* ]]; then
        emit UserPromptSubmit "${want}"
    fi
    # Detached from the hook's output, which Claude Code reads to the end.
    sync_tab "${session}" "${provider}" "${topic}" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true

    count=$(($(head -n 1 "${STATE_DIR}/${session}.prompts" 2>/dev/null || echo 0) + 1))
    printf '%s\n' "${count}" >"${STATE_DIR}/${session}.prompts"
    refresh="${CLAUDE_SESSION_NAME_REFRESH:-10}"
    if [[ "${refresh}" =~ ^[0-9]+$ ]] && ((refresh > 0 && count % refresh == 0)); then
        spawn_topic "${session}" "${provider}" \
            "$(recent_prompts "${transcript}" | tail -c "${TOPIC_TEXT_MAX}") ${prompt}"
    fi
}

main() {
    local fields event title model session prompt transcript
    [[ "${CLAUDE_SESSION_NAME:-}" == "off" ]] && exit 0
    # Only interactive sessions: a `claude -p` or SDK run, often started by an
    # agent inside another session, is not in the picker and must not rename.
    [[ "${CLAUDE_CODE_ENTRYPOINT:-cli}" == "cli" ]] || exit 0
    command -v jq &>/dev/null || exit 0

    # One field per line: a tab-separated read would drop an empty title. The
    # prompt is last and may span lines.
    fields=$(jq -r '.hook_event_name // "", .session_title // "", .model // "",
        .session_id // "", .transcript_path // "", (.prompt // "" | gsub("\n"; " "))' 2>/dev/null) || exit 0
    {
        read -r event
        read -r title
        read -r model
        read -r session
        read -r transcript
        read -r prompt
    } <<<"${fields}"
    # The session id becomes a file name; anything unexpected is ignored.
    [[ "${session}" =~ ^[A-Za-z0-9-]+$ ]] || exit 0

    case "${event}" in
        SessionStart) on_start "${title}" "${session}" "${model}" ;;
        UserPromptSubmit) on_prompt "${title}" "${session}" "${prompt}" "${transcript}" ;;
    esac
    exit 0
}

main
