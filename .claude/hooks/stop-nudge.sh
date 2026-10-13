#!/usr/bin/env bash
# stop-nudge.sh — Stop hook: a turn that ends by announcing a next step, with
# no tool call, gets one nudge to take that step.
# Path: .claude/hooks/stop-nudge.sh
#
# Some models routed into Claude Code (Muse Wonder Full measured most) end a
# turn with "…writing summary.md now." and never call the tool. Claude stops
# on purpose to wait for the person, so only the listed models are nudged.
#
# Env:
#   STOP_NUDGE=off          disable
#   STOP_NUDGE_MODELS       space-separated globs (default "muse-*")
#   STOP_NUDGE_MAX          nudges per session at most (default 6)
#
# A nudge goes back as Stop hook feedback (additionalContext). Another one is
# given only after the model has called a tool since the last; Claude Code's
# own cap (8 continuations in a row) stays the backstop. A turn that waits on
# background work or a scheduled prompt is never nudged: its "I'll report
# when…" is a promise, not a step left out. jq runs twice at
# most: through a version manager's shim each start costs a quarter second.

set -uo pipefail

input=$(cat)
[[ ${STOP_NUDGE:-on} == off ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

transcript=$(jq -r '.transcript_path // empty' <<<"${input}" 2>/dev/null)
transcript=${transcript/#\~/${HOME}}
[[ -n ${transcript} && -r ${transcript} ]] || exit 0

# The session's model as the statusline records it; the transcript may not
# hold the first turn's answer yet when Stop fires.
session=$(jq -r '.session_id // empty' <<<"${input}" 2>/dev/null)
recorded=""
record="${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code/session-names/${session}.model"
[[ -n ${session} && -r ${record} ]] && recorded=$(head -n 1 "${record}")

# Without a record (a -p run has no statusline), the first turn's answer may
# reach the transcript just after Stop fires: wait for it, 2 seconds at most.
if [[ -z ${recorded} ]]; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        tail -n 400 "${transcript}" | grep -q '"type":"assistant"' && break
        sleep 0.2
    done
fi

# A session nudged STOP_NUDGE_MAX times is left alone from then on.
max=${STOP_NUDGE_MAX:-6}
[[ ${max} =~ ^[0-9]+$ ]] || max=6
(($(grep -c '\[stop-nudge\] Your last message' "${transcript}" 2>/dev/null) >= max)) && exit 0

# Globs become one anchored regex: "muse-* gpt-5*" -> ^(muse-.*|gpt-5.*)$
read -ra globs <<<"${STOP_NUDGE_MODELS:-muse-*}"
pattern=$(printf '%s|' "${globs[@]}" | sed -e 's/[.+^$()]/\\&/g' -e 's/\*/.*/g' -e 's/?/./g')
pattern="^(${pattern%|})$"

tail -n 400 "${transcript}" | jq -rRn --argjson in "${input}" --arg pattern "${pattern}" --arg recorded "${recorded}" '
    "[stop-nudge]" as $mark
    | [inputs | fromjson? | select(type == "object")] as $tail
    | (if $recorded != "" then $recorded
       else ($tail | map(select(.type == "assistant") | .message.model // empty) | last // "") end) as $model
    # One nudge per stretch of work: after a nudge, only a tool call re-arms it.
    | ($tail | map(tostring | contains($mark)) | rindex(true)) as $at
    | (if ($in.stop_hook_active // false) | not then true
       elif $at == null then true
       else ($tail[$at + 1:] | map(select(.type == "assistant") | .message.content[]?
             | select(.type == "tool_use")) | length > 0) end) as $armed
    # The last sentence, code blocks dropped: does it announce a step not taken?
    | (($in.last_assistant_message // "") | gsub("```[\\s\\S]*?```"; " ")
        | split("\n") | map(select(test("\\S"))) | last // "") as $line
    | ($line | [splits("(?<=[.!?])\\s+")] | map(select(test("\\S"))) | last // ""
        | gsub("^\\s+|\\s+$"; "")) as $s
    | (if $s == "" or ($s | test("\\?\\s*$")) then false
       elif ($s | test("(?i)\\b(say go|tell me|let me know|if you|when you|your call|wait(ing)? for|unless|dime|av[ií]same|si quieres|cuando (me )?digas|salvo que|espero|confirm)")) then false
       elif ($s | test(":\\s*$")) then true
       else ($s | length) < 200
         and ($s | test("(?i)\\b(now|next|let me|i.ll|i will|going to|about to|voy a|vamos a|ahora|a continuaci[oó]n|procedo|sigo con|enseguida|paso a|empiezo|comienzo)\\b"))
         and ($s | test("(?i)\\b(done|listo|termin[eé]|completed|finished|hecho)\\b(?!\\.\\w)") | not)
       end) as $announces
    | ((($in.background_tasks // []) + ($in.session_crons // [])) | length == 0) as $idle
    | select(($model | test($pattern)) and $armed and $idle and $announces)
    | {hookSpecificOutput: {hookEventName: "Stop",
        additionalContext: ($mark + " Your last message announced a next step, but the turn ended without a tool call. If that step is still needed, take it now with your tools; if you are waiting for the person, say so in one line.")}}
' 2>/dev/null
exit 0
