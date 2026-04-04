#!/usr/bin/env bats
# settings-hook-paths.bats
# Path: tests/settings-hook-paths.bats
#
# bats-core tests that certify every hook command path in settings.json
# resolves to an executable file from ANY project directory.
#
# This catches the bug where ./ (project-relative) paths in the global
# ~/.claude/settings.json only work inside claude-code-config itself,
# silently breaking hooks in every other project.
#
# Run: bats tests/settings-hook-paths.bats
#      make test

SETTINGS="$BATS_TEST_DIRNAME/../.claude/settings.json"

setup() {
    # Ensure jq is available (required by these tests)
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# --- Schema validation ---

@test "settings.json exists and is valid JSON" {
    [ -f "$SETTINGS" ]
    jq empty "$SETTINGS"
}

@test "settings.json has PreToolUse hooks array" {
    local count
    count=$(jq '.hooks.PreToolUse | length' "$SETTINGS")
    [ "$count" -gt 0 ]
}

@test "settings.json has Stop hooks array" {
    local count
    count=$(jq '.hooks.Stop | length' "$SETTINGS")
    [ "$count" -gt 0 ]
}

# --- No relative ./ paths in global settings ---

@test "no hook commands use ./ relative paths" {
    local bad_paths
    bad_paths=$(jq -r '
        [.hooks | to_entries[] | .value[] | .hooks[]? | .command // empty]
        | map(select(startswith("./")))
        | .[]
    ' "$SETTINGS" 2>/dev/null || true)

    if [ -n "$bad_paths" ]; then
        echo "ERROR: Found ./ relative paths in settings.json hooks:"
        echo "$bad_paths"
        echo ""
        echo "Global settings (~/.claude/settings.json) must use ~/ paths"
        echo "so hooks resolve via the ~/.claude/hooks symlink from any project."
        false
    fi
}

@test "all hook commands use ~/ absolute paths" {
    local all_commands
    all_commands=$(jq -r '
        [.hooks | to_entries[] | .value[] | .hooks[]? | .command // empty]
        | .[]
    ' "$SETTINGS")

    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        if [[ "$cmd" != "~/"* ]]; then
            echo "ERROR: Hook command does not use ~/ path: $cmd"
            false
        fi
    done <<< "$all_commands"
}

# --- All hook scripts resolve and are executable ---

@test "all PreToolUse hook scripts exist and are executable" {
    local commands
    commands=$(jq -r '
        .hooks.PreToolUse[]
        | .hooks[]?
        | .command // empty
    ' "$SETTINGS")

    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        # Expand ~ to $HOME
        local expanded="${cmd/#\~/$HOME}"
        if [ ! -f "$expanded" ]; then
            echo "MISSING: $cmd (expanded: $expanded)"
            false
        fi
        if [ ! -x "$expanded" ]; then
            echo "NOT EXECUTABLE: $cmd (expanded: $expanded)"
            false
        fi
    done <<< "$commands"
}

@test "all Stop hook scripts exist and are executable" {
    local commands
    commands=$(jq -r '
        .hooks.Stop[]
        | .hooks[]?
        | .command // empty
    ' "$SETTINGS")

    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        local expanded="${cmd/#\~/$HOME}"
        if [ ! -f "$expanded" ]; then
            echo "MISSING: $cmd (expanded: $expanded)"
            false
        fi
        if [ ! -x "$expanded" ]; then
            echo "NOT EXECUTABLE: $cmd (expanded: $expanded)"
            false
        fi
    done <<< "$commands"
}

# --- Hooks resolve from an arbitrary temp directory (the real test) ---

@test "all hook scripts resolve from a random temp directory (simulates other projects)" {
    local tmpdir
    tmpdir=$(mktemp -d)

    local all_commands
    all_commands=$(jq -r '
        [.hooks | to_entries[] | .value[] | .hooks[]? | .command // empty]
        | .[]
    ' "$SETTINGS")

    local failures=0
    while IFS= read -r cmd; do
        [ -z "$cmd" ] && continue
        local expanded="${cmd/#\~/$HOME}"
        # Test from the temp directory — this is what fails with ./ paths
        if ! (cd "$tmpdir" && [ -x "$expanded" ]); then
            echo "FAILS FROM TMPDIR: $cmd"
            failures=$((failures + 1))
        fi
    done <<< "$all_commands"

    rm -rf "$tmpdir"

    if [ "$failures" -gt 0 ]; then
        echo ""
        echo "$failures hook(s) do not resolve from an arbitrary directory."
        echo "This means they will fail in any project that is not claude-code-config."
        false
    fi
}

# --- statusLine and fileSuggestion paths ---

@test "statusLine command uses ~/ path and script exists" {
    local cmd
    cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS")
    [ -n "$cmd" ]
    [[ "$cmd" == "~/"* ]]
    local expanded="${cmd/#\~/$HOME}"
    [ -x "$expanded" ]
}

# --- Every hook has required fields ---

@test "every PreToolUse entry has matcher and hooks array" {
    local invalid
    invalid=$(jq -r '
        .hooks.PreToolUse[]
        | select(.matcher == null or .hooks == null or (.hooks | type) != "array")
        | .matcher // "null"
    ' "$SETTINGS" 2>/dev/null || true)

    if [ -n "$invalid" ]; then
        echo "Invalid PreToolUse entries (missing matcher or hooks): $invalid"
        false
    fi
}

@test "every hook entry has type and command fields" {
    local invalid
    invalid=$(jq -r '
        [.hooks | to_entries[] | .value[] | .hooks[]?]
        | map(select(.type == null or .command == null))
        | length
    ' "$SETTINGS")

    [ "$invalid" -eq 0 ]
}

# --- Symlink chain validation ---

@test "~/.claude/hooks is a symlink to the repo hooks directory" {
    local hooks_link="$HOME/.claude/hooks"
    [ -L "$hooks_link" ] || skip "~/.claude/hooks is not a symlink (run ./setup.sh to create it)"

    local repo_hooks="$BATS_TEST_DIRNAME/../.claude/hooks"
    local repo_hooks_real
    repo_hooks_real=$(cd "$repo_hooks" && pwd -P)

    local link_target
    link_target=$(readlink "$hooks_link")
    local link_real
    link_real=$(cd "$hooks_link" && pwd -P)

    [ "$link_real" = "$repo_hooks_real" ] || {
        echo "~/.claude/hooks points to: $link_target"
        echo "Expected to resolve to:    $repo_hooks_real"
        echo "Actual resolves to:        $link_real"
        false
    }
}

@test "~/.claude/scripts is a symlink to the repo scripts directory" {
    local scripts_link="$HOME/.claude/scripts"
    [ -L "$scripts_link" ] || skip "~/.claude/scripts is not a symlink (run ./setup.sh to create it)"

    local repo_scripts="$BATS_TEST_DIRNAME/../.claude/scripts"
    local repo_scripts_real
    repo_scripts_real=$(cd "$repo_scripts" && pwd -P)

    local link_real
    link_real=$(cd "$scripts_link" && pwd -P)

    [ "$link_real" = "$repo_scripts_real" ] || {
        echo "~/.claude/scripts symlink mismatch"
        false
    }
}
