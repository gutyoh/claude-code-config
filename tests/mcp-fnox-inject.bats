#!/usr/bin/env bats
# mcp-fnox-inject.bats
# Path: tests/mcp-fnox-inject.bats
#
# bin/mcp-fnox-inject starts an MCP server with only its own key, read from
# fnox in HOME. A stub fnox records how it was called.

INJECT="$BATS_TEST_DIRNAME/../bin/mcp-fnox-inject"

setup() {
    export STUB="${BATS_TEST_TMPDIR}/fnox"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}" "${BATS_TEST_TMPDIR}/repo"
    cat >"${STUB}" <<'STUB'
#!/bin/sh
printf '%s|%s\n' "$(pwd)" "$*" >>"$(dirname "$0")/calls"
[ "$1" = get ] || exit 3
case "$2" in
    BRAVE_API_KEY) echo brave-secret ;;
    EMPTY_KEY) echo "" ;;
    *) echo "no identity matched" >&2; exit 1 ;;
esac
STUB
    chmod +x "${STUB}"
    export MCP_FNOX_BIN="${STUB}"
}

@test "the server gets its own key and no other fnox secret" {
    export TAVILY_API_KEY=already-here
    run bash -c 'cd "$1" && "$2" BRAVE_API_KEY sh -c "printf %s \"\$BRAVE_API_KEY\""' _ "${BATS_TEST_TMPDIR}/repo" "${INJECT}"
    [ "$status" -eq 0 ]
    [ "$output" = "brave-secret" ]
    # Asked fnox for one key, from HOME, never `exec` (which exports every secret).
    [ "$(cat "${BATS_TEST_TMPDIR}/calls")" = "${HOME}|get BRAVE_API_KEY" ]
}

@test "a key fnox cannot decrypt stops the server with a message" {
    run "${INJECT}" TAVILY_API_KEY sh -c 'echo started'
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not decrypt TAVILY_API_KEY"* ]]
    [[ "$output" == *"mcp-fnox-inject: fnox: no identity matched"* ]]
    [[ "$output" != *started* ]]
}

@test "an empty value counts as missing" {
    run "${INJECT}" EMPTY_KEY sh -c 'echo started'
    [ "$status" -eq 1 ]
    [[ "$output" != *started* ]]
}

@test "the server replaces the helper, so signals reach it and nothing is left behind" {
    "${INJECT}" BRAVE_API_KEY sh -c 'echo $$ >"$0"; exec sleep 30' "${BATS_TEST_TMPDIR}/pid" &
    local helper=$!
    for _ in $(seq 50); do [ -s "${BATS_TEST_TMPDIR}/pid" ] && break; sleep 0.1; done
    [ "$(cat "${BATS_TEST_TMPDIR}/pid")" = "${helper}" ]
    kill "${helper}"
    wait "${helper}" 2>/dev/null || true
    run kill -0 "${helper}"
    [ "$status" -ne 0 ]
}

@test "a bad variable name or a missing command is refused" {
    run "${INJECT}" 'bad-name' true
    [ "$status" -eq 2 ]
    run "${INJECT}" BRAVE_API_KEY
    [ "$status" -eq 2 ]
}
