# SQL Patterns

## Discovery Before Query

**CRITICAL**: Before writing any SQL query, always discover the target dynamically. Never guess catalog, schema, table, or column names. Never hardcode profile names, warehouse IDs, or any environment-specific values.

### Progressive Discovery Chain

```
1. databricks auth profiles              → discover and choose profile
2. databricks warehouses list            → discover and choose warehouse
3. databricks catalogs list              → choose catalog
4. databricks schemas list <catalog>     → choose schema
5. databricks tables list <cat> <schema> → choose table
6. databricks tables get <cat.schema.table> → inspect columns
7. Write SQL using exact column names from step 6
```

### When User Specifies a Fully Qualified Name

Skip to step 6 — inspect columns, then write SQL:

```bash
databricks tables get <catalog>.<schema>.<table> -p <profile> -o json
```

### When User Asks a Vague Question

Example: "How many members do we have?"

1. Discover profiles → use specified or ask user to choose
2. Discover warehouses → use available or ask user to choose
3. Discover catalogs → suggest the appropriate layer (e.g., silver for analytical queries)
4. Ask user to confirm catalog
5. Discover schemas → present options
6. Discover tables → match "members" to table name
7. Inspect columns → get exact names
8. Write SQL with fully qualified names

---

## Statement Execution API

The primary method for running SQL queries against Databricks.

### Basic Query

```bash
# warehouse_id, catalog, schema, and profile all come from discovery — never hardcode
databricks api post /api/2.0/sql/statements/ \
  -p <profile> \
  -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "catalog": "<catalog>",
    "schema": "<schema>",
    "statement": "SELECT <columns> FROM <table> LIMIT 10",
    "wait_timeout": "30s",
    "row_limit": 100
  }'
```

### With Parameterized Values

Use the `parameters` array for user-supplied values to prevent SQL injection.

```bash
databricks api post /api/2.0/sql/statements/ \
  -p <profile> \
  -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "catalog": "<catalog>",
    "schema": "<schema>",
    "statement": "SELECT <columns> FROM <table> WHERE <column> = :param LIMIT 10",
    "wait_timeout": "30s",
    "row_limit": 100,
    "parameters": [{"name": "param", "value": "<user-value>", "type": "STRING"}]
  }'
```

---

## Request Parameters Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `warehouse_id` | string | Yes | — | SQL warehouse to execute on (from `warehouses list`) |
| `statement` | string | Yes | — | SQL query text |
| `catalog` | string | No | — | Default catalog for unqualified table names |
| `schema` | string | No | — | Default schema for unqualified table names |
| `wait_timeout` | string | No | `"10s"` | `"0s"` to `"50s"`. Use `"30s"` default, `"50s"` for heavy queries |
| `row_limit` | int | No | — | Max rows to return. **Always include `100` unless user specifies otherwise** |
| `byte_limit` | int | No | — | Max bytes to return |
| `format` | string | No | `JSON_ARRAY` | `JSON_ARRAY`, `CSV`, or `ARROW_STREAM` |
| `disposition` | string | No | `INLINE` | `INLINE` or `EXTERNAL_LINKS` |
| `on_wait_timeout` | string | No | `CONTINUE` | `CONTINUE` or `CANCEL` |
| `parameters` | array | No | — | Parameterized query values |

---

## Response Handling

### Success Response Structure

```json
{
  "statement_id": "01ef7...",
  "status": { "state": "SUCCEEDED" },
  "manifest": {
    "schema": {
      "columns": [
        { "name": "col_name", "type_name": "STRING", "position": 0 }
      ]
    },
    "total_row_count": 10
  },
  "result": {
    "data_array": [
      ["value1", "value2"],
      ["value3", "value4"]
    ]
  }
}
```

Parse this into a markdown table using column names from `manifest.schema.columns` and data from `result.data_array`.

### Async Queries (PENDING/RUNNING) — Non-Blocking

When `status.state` is `PENDING` or `RUNNING` (cold warehouse, heavy query), **do NOT sleep or poll in a loop**. Instead:

1. Return the statement_id to the user:

```
Query is still running (statement_id: 01ef7abc...).
The warehouse may be warming up. Ask me to check the result when you're ready.
```

2. When the user asks to check, run:

```bash
databricks api get /api/2.0/sql/statements/<STATEMENT_ID> \
  -p <profile> -o json
```

3. If still PENDING/RUNNING, report status again. If SUCCEEDED, parse and present results. If FAILED, show the error.

### Pagination (Large Results)

If `result.next_chunk_internal_link` is present, fetch the next chunk:

```bash
databricks api get <next_chunk_internal_link> -p <profile> -o json
```

---

## Common Query Patterns

All examples below use placeholder values. Replace `<warehouse_id>`, `<catalog>`, `<schema>`, `<table>`, and `<profile>` with values discovered dynamically via the Discovery Before Query workflow.

### Data Exploration

```bash
# Count rows in a table (use fully qualified name from discovery)
databricks api post /api/2.0/sql/statements/ \
  -p <profile> -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "statement": "SELECT COUNT(*) as total FROM <catalog>.<schema>.<table>",
    "wait_timeout": "30s"
  }'
```

### Schema Inspection via SQL

```bash
# DESCRIBE TABLE for column details
databricks api post /api/2.0/sql/statements/ \
  -p <profile> -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "statement": "DESCRIBE TABLE <catalog>.<schema>.<table>",
    "wait_timeout": "30s"
  }'
```

### Data Quality Check

```bash
# Find nulls in a column (column name from tables get inspection)
databricks api post /api/2.0/sql/statements/ \
  -p <profile> -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "statement": "SELECT COUNT(*) as null_count FROM <catalog>.<schema>.<table> WHERE <column> IS NULL",
    "wait_timeout": "30s"
  }'
```

### Sampling Data

```bash
# Sample with specific columns from inspection (avoid SELECT *)
databricks api post /api/2.0/sql/statements/ \
  -p <profile> -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "catalog": "<catalog>",
    "schema": "<schema>",
    "statement": "SELECT <col1>, <col2>, <col3> FROM <table> LIMIT 20",
    "wait_timeout": "30s",
    "row_limit": 100
  }'
```

---

## DDL Operations (Write — Requires Confirmation)

These operations modify metadata but not data. They require explicit user confirmation. All values come from discovery.

### Create Masking Function

```bash
# Agent MUST confirm with user before executing
databricks api post /api/2.0/sql/statements/ \
  -p <profile> -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "statement": "CREATE FUNCTION <catalog>.<schema>.<function_name>(name STRING) RETURN CASE WHEN is_account_group_member('<group>') THEN name ELSE '***MASKED***' END",
    "wait_timeout": "30s"
  }'
```

### Apply Column Mask

```bash
# Agent MUST confirm with user before executing
databricks api post /api/2.0/sql/statements/ \
  -p <profile> -o json \
  --json '{
    "warehouse_id": "<warehouse_id>",
    "statement": "ALTER TABLE <catalog>.<schema>.<table> ALTER COLUMN <column> SET MASK <catalog>.<schema>.<function_name>",
    "wait_timeout": "30s"
  }'
```

---

## Anti-Patterns

1. **Skipping discovery**: Never write SQL without first inspecting the table's columns via `tables get`
2. **Guessing column names**: Always use exact names from `tables get` output
3. **Hardcoding catalog/schema/table**: Always discover dynamically or use what the user specified
4. **Hardcoding profile names**: Always discover via `databricks auth profiles`
5. **Hardcoding warehouse IDs**: Always discover via `databricks warehouses list`
6. **Missing `row_limit`**: Always include for SELECT queries via Statement Execution API
7. **Missing `wait_timeout`**: Always include, default `"30s"`
8. **`SELECT *` on large tables**: Use specific columns and `LIMIT`
9. **String interpolation for user values**: Use `parameters` array instead
10. **Sleeping or polling in a loop**: When query is PENDING/RUNNING, return statement_id and let user decide when to check
11. **Not checking warehouse status**: Always verify warehouse is RUNNING before executing SQL
12. **Ignoring `next_chunk_internal_link`**: Check for pagination on large results
