# Transpilation Patterns (sqlglot)

## What sqlglot Does

sqlglot is a Python SQL parser, transpiler, optimizer, and engine. It translates between 31 SQL dialects with zero dependencies. Use it when the user needs to convert SQL from one database dialect to another.

Install: `pip install sqlglot`

## CLI Usage via Python One-Liners

```bash
# Basic transpilation: T-SQL to PostgreSQL
python3 -c "import sqlglot; print(sqlglot.transpile('SELECT TOP 10 * FROM users', read='tsql', write='postgres')[0])"
# Output: SELECT * FROM users LIMIT 10

# MySQL to PostgreSQL
python3 -c "import sqlglot; print(sqlglot.transpile('SELECT IFNULL(name, \"Unknown\") FROM users', read='mysql', write='postgres')[0])"
# Output: SELECT COALESCE(name, 'Unknown') FROM users

# PostgreSQL to MySQL
python3 -c "import sqlglot; print(sqlglot.transpile('SELECT * FROM users WHERE name ILIKE \"%alice%\"', read='postgres', write='mysql')[0])"

# PostgreSQL to DuckDB
python3 -c "import sqlglot; print(sqlglot.transpile('SELECT NOW()', read='postgres', write='duckdb')[0])"

# Format/pretty-print SQL (no dialect conversion)
python3 -c "import sqlglot; print(sqlglot.transpile('SELECT a,b,c FROM t WHERE x=1 AND y=2 ORDER BY a', pretty=True)[0])"
```

## Supported Dialects

### Official (18)

| Dialect | sqlglot name |
|---------|-------------|
| Athena | `athena` |
| BigQuery | `bigquery` |
| ClickHouse | `clickhouse` |
| Databricks | `databricks` |
| DuckDB | `duckdb` |
| Hive | `hive` |
| MySQL | `mysql` |
| Oracle | `oracle` |
| PostgreSQL | `postgres` |
| Presto | `presto` |
| Redshift | `redshift` |
| Snowflake | `snowflake` |
| Spark | `spark` |
| SQLite | `sqlite` |
| StarRocks | `starrocks` |
| Tableau | `tableau` |
| Trino | `trino` |
| T-SQL (SQL Server) | `tsql` |

### Community (16+)

Doris, Dremio, Drill, Druid, Exasol, Fabric, Materialize, PRQL, RisingWave, SingleStore, Solr, Teradata, YDB, and more.

## Common Transpilation Scenarios

### Pagination

| From | To | Conversion |
|------|----|-----------|
| T-SQL `SELECT TOP 10 *` | PostgreSQL | `SELECT * ... LIMIT 10` |
| Oracle `WHERE ROWNUM <= 10` | PostgreSQL | `SELECT * ... LIMIT 10` |
| PostgreSQL `LIMIT 10 OFFSET 20` | T-SQL | `OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY` |

### Null Handling

| From | To | Conversion |
|------|----|-----------|
| MySQL `IFNULL(x, y)` | PostgreSQL | `COALESCE(x, y)` |
| Oracle `NVL(x, y)` | PostgreSQL | `COALESCE(x, y)` |
| T-SQL `ISNULL(x, y)` | PostgreSQL | `COALESCE(x, y)` |

### Date Functions

| From | To | Notes |
|------|----|-------|
| T-SQL `GETDATE()` | PostgreSQL `NOW()` | Current timestamp |
| MySQL `DATE_ADD(d, INTERVAL 1 DAY)` | PostgreSQL `d + INTERVAL '1 day'` | Date arithmetic |
| Oracle `SYSDATE` | PostgreSQL `NOW()` | Current timestamp |

### String Functions

| From | To | Notes |
|------|----|-------|
| T-SQL `LEN(s)` | PostgreSQL `LENGTH(s)` | String length |
| T-SQL `s1 + s2` | PostgreSQL `s1 \|\| s2` | Concatenation |
| MySQL `CONCAT(a, b, c)` | PostgreSQL `a \|\| b \|\| c` | Multi-arg concat |

## Advanced: Multi-Statement Transpilation

```bash
# Transpile a SQL file
python3 -c "
import sqlglot
with open('query.sql') as f:
    sql = f.read()
for statement in sqlglot.transpile(sql, read='tsql', write='postgres', pretty=True):
    print(statement)
    print(';')
"
```

## Advanced: Parse and Analyze SQL

```bash
# Parse SQL into AST and extract table names
python3 -c "
import sqlglot
ast = sqlglot.parse_one('SELECT u.name, o.total FROM users u JOIN orders o ON u.id = o.user_id')
tables = [table.name for table in ast.find_all(sqlglot.exp.Table)]
print('Tables:', tables)
"
# Output: Tables: ['users', 'orders']
```

## What sqlglot Cannot Do

- Execute SQL against live databases (use native CLIs for that)
- Provide autocompletion or LSP features
- Lint style rules (use SQLFluff for that)
- Handle non-SQL languages (except PRQL via community plugin)
- Guarantee 100% semantic equivalence for complex stored procedures
