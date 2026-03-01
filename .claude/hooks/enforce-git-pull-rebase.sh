#!/usr/bin/env bash
# enforce-git-pull-rebase.sh
# Path: .claude/hooks/enforce-git-pull-rebase.sh
#
# Claude Code PreToolUse hook that automatically adds --rebase to git pull
# commands, ensuring a clean linear history.
#
# This hook intercepts Bash tool calls, checks if the command is `git pull`
# without --rebase, and modifies it to include --rebase.
#
# Usage:     Configured in .claude/settings.json as a PreToolUse hook
# Platforms: macOS, Linux

set -euo pipefail

# --- Main ---

main() {
    # Read the tool input JSON from stdin
    local input
    input=$(cat)

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        # jq not available, pass through unchanged
        exit 0
    fi

    # Extract the command from tool_input
    # JSON structure: { "tool_input": { "command": "..." }, ... }
    local cmd
    cmd=$(echo "${input}" | jq -r '.tool_input.command // empty')

    # If no command found, pass through unchanged
    if [[ -z "${cmd}" ]]; then
        exit 0
    fi

    # Check if this is a git pull command without --rebase
    if [[ "${cmd}" =~ git[[:space:]]+pull ]] && [[ ! "${cmd}" =~ --rebase ]]; then
        # Add --rebase after "git pull"
        # Handles: git pull -> git pull --rebase
        #          git pull origin main -> git pull --rebase origin main
        local modified_cmd
        modified_cmd=$(echo "${cmd}" | sed -E 's/(git[[:space:]]+pull)/\1 --rebase/')

        # Return structured output per official hookSpecificOutput format
        jq -n \
            --arg cmd "${modified_cmd}" \
            --arg reason "Added --rebase for clean linear history" \
            '{
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: "allow",
                    permissionDecisionReason: $reason,
                    updatedInput: { command: $cmd }
                }
            }'
        exit 0
    fi

    # Pass through unchanged for all other commands (no output needed)
    exit 0
}

main "$@"
