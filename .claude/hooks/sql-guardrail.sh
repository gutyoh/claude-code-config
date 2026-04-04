#!/usr/bin/env bash
# Hook: sql-guardrail.sh
# Path: .claude/hooks/sql-guardrail.sh
#
# Unified database guardrail for ALL database CLI commands (SQL + NoSQL).
# Replaces validate-readonly-sql.sh with a single, unified hook
# that detects the CLI tool and applies the correct safety level.
#
# Safety Levels:
#   STRICT   — Databricks: read-only, blocks ALL mutations (INSERT/UPDATE/DELETE/MERGE)
#   STANDARD — psql/mysql/sqlcmd/sqlite3/duckdb/sqlplus/clickhouse: blocks catastrophic
#              operations (DROP DATABASE, TRUNCATE, DELETE without WHERE) but allows
#              controlled writes (INSERT, UPDATE, CREATE) since sql-expert needs them.
#   MONGO    — mongosh: blocks dropDatabase(), collection.drop(), deleteMany({}),
#              remove({}) with empty filter. Allows normal CRUD with filters.
#
# Exit codes:
#   0 = allow (pass through)
#   2 = block (feed error message back to Claude)
#
# Usage: Configured in .claude/settings.json and agent frontmatter as a
#        PreToolUse hook on Bash.
# Platforms: macOS, Linux, Windows Git Bash

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "${INPUT}" | jq -r '.tool_input.command // empty')

# Skip if no command
[[ -z "${COMMAND}" ]] && exit 0

# --- Detect CLI and assign safety level ---

SAFETY_LEVEL=""

if echo "${COMMAND}" | grep -qiE '(databricks|DATABRICKS)'; then
    SAFETY_LEVEL="STRICT"
elif echo "${COMMAND}" | grep -qiE '\b(mongosh|mongo)\b'; then
    SAFETY_LEVEL="MONGO"
elif echo "${COMMAND}" | grep -qiE '\b(psql|mysql|mariadb|sqlcmd|mssql-cli|sqlite3|duckdb|sqlplus|cockroach\s+sql|clickhouse-client|clickhouse\s+client)\b'; then
    SAFETY_LEVEL="STANDARD"
fi

# Not a database CLI command — pass through
[[ -z "${SAFETY_LEVEL}" ]] && exit 0

# --- MONGO mode (mongosh): block catastrophic operations ---

if [[ "${SAFETY_LEVEL}" == "MONGO" ]]; then
    # ALWAYS block: dropDatabase()
    if echo "${COMMAND}" | grep -iE '\.dropDatabase\s*\(' >/dev/null; then
        cat >&2 <<'EOF'
BLOCKED: db.dropDatabase() is never allowed via this agent.
This permanently deletes the entire database and all its collections.
Run it manually in mongosh with extreme caution if truly needed.
EOF
        exit 2
    fi

    # ALWAYS block: collection.drop()
    if echo "${COMMAND}" | grep -iE '\.drop\s*\(\s*\)' >/dev/null; then
        cat >&2 <<'EOF'
BLOCKED: db.collection.drop() is never allowed via this agent.
This permanently deletes the entire collection and all its indexes.
Run it manually in mongosh if truly needed.
EOF
        exit 2
    fi

    # ALWAYS block: deleteMany({}) or deleteMany() with empty filter
    if echo "${COMMAND}" | grep -iE '\.deleteMany\s*\(\s*\{\s*\}\s*\)' >/dev/null; then
        cat >&2 <<'EOF'
BLOCKED: deleteMany({}) with empty filter detected.
This would delete ALL documents in the collection.
Add a filter to target specific documents: deleteMany({ field: value })
EOF
        exit 2
    fi

    # ALWAYS block: remove({}) with empty filter (legacy method)
    if echo "${COMMAND}" | grep -iE '\.remove\s*\(\s*\{\s*\}\s*\)' >/dev/null; then
        cat >&2 <<'EOF'
BLOCKED: remove({}) with empty filter detected.
This would delete ALL documents in the collection.
Use deleteMany({ filter }) with a specific filter instead.
EOF
        exit 2
    fi

    # WARN: updateMany({}, ...) with empty filter
    if echo "${COMMAND}" | grep -iE '\.updateMany\s*\(\s*\{\s*\}' >/dev/null; then
        echo "WARNING: updateMany({}) with empty filter detected. This updates ALL documents in the collection. Ensure the user has explicitly confirmed this operation." >&2
        exit 0
    fi

    exit 0
fi

# --- STRICT mode (Databricks): block ALL mutations ---

if [[ "${SAFETY_LEVEL}" == "STRICT" ]]; then
    if echo "${COMMAND}" | grep -iE '\b(INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|TRUNCATE\s+TABLE|MERGE\s+INTO|DROP\s+(TABLE|SCHEMA|CATALOG|DATABASE))\b' >/dev/null; then
        cat >&2 <<'EOF'
BLOCKED: Destructive SQL operation detected in Databricks command.
INSERT, UPDATE, DELETE, TRUNCATE, MERGE, and DROP TABLE/SCHEMA/CATALOG
are NEVER allowed via the databricks-expert agent.
Use dbt or proper CI/CD pipelines for data mutations.
EOF
        exit 2
    fi
    exit 0
fi

# --- STANDARD mode (general SQL CLIs): block catastrophic operations ---

# ALWAYS block: DROP DATABASE, TRUNCATE TABLE
if echo "${COMMAND}" | grep -iE '\b(DROP\s+DATABASE)\b' >/dev/null; then
    cat >&2 <<'EOF'
BLOCKED: DROP DATABASE is never allowed via this agent.
This is an irreversible, catastrophic operation.
Run it manually with extreme caution if truly needed.
EOF
    exit 2
fi

if echo "${COMMAND}" | grep -iE '\b(TRUNCATE\s+TABLE)\b' >/dev/null; then
    cat >&2 <<'EOF'
BLOCKED: TRUNCATE TABLE is never allowed via this agent.
This deletes ALL data from the table with no recovery.
Use DELETE with a WHERE clause, or run TRUNCATE manually.
EOF
    exit 2
fi

# ALWAYS block: DELETE without WHERE clause
# Matches: DELETE FROM table; or DELETE FROM table (end of string)
# Does NOT match: DELETE FROM table WHERE ...
if echo "${COMMAND}" | grep -iE '\bDELETE\s+FROM\s+\S+\s*;' >/dev/null; then
    # Check if there's a WHERE clause between DELETE FROM and the semicolon
    if ! echo "${COMMAND}" | grep -iE '\bDELETE\s+FROM\s+\S+\s+WHERE\b' >/dev/null; then
        cat >&2 <<'EOF'
BLOCKED: DELETE without WHERE clause detected.
This would delete ALL rows from the table.
Add a WHERE clause to target specific rows.
EOF
        exit 2
    fi
fi

# WARN (allow but stderr warning): DROP TABLE, DROP INDEX, DROP VIEW, DROP SCHEMA
if echo "${COMMAND}" | grep -iE '\b(DROP\s+TABLE|DROP\s+INDEX|DROP\s+VIEW|DROP\s+SCHEMA|ALTER\s+TABLE\s+\S+\s+DROP)\b' >/dev/null; then
    echo "WARNING: Potentially destructive DDL detected (DROP TABLE/INDEX/VIEW/SCHEMA). Ensure the user has explicitly confirmed this operation." >&2
    exit 0
fi

exit 0
