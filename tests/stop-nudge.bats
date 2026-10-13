#!/usr/bin/env bats
# stop-nudge.bats
# Path: tests/stop-nudge.bats
#
# Tests for the stop-nudge.sh Stop hook: a listed model that ends a turn by
# announcing a step it never took gets one nudge; everything else stops.
#
# Run: bats tests/stop-nudge.bats
#      just test

bats_require_minimum_version 1.5.0

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/stop-nudge.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd jq
    isolate_home
    unset STOP_NUDGE STOP_NUDGE_MODELS
    TX="${BATS_TEST_TMPDIR}/session.jsonl"
    assistant muse-wonder-full-1.0 >"${TX}"
}

# assistant <model> [tool]: one transcript entry from that model.
assistant() {
    if [[ ${2:-} == tool ]]; then
        jq -nc --arg m "$1" '{type: "assistant", message: {model: $m, content: [{type: "tool_use", name: "Bash"}]}}'
    else
        jq -nc --arg m "$1" '{type: "assistant", message: {model: $m, content: [{type: "text", text: "x"}]}}'
    fi
}

# stop <message> [active]: runs the hook; $nudged is 1 when it asked to go on.
stop() {
    local body
    body=$(jq -nc --arg m "$1" --arg t "${TX}" --argjson a "${2:-false}" \
        '{hook_event_name: "Stop", last_assistant_message: $m, transcript_path: $t, stop_hook_active: $a}')
    run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" "${body}"
    nudged=0
    [[ ${output} == *"[stop-nudge]"* ]] && nudged=1
    return 0
}

@test "a turn that ends announcing a step is nudged" {
    for message in \
        "Notes start with “alpha” and the CSV has 137 lines — writing summary.md now." \
        "Extraigo la cohorte madura a un parquet local y construyo el panel:" \
        "Voy a ello — el túnel ya está activo, así que pruebo la LAN a través de él." \
        "Listed the files. Next I'll count the CSV lines."; do
        stop "${message}"
        [ "${status}" -eq 0 ]
        [ "${nudged}" -eq 1 ] || { echo "not nudged: ${message}"; return 1; }
    done
    jq -e '.hookSpecificOutput.hookEventName == "Stop"' <<<"${output}"
}

@test "a finished answer, a question or a wait for the person stops" {
    for message in \
        "Done. summary.md has lines=137 and first=alpha." \
        "Listo, el panel quedó en panel.parquet." \
        "¿Quieres que lo aplique también en la Mac?" \
        "Say go (or point me at a different step) and I'll start." \
        "Espero la posición del otro Claude y sigo después." \
        "Dime si sigo con el PR ahora." \
        ""; do
        stop "${message}"
        [ "${nudged}" -eq 0 ] || { echo "nudged: ${message}"; return 1; }
    done
}

@test "the last sentence decides, and code blocks are ignored" {
    stop $'I will write it now.\n\nDone: the file is written.'
    [ "${nudged}" -eq 0 ]
    stop $'All checks passed.\n```sh\nnow run: make\n```\nNothing left to do.'
    [ "${nudged}" -eq 0 ]
}

@test "models not listed are never nudged" {
    assistant claude-opus-5-5 >"${TX}"
    stop "Starting PR C now."
    [ "${nudged}" -eq 0 ]
    STOP_NUDGE_MODELS="claude-* gpt-*" stop "Starting PR C now."
    [ "${nudged}" -eq 1 ]
}

@test "after a nudge only a tool call re-arms it" {
    printf '%s\n' "$(assistant muse-spark-1.3)" \
        '{"type":"user","message":{"content":"Stop hook feedback: [stop-nudge] Your last message announced a next step"}}' \
        "$(assistant muse-spark-1.3)" >"${TX}"
    stop "Writing the file now." true
    [ "${nudged}" -eq 0 ]
    assistant muse-spark-1.3 tool >>"${TX}"
    stop "Writing the file now." true
    [ "${nudged}" -eq 1 ]
}

@test "STOP_NUDGE=off, no transcript or no message: it stops" {
    STOP_NUDGE=off stop "Writing the file now."
    [ "${nudged}" -eq 0 ]
    TX="${BATS_TEST_TMPDIR}/missing.jsonl" stop "Writing the file now."
    [ "${nudged}" -eq 0 ]
    run bash -c 'printf "%s" "{}" | bash "$1"' _ "$HOOK"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "the hook is registered as a Stop hook" {
    jq -e '.hooks.Stop[].hooks[] | select(.command == "~/.claude/hooks/stop-nudge.sh")' \
        "$BATS_TEST_DIRNAME/../.claude/settings.json"
}
