#!/usr/bin/env bats
# enforce-git-pull-rebase.bats
# Path: tests/enforce-git-pull-rebase.bats
#
# bats-core tests for the enforce-git-pull-rebase.sh PreToolUse hook.
# Covers the rewrite logic and the conflicting-flag edge cases (--ff-only,
# --no-rebase, --rebase=false) that must NOT be rewritten.
#
# Run: bats tests/enforce-git-pull-rebase.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/enforce-git-pull-rebase.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq is required for enforce-git-pull-rebase tests"
}

# Helper: run the hook against a bash command, capture stdout.
# Sets: $output (hook's JSON response or empty), $status (exit code).
run_hook() {
    local cmd="$1"
    local input
    input=$(jq -n --arg c "$cmd" '{ tool_name: "Bash", tool_input: { command: $c } }')
    run bash -c "printf %s '$input' | bash '$HOOK'"
}

# Helper: extract rewritten command from $output, empty if unchanged
rewritten() {
    echo "$output" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null
}

# ============================================================================
# Basic functionality
# ============================================================================

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "plain 'git pull' is rewritten to include --rebase" {
    run_hook "git pull"
    [ "$status" -eq 0 ]
    [ "$(rewritten)" = "git pull --rebase" ]
}

@test "'git pull origin main' places --rebase BEFORE positionals" {
    run_hook "git pull origin main"
    [ "$status" -eq 0 ]
    [ "$(rewritten)" = "git pull --rebase origin main" ]
}

# ============================================================================
# Pass-through (no rewrite)
# ============================================================================

@test "'git pull --rebase' is NOT rewritten (already has --rebase)" {
    run_hook "git pull --rebase"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "'git pull --rebase=true' is NOT rewritten" {
    run_hook "git pull --rebase=true"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "'git pull --rebase=false' is NOT rewritten (explicit opt-out)" {
    # Regression test: user explicitly disabled rebase; hook must not override.
    run_hook "git pull --rebase=false"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "'git pull --no-rebase' is NOT rewritten (explicit opt-out)" {
    # Regression test: explicit opt-out must be respected.
    run_hook "git pull --no-rebase"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "'git pull --ff-only' is NOT rewritten (flag conflicts with --rebase)" {
    # Regression test for the bug where the hook rewrote `git pull --ff-only`
    # into `git pull --rebase --ff-only`, which Git rejects.
    run_hook "git pull --ff-only"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "'git pull --ff-only origin main' is NOT rewritten" {
    run_hook "git pull --ff-only origin main"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "'git push' is NOT rewritten (non-pull command)" {
    run_hook "git push origin main"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "'git fetch' is NOT rewritten" {
    run_hook "git fetch origin"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

@test "non-git command is NOT rewritten" {
    run_hook "ls -la"
    [ "$status" -eq 0 ]
    [ -z "$(rewritten)" ]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "empty stdin exits 0 with no output" {
    run bash -c "echo '' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "missing tool_input.command exits 0 with no output" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{}}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "rewrite preserves additional flags" {
    run_hook "git pull --verbose"
    [ "$status" -eq 0 ]
    [ "$(rewritten)" = "git pull --rebase --verbose" ]
}

@test "rewrite result includes correct hookSpecificOutput structure" {
    run_hook "git pull"
    [ "$status" -eq 0 ]
    local event decision reason
    event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName // empty')
    decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')
    reason=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
    [ "$event" = "PreToolUse" ]
    [ "$decision" = "allow" ]
    [ -n "$reason" ]
}

# ============================================================================
# Performance
# ============================================================================

@test "hook completes in < 500ms on fast path (non-git command)" {
    local start end elapsed threshold _uname
    start=$("${_PY}" -c "import time; print(int(time.time() * 1000))")
    run_hook "ls -la"
    end=$("${_PY}" -c "import time; print(int(time.time() * 1000))")
    elapsed=$((end - start))
    threshold=500
    _uname="$(uname -s)"
    if [[ "$_uname" == MINGW* || "$_uname" == MSYS* || "$_uname" == CYGWIN* || "$_uname" == *_NT* ]]; then
        threshold=5000
    fi
    [ "$elapsed" -lt "$threshold" ]
}
