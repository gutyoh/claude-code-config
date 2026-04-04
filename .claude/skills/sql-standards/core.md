# Core Principles

## 1. Safety Guardrails

### Read-Only by Default

The agent operates in read-only mode unless the user explicitly requests a write operation.

| Level | Operations | When |
|-------|-----------|------|
| **Default (read-only)** | `SELECT`, `DESCRIBE`, `SHOW`, `EXPLAIN`, all schema inspection | Always |
| **Write (explicit + confirm)** | `CREATE TABLE`, `ALTER TABLE`, `INSERT`, `UPDATE ... WHERE`, `DELETE ... WHERE` | Only when user explicitly asks AND confirms |
| **Destructive (double confirm)** | `DROP TABLE IF EXISTS`, `DROP INDEX`, `DROP VIEW` | User asks + confirms + agent warns about consequences |
| **NEVER** | `DROP DATABASE`, `TRUNCATE TABLE`, `DELETE` without `WHERE` | Blocked by `sql-guardrail.sh` PreToolUse hook |

### Row Limits

Always add `LIMIT 100` (or dialect equivalent) to SELECT queries unless the user specifies otherwise.

| Database | Syntax |
|----------|--------|
| PostgreSQL, MySQL, SQLite, DuckDB | `LIMIT 100` |
| SQL Server | `TOP 100` or `OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY` |
| Oracle | `FETCH FIRST 100 ROWS ONLY` (12c+) or `WHERE ROWNUM <= 100` |

### No Blind Writes

Never execute INSERT, UPDATE, or DELETE without first inspecting the target table's schema and confirming with the user.

### Parameterized Queries

When the CLI supports it, use parameterized queries for user-supplied values to prevent SQL injection. When it doesn't (most CLIs), ensure values are properly escaped.

---

## 2. CLI Detection and Connection

### Detect Available CLIs

```bash
# Check which database CLIs are installed
command -v psql &>/dev/null && echo "PostgreSQL: psql available"
command -v mysql &>/dev/null && echo "MySQL: mysql available"
command -v sqlcmd &>/dev/null && echo "SQL Server: sqlcmd available"
command -v sqlite3 &>/dev/null && echo "SQLite: sqlite3 available"
command -v duckdb &>/dev/null && echo "DuckDB: duckdb available"
command -v sql &>/dev/null && echo "Oracle SQLcl: sql available"
command -v sqlplus &>/dev/null && echo "Oracle SQL*Plus: sqlplus available"
command -v clickhouse-client &>/dev/null && echo "ClickHouse: clickhouse-client available"
```

### Connection Patterns

| Database | Connection string pattern |
|----------|--------------------------|
| PostgreSQL | `psql "postgresql://user:pass@host:5432/dbname"` or `psql -h host -p 5432 -U user -d dbname` |
| MySQL | `mysql -h host -P 3306 -u user -p dbname` |
| SQL Server | `sqlcmd -S host,1433 -U user -P pass -d dbname` |
| SQLite | `sqlite3 /path/to/database.db` |
| DuckDB | `duckdb /path/to/database.duckdb` or `duckdb` (in-memory) |
| Oracle | `sql user/pass@host:1521/service` or `sqlplus user/pass@//host:1521/service` |

### Detect Database from Config Files

Look for connection details in common config files:

| File | Database hints |
|------|---------------|
| `.env` | `DATABASE_URL=`, `DB_HOST=`, `PGHOST=`, `MYSQL_HOST=` |
| `database.yml` | Rails — `adapter: postgresql`, `adapter: mysql2`, `adapter: sqlite3` |
| `settings.py` | Django — `'ENGINE': 'django.db.backends.postgresql'` |
| `appsettings.json` | .NET — `"ConnectionStrings"` section |
| `docker-compose.yml` | `image: postgres:`, `image: mysql:`, `image: mcr.microsoft.com/mssql/server` |
| `pyproject.toml` | `sqlalchemy`, `psycopg2`, `mysqlclient`, `duckdb` in dependencies |

---

## 3. Discovery-First Workflow

**CRITICAL**: Never assume which database, schema, table, or column the user wants. Always discover dynamically.

### Step 1: Detect Engine

Check CLI availability and config files. Ask the user if ambiguous.

### Step 2: Verify Connection

Run a simple test query to confirm the connection works:

| Database | Test query |
|----------|-----------|
| PostgreSQL | `psql -c "SELECT 1;" --csv` |
| MySQL | `mysql -e "SELECT 1;"` |
| SQL Server | `sqlcmd -Q "SELECT 1;" -h -1` |
| SQLite | `sqlite3 db.db "SELECT 1;"` |
| DuckDB | `duckdb -c "SELECT 1;"` |
| Oracle | `sql -S user/pass@host <<< "SELECT 1 FROM DUAL;"` |

### Step 3: List Databases

| Database | Command |
|----------|---------|
| PostgreSQL | `psql -c "\l" --csv` or `psql -c "SELECT datname FROM pg_database WHERE datistemplate = false;" --csv` |
| MySQL | `mysql -e "SHOW DATABASES;" -B` |
| SQL Server | `sqlcmd -Q "SELECT name FROM sys.databases;" -W -s ","` |
| SQLite | N/A (file-based — one DB per file) |
| DuckDB | `duckdb -c "SHOW DATABASES;" -json` |
| Oracle | `sql -S user/pass@host <<< "SELECT name FROM v\$database;"` |

### Step 4: List Tables

| Database | Command |
|----------|---------|
| PostgreSQL | `psql -d dbname -c "\dt" --csv` or `psql -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public';" --csv` |
| MySQL | `mysql dbname -e "SHOW TABLES;" -B` |
| SQL Server | `sqlcmd -d dbname -Q "SELECT name FROM sys.tables;" -W -s ","` |
| SQLite | `sqlite3 db.db ".tables"` or `sqlite3 db.db "SELECT name FROM sqlite_master WHERE type='table';"` |
| DuckDB | `duckdb db.duckdb -c "SHOW TABLES;" -json` |
| Oracle | `sql -S user/pass@host <<< "SELECT table_name FROM user_tables;"` |

### Step 5: Describe Table (Inspect Columns)

**Never guess column names.** Always inspect the table first.

| Database | Command |
|----------|---------|
| PostgreSQL | `psql -c "\d tablename" --csv` or `psql -c "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'tablename';" --csv` |
| MySQL | `mysql -e "DESCRIBE tablename;" -B` |
| SQL Server | `sqlcmd -Q "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'tablename';" -W -s ","` |
| SQLite | `sqlite3 db.db ".schema tablename"` or `sqlite3 db.db "PRAGMA table_info(tablename);"` |
| DuckDB | `duckdb db.duckdb -c "DESCRIBE tablename;" -json` |
| Oracle | `sql -S user/pass@host <<< "DESCRIBE tablename;"` |

### Step 6: Write and Execute SQL

Only after discovering the target and inspecting columns, write the SQL query using exact column names.

---

## 4. Output Formatting

### Present Results as Markdown Tables

```
Query succeeded (5 rows)

| id | name    | email             | created_at          |
|----|---------|-------------------|---------------------|
| 1  | Alice   | alice@example.com | 2026-01-15 08:30:00 |
| 2  | Bob     | bob@example.com   | 2026-02-20 14:22:00 |
```

### Truncated Results

```
Query succeeded (100 of 45,231 rows shown — LIMIT applied)
```

### Error Case

```
Query failed: ERROR: relation "nonexistent_table" does not exist
```

### CLI Output Formats for Parseable Results

| Database | Flag for parseable output |
|----------|--------------------------|
| PostgreSQL | `--csv` (CSV) or `-t -A` (unaligned, no headers) |
| MySQL | `-B` (batch/tab-separated) or `-B --column-names` |
| SQL Server | `-W -s ","` (trim + comma separator) or `-y 0` (unlimited column width) |
| SQLite | `.mode json` (JSON) or `.mode csv` (CSV) |
| DuckDB | `-json` (JSON) or `-csv` (CSV) |
| Oracle | `SET MARKUP CSV ON` in SQLcl |

---

## 5. ClickHouse Recognition

ClickHouse uses a **non-standard SQL dialect** with significant differences from standard SQL:

- **MergeTree engine family** — tables require `ENGINE = MergeTree() ORDER BY (...)`. 10+ engine variants with different merge/deduplication behaviors.
- **`PREWHERE` clause** — ClickHouse-specific optimization that filters before reading all columns.
- **`FINAL` modifier** — forces deduplication in `ReplacingMergeTree` tables at query time.
- **Case-sensitive function names** — `sum()` works, `SUM()` does not.
- **`LowCardinality` type** — dictionary-encoded strings for columns with <10k unique values.
- **Mutations** — `ALTER TABLE UPDATE` and `ALTER TABLE DELETE` are async background operations, not immediate.
- **No standard UPSERT** — use `ReplacingMergeTree` + `FINAL` instead.

**CLI**: `clickhouse-client --format JSON --query "SELECT ..."`

For basic connection and SELECT queries, the sql-expert can help. For production work involving MergeTree engine selection, partitioning strategy, materialized views, and performance tuning, recommend a dedicated `clickhouse-expert` agent.

---

## 6. Anti-Patterns to Avoid

1. **Hardcoded credentials**: Never embed passwords in commands — use connection strings from config files or environment variables
2. **Guessing column names**: Always inspect the table with DESCRIBE/\d before writing SQL
3. **Missing row limits**: Always add LIMIT (or dialect equivalent) to SELECT queries
4. **Blind `SELECT *`**: Use specific columns and LIMIT on large tables
5. **Assuming the database engine**: Always detect from CLI availability, config files, or ask the user
6. **Running writes without confirmation**: CREATE, INSERT, UPDATE, DELETE all require explicit user confirmation
7. **Ignoring dialect differences**: String quoting, pagination, auto-increment, UPSERT, and date functions vary across dialects
8. **Not checking CLI availability**: Always verify `command -v <cli>` before attempting to use it
9. **Sleeping or polling**: If a query takes long, inform the user and let them decide when to retry
10. **Using one dialect's syntax on another engine**: PostgreSQL's `ILIKE` doesn't exist in MySQL — always check the dialect
