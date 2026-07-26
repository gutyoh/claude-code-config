#!/usr/bin/env bats
# smoke.bats
# Path: tests/smoke.bats
#
# End-to-end checks that the installer actually runs on a clean machine.
# The unit lane mocks aggressively and can stay green while the real entry
# point is broken; these drive setup.sh itself against a throwaway HOME.
#
# Deliberately narrow: no MCP servers, no network, no agents. The question is
# "does the installer run to completion and leave a usable config", not "is
# every feature correct" — the unit and integration lanes answer that.
#
# Run: bats tests/smoke.bats
#      make smoke

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    SETUP="${REPO_DIR}/setup.sh"
}

# bats test_tags=smoke
@test "setup.sh --help exits 0 and prints usage" {
    run "$SETUP" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: setup.sh"* ]]
}

# bats test_tags=smoke
@test "setup.sh rejects an unknown flag" {
    run "$SETUP" --definitely-not-a-flag
    [ "$status" -ne 0 ]
}

# bats test_tags=smoke
@test "setup.sh --minimal completes against an empty HOME" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ]
    [[ "$output" == *"Setup complete!"* ]]
}

# bats test_tags=smoke
@test "setup.sh --minimal produces valid settings.json" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ]

    local settings="${HOME}/.claude/settings.json"
    [ -f "$settings" ]
    jq -e '.' "$settings" >/dev/null
}

# bats test_tags=smoke
@test "setup.sh --minimal installs no claude-sync hooks" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ]

    local settings="${HOME}/.claude/settings.json"
    local hooks
    hooks=$(jq -r '[.hooks.SessionStart // [], .hooks.SessionEnd // []] | flatten | length' "$settings")
    [ "$hooks" -eq 0 ]
}

# bats test_tags=smoke
@test "setup.sh is idempotent across two runs" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ]
    run "$SETUP" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ]

    jq -e '.' "${HOME}/.claude/settings.json" >/dev/null
}

# bats test_tags=smoke
@test "setup.sh with claude-sync wires bounded hooks end to end" {
    require_cmd python3
    require_cmd jq
    stub_bin claude-sync 'exit 0'

    run "$SETUP" -y --minimal --with-claude-sync --no-opencode
    [ "$status" -eq 0 ]

    local settings="${HOME}/.claude/settings.json"
    local timeout
    timeout=$(jq -r '
        .hooks.SessionStart[]?.hooks[]?
        | select(.command | test("cc-sync-pull"))
        | .timeout // "MISSING"
    ' "$settings")
    [ "$timeout" != "MISSING" ]
    [ "$timeout" -gt 0 ]
}

# bats test_tags=smoke
@test "the shipped settings.json template is valid JSON" {
    require_cmd jq
    jq -e '.' "${REPO_DIR}/.claude/settings.json" >/dev/null
}

# bats test_tags=smoke
@test "every shipped hook script is syntactically valid bash" {
    local f
    for f in "${REPO_DIR}"/.claude/hooks/*.sh; do
        [ -f "$f" ] || continue
        run bash -n "$f"
        [ "$status" -eq 0 ] || {
            echo "syntax error in $f"
            false
        }
    done
}
