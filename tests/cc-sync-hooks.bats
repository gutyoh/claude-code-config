#!/usr/bin/env bats
# cc-sync-hooks.bats
# Path: tests/cc-sync-hooks.bats
#
# bats-core tests for the SessionStart/SessionEnd claude-sync hooks
# (cc-sync-pull.sh and cc-sync-push.sh).
#
# Validates:
#   - both scripts exist and are executable
#   - both scripts no-op silently when claude-sync is not on PATH
#   - both scripts consume stdin (Claude Code feeds JSON to hooks via stdin)
#   - settings.json template wires SessionStart -> cc-sync-pull
#                              and SessionEnd   -> cc-sync-push
#
# Run: bats tests/cc-sync-hooks.bats
#      make test

SETTINGS="$BATS_TEST_DIRNAME/../.claude/settings.json"
HOOKS_DIR="$BATS_TEST_DIRNAME/../.claude/hooks"
PULL_SCRIPT="$HOOKS_DIR/cc-sync-pull.sh"
PUSH_SCRIPT="$HOOKS_DIR/cc-sync-push.sh"

setup() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# --- Hook scripts: presence and executability ---

@test "cc-sync-pull.sh exists and is executable" {
    [ -f "$PULL_SCRIPT" ]
    [ -x "$PULL_SCRIPT" ]
}

@test "cc-sync-push.sh exists and is executable" {
    [ -f "$PUSH_SCRIPT" ]
    [ -x "$PUSH_SCRIPT" ]
}

# --- Hook scripts: graceful no-op when claude-sync absent ---

@test "cc-sync-pull.sh exits 0 when claude-sync is not installed" {
    PATH="/usr/bin:/bin" run bash -c "echo '{}' | '$PULL_SCRIPT'"
    [ "$status" -eq 0 ]
}

@test "cc-sync-push.sh exits 0 when claude-sync is not installed" {
    PATH="/usr/bin:/bin" run bash -c "echo '{}' | '$PUSH_SCRIPT'"
    [ "$status" -eq 0 ]
}

# --- Settings template wiring ---

@test "settings.json template wires SessionStart to cc-sync-pull.sh" {
    local cmd
    cmd=$(jq -r '
        .hooks.SessionStart // []
        | .[].hooks[]?
        | .command // empty
    ' "$SETTINGS" | grep -F "cc-sync-pull.sh" | head -1)
    [ "$cmd" = "~/.claude/hooks/cc-sync-pull.sh" ]
}

@test "settings.json template wires SessionEnd to cc-sync-push.sh" {
    local cmd
    cmd=$(jq -r '
        .hooks.SessionEnd // []
        | .[].hooks[]?
        | .command // empty
    ' "$SETTINGS" | grep -F "cc-sync-push.sh" | head -1)
    [ "$cmd" = "~/.claude/hooks/cc-sync-push.sh" ]
}

@test "SessionStart hook command uses ~/ absolute path" {
    local cmd
    cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$SETTINGS")
    [[ "$cmd" == "~/"* ]]
}

@test "SessionEnd hook command uses ~/ absolute path" {
    local cmd
    cmd=$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$SETTINGS")
    [[ "$cmd" == "~/"* ]]
}

@test "SessionStart entries omit matcher (per official hooks reference)" {
    # SessionStart and SessionEnd do not use matchers — their filtering is
    # done via the `source` / `reason` fields, not a tool matcher.
    # Including a matcher does not break Claude Code, but the convention
    # in the official docs is to omit it.
    local with_matcher
    with_matcher=$(jq '
        .hooks.SessionStart // []
        | map(select(has("matcher")))
        | length
    ' "$SETTINGS")
    [ "$with_matcher" -eq 0 ]
}

@test "SessionEnd entries omit matcher (per official hooks reference)" {
    local with_matcher
    with_matcher=$(jq '
        .hooks.SessionEnd // []
        | map(select(has("matcher")))
        | length
    ' "$SETTINGS")
    [ "$with_matcher" -eq 0 ]
}
