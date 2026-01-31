#!/usr/bin/env bash
# Hook: validate-readonly-sql.sh
# Purpose: Block destructive SQL operations in databricks commands.
# Used by: databricks-expert agent (PreToolUse hook on Bash)
# Exit code 2 = block the tool call and feed error message back to Claude.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only inspect databricks-related commands
if ! echo "$COMMAND" | grep -qE '(databricks|DATABRICKS)'; then
    exit 0
fi

# Block NEVER-allowed SQL operations (case-insensitive)
if echo "$COMMAND" | grep -iE '\b(INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|TRUNCATE\s+TABLE|MERGE\s+INTO|DROP\s+(TABLE|SCHEMA|CATALOG|DATABASE))\b' >/dev/null; then
    echo "BLOCKED: Destructive SQL operation detected. INSERT, UPDATE, DELETE, TRUNCATE, MERGE, and DROP TABLE/SCHEMA/CATALOG are NEVER allowed via this agent. Use dbt or proper CI/CD pipelines for data mutations." >&2
    exit 2
fi

exit 0
