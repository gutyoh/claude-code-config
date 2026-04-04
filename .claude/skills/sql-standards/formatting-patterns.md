# Formatting Patterns (SQLFluff)

## What SQLFluff Does

SQLFluff is a SQL linter and auto-formatter supporting 29+ dialects. It enforces consistent style, catches syntax errors, and auto-fixes formatting issues. Use it when the user wants to lint or format SQL files.

Install: `pip install sqlfluff`

## CLI Usage

```bash
# Lint a SQL file (report issues)
sqlfluff lint query.sql --dialect postgres

# Fix a SQL file (auto-format)
sqlfluff fix query.sql --dialect postgres

# Parse a SQL file (check syntax without linting style)
sqlfluff parse query.sql --dialect postgres

# Lint with specific rules
sqlfluff lint query.sql --dialect postgres --rules L001,L002,L003

# Lint all SQL files in a directory
sqlfluff lint models/ --dialect postgres

# Lint from stdin
echo "SELECT a,b FROM t WHERE x=1" | sqlfluff lint --dialect postgres -
```

## Supported Dialects

| Dialect | SQLFluff name | Notes |
|---------|--------------|-------|
| ANSI SQL | `ansi` | Base dialect |
| PostgreSQL | `postgres` | |
| MySQL | `mysql` | |
| MariaDB | `mariadb` | Inherits from MySQL |
| T-SQL (SQL Server) | `tsql` | |
| SQLite | `sqlite` | |
| DuckDB | `duckdb` | Inherits from PostgreSQL |
| Oracle | `oracle` | |
| BigQuery | `bigquery` | |
| Snowflake | `snowflake` | |
| Databricks | `databricks` | Inherits from Spark SQL |
| Redshift | `redshift` | |
| ClickHouse | `clickhouse` | |
| Spark SQL | `sparksql` | |
| Hive | `hive` | |
| Trino | `trino` | |
| Athena | `athena` | |
| Db2 | `db2` | |
| Exasol | `exasol` | |
| Greenplum | `greenplum` | Inherits from PostgreSQL |
| Materialize | `materialize` | Inherits from PostgreSQL |
| Teradata | `teradata` | |
| Vertica | `vertica` | |

## Configuration

Create `.sqlfluff` in the project root:

```ini
[sqlfluff]
dialect = postgres
templater = raw
max_line_length = 120
exclude_rules = LT12

[sqlfluff:indentation]
indented_joins = true
indented_using_on = true

[sqlfluff:layout:type:comma]
line_position = trailing

[sqlfluff:rules:capitalisation.keywords]
capitalisation_policy = lower

[sqlfluff:rules:capitalisation.functions]
capitalisation_policy = lower
```

## Key Rules

| Rule | Category | What it enforces |
|------|----------|-----------------|
| LT01 | Layout | Trailing whitespace |
| LT02 | Layout | Indentation consistency |
| LT04 | Layout | Comma placement (leading vs trailing) |
| LT09 | Layout | SELECT targets on separate lines |
| CP01 | Capitalisation | Keyword casing (lower/upper) |
| CP03 | Capitalisation | Function name casing |
| AL01 | Aliasing | Implicit table aliases |
| AL03 | Aliasing | Column alias consistency |
| AM01 | Ambiguous | Ambiguous `DISTINCT` in `GROUP BY` |
| ST06 | Structure | SELECT wildcard before other columns |
| ST07 | Structure | `USING` instead of `ON` for same-column joins |

## Pre-commit Integration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 4.1.0
    hooks:
      - id: sqlfluff-lint
        args: [--dialect, postgres]
      - id: sqlfluff-fix
        args: [--dialect, postgres]
```

## When to Use SQLFluff vs sqlglot for Formatting

| Need | Tool |
|------|------|
| Enforce style rules (casing, indentation, commas) | SQLFluff |
| Pretty-print a single query | sqlglot (`pretty=True`) |
| Lint for best practices | SQLFluff |
| Check syntax errors | Either (SQLFluff or sqlglot parse) |
| CI/CD enforcement | SQLFluff (pre-commit, GitHub Actions) |
| Cross-dialect formatting | sqlglot (format during transpilation) |
