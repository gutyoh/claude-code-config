#!/bin/bash
# =============================================================================
# enforce-git-pull-rebase.sh
# =============================================================================
# Claude Code PreToolUse hook that automatically adds --rebase to git pull
# commands, ensuring a clean linear history.
#
# This hook intercepts Bash tool calls, checks if the command is `git pull`
# without --rebase, and modifies it to include --rebase.
#
# Usage: Configured in .claude/settings.json as a PreToolUse hook
# =============================================================================

set -euo pipefail

# Read the tool input JSON from stdin
INPUT=$(cat)

# Check if jq is available
if ! command -v jq &> /dev/null; then
    # jq not available, pass through unchanged
    echo "$INPUT"
    exit 0
fi

# Extract the command from tool_input
# The JSON structure is: { "tool_input": { "command": "..." }, ... }
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If no command found, pass through unchanged
if [[ -z "$COMMAND" ]]; then
    echo "$INPUT"
    exit 0
fi

# Check if this is a git pull command
if [[ "$COMMAND" =~ git[[:space:]]+pull ]]; then
    # Check if --rebase is NOT already present
    if [[ ! "$COMMAND" =~ --rebase ]]; then
        # Add --rebase after "git pull"
        # Handle various formats:
        #   git pull                    -> git pull --rebase
        #   git pull origin main        -> git pull --rebase origin main
        #   git pull origin develop     -> git pull --rebase origin develop
        MODIFIED_COMMAND=$(echo "$COMMAND" | sed -E 's/(git[[:space:]]+pull)/\1 --rebase/')

        # Update the command in the JSON and output
        echo "$INPUT" | jq --arg cmd "$MODIFIED_COMMAND" '.tool_input.command = $cmd'
        exit 0
    fi
fi

# Pass through unchanged for all other commands
echo "$INPUT"
