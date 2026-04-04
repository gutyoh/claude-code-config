#!/usr/bin/env bats
# sql-guardrail.bats
# Path: tests/sql-guardrail.bats
#
# bats-core tests for the sql-guardrail.sh PreToolUse hook.
# Tests both STRICT mode (Databricks) and STANDARD mode (psql/mysql/sqlcmd/sqlite3/duckdb/sqlplus).
#
# Run: bats tests/sql-guardrail.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/sql-guardrail.sh"

# Helper: build the JSON that Claude Code sends to PreToolUse hooks
make_input() {
    local cmd="$1"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd"
}

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
}

# ============================================================================
# Basic functionality
# ============================================================================

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "non-database command passes through (exit 0)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "empty command passes through (exit 0)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "missing command field passes through (exit 0)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "empty stdin passes through (exit 0)" {
    run bash -c 'echo "" | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STRICT mode (Databricks) — blocks ALL mutations
# ============================================================================

@test "STRICT: blocks INSERT INTO via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"INSERT INTO my_table VALUES (1)\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STRICT: blocks DELETE FROM via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post /api/2.0/sql/statements/ --json {\"statement\":\"DELETE FROM users WHERE id=1\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STRICT: blocks UPDATE SET via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"UPDATE users SET name=x\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STRICT: blocks TRUNCATE TABLE via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"TRUNCATE TABLE users\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STRICT: blocks MERGE INTO via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"MERGE INTO target USING source ON target.id=source.id\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STRICT: blocks DROP TABLE via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"DROP TABLE my_table\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STRICT: blocks DROP DATABASE via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"DROP DATABASE my_db\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STRICT: allows SELECT via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"SELECT * FROM users LIMIT 10\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "STRICT: allows DESCRIBE via databricks" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks tables get catalog.schema.table -p dev -o json"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "STRICT: stderr mentions Databricks on block" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"databricks api post --json {\"statement\":\"INSERT INTO t VALUES (1)\"}"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Databricks"* ]] || [[ "$stderr" == *"Databricks"* ]] || {
        # bats captures stderr in output when using run
        echo "$output" | grep -qi "databricks"
    }
}

# ============================================================================
# STANDARD mode — psql
# ============================================================================

@test "STANDARD psql: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP DATABASE mydb;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD psql: blocks TRUNCATE TABLE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"TRUNCATE TABLE users;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD psql: blocks DELETE without WHERE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM users;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD psql: allows DELETE with WHERE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM users WHERE id = 5;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "STANDARD psql: allows SELECT" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"SELECT * FROM users LIMIT 10;\" --csv"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "STANDARD psql: allows INSERT INTO (not blocked in standard mode)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"INSERT INTO users (name) VALUES ('"'"'alice'"'"');\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "STANDARD psql: allows CREATE TABLE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"CREATE TABLE test (id SERIAL PRIMARY KEY);\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "STANDARD psql: warns on DROP TABLE (exit 0 but stderr)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE IF EXISTS temp_data;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — mysql
# ============================================================================

@test "STANDARD mysql: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"mysql -e \"DROP DATABASE mydb;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD mysql: blocks TRUNCATE TABLE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"mysql -e \"TRUNCATE TABLE orders;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD mysql: allows SELECT" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"mysql -B -N -e \"SELECT * FROM users LIMIT 10;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — sqlcmd (MSSQL)
# ============================================================================

@test "STANDARD sqlcmd: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlcmd -Q \"DROP DATABASE testdb;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD sqlcmd: blocks TRUNCATE TABLE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlcmd -Q \"TRUNCATE TABLE logs;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD sqlcmd: allows SELECT" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlcmd -Q \"SELECT TOP 10 * FROM users;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — sqlite3
# ============================================================================

@test "STANDARD sqlite3: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlite3 my.db \"DROP DATABASE main;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD sqlite3: blocks DELETE without WHERE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlite3 data.db \"DELETE FROM events;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD sqlite3: allows SELECT" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlite3 data.db \".mode json\" \"SELECT * FROM events LIMIT 10;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — duckdb
# ============================================================================

@test "STANDARD duckdb: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"duckdb my.duckdb -c \"DROP DATABASE main;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD duckdb: blocks TRUNCATE TABLE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"duckdb analytics.db -c \"TRUNCATE TABLE events;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD duckdb: allows SELECT with ATTACH" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"duckdb -c \"ATTACH '"'"'postgres:dbname=mydb'"'"' AS pg; SELECT * FROM pg.users LIMIT 10;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "STANDARD duckdb: allows reading Parquet files" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"duckdb -c \"SELECT * FROM read_parquet('"'"'data.parquet'"'"') LIMIT 10;\" -json"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — sqlplus / Oracle
# ============================================================================

@test "STANDARD sqlplus: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlplus user/pass@host <<< \"DROP DATABASE mydb;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD sqlplus: allows SELECT" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlplus user/pass@host <<< \"SELECT * FROM users WHERE ROWNUM <= 10;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — mariadb (uses mysql-compatible CLI)
# ============================================================================

@test "STANDARD mariadb: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"mariadb -e \"DROP DATABASE mydb;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD mariadb: allows SELECT" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"mariadb -B -e \"SELECT * FROM users LIMIT 10;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — cockroach sql
# ============================================================================

@test "STANDARD cockroach sql: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"cockroach sql --execute=\"DROP DATABASE mydb;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

# ============================================================================
# STANDARD mode — clickhouse-client
# ============================================================================

@test "STANDARD clickhouse-client: blocks DROP DATABASE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"clickhouse-client --query=\"DROP DATABASE analytics;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "STANDARD clickhouse-client: allows SELECT" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"clickhouse-client --format JSON --query=\"SELECT count() FROM events;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

# ============================================================================
# STANDARD mode — mssql-cli
# ============================================================================

@test "STANDARD mssql-cli: blocks TRUNCATE TABLE" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"mssql-cli -Q \"TRUNCATE TABLE audit_log;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

# ============================================================================
# Case insensitivity
# ============================================================================

@test "blocks drop database (lowercase)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"psql -c \"drop database mydb;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks DROP DATABASE (uppercase)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"mysql -e \"DROP DATABASE MYDB;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks Drop Database (mixed case)" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"sqlcmd -Q \"Drop Database TestDB;\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 2 ]
}

# ============================================================================
# Non-database commands are NOT affected
# ============================================================================

@test "git commands pass through even with SQL-like content" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"git commit -m \"DROP DATABASE fix\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "echo commands pass through" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"echo \"DROP DATABASE test\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "python commands pass through" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"python3 -c \"print('"'"'DROP DATABASE'"'"')\""}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}

@test "npm commands pass through" {
    run bash -c 'echo '"'"'{"tool_name":"Bash","tool_input":{"command":"npm test"}}'"'"' | bash '"$HOOK"
    [ "$status" -eq 0 ]
}
