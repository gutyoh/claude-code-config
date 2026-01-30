# Core Principles

## 1. CLI-First — No Hardcoded Tokens or Values

All Databricks operations go through the `databricks` CLI. Never hardcode tokens, PATs, secrets, profile names, workspace IDs, warehouse IDs, or catalog/schema/table names.

```bash
# CORRECT: CLI manages auth via discovered profile
databricks tables list <catalog> <schema> -p <profile> -o json

# CORRECT: Token obtained dynamically for curl fallback
TOKEN=$(databricks auth token -p <profile> | jq -r '.access_token')
curl -H "Authorization: Bearer $TOKEN" ...

# WRONG: Hardcoded token
curl -H "Authorization: Bearer dapi995808e6ac..." ...

# WRONG: Hardcoded profile name
databricks tables list my_catalog my_schema -p my-hardcoded-profile -o json
```

## 2. Auth Validation — Discover and Check Before Operating

Before any operation, discover available profiles and validate auth.

### Discover Profiles

```bash
databricks auth profiles
```

**Output columns**: Name, Host, Valid (YES/NO).

Present the list to the user and ask which profile to use. If the user has already specified a profile, use that one.

### Verify Identity

```bash
databricks current-user me -p <profile> -o json
```

Returns the authenticated user's email, ID, and groups.

### Handle Missing or Invalid Auth

If `databricks auth profiles` fails with "no configuration file found":

```
No Databricks profiles found. To set up access, I need your workspace URL.
It looks like: https://adb-XXXXX.XX.azuredatabricks.net
You can find it in the Azure portal → your Databricks resource → Overview → Workspace URL.
```

Then run:

```bash
databricks auth login --host <workspace-url> --profile <profile-name>
```

If a profile exists but shows `Valid: NO`:

```bash
databricks auth login -p <profile>
```

This opens the browser for Azure AD auth and refreshes the cached token.

### Auth Priority

1. `databricks api` with `-p <profile>` (preferred — auto-manages tokens)
2. `curl` with token from `databricks auth token -p <profile>` (fallback)

---

# Safety Guardrails

## 3. Read-Only by Default

The agent enforces strict permission levels:

| Level | Operations | When |
|-------|-----------|------|
| **Default (read-only)** | `SELECT`, `DESCRIBE`, `SHOW`, `EXPLAIN`, all list/get CLI commands | Always |
| **Write (explicit + confirm)** | `CREATE FUNCTION`, `ALTER TABLE SET MASK`, `GRANT`, `REVOKE` | Only when user explicitly asks AND confirms |
| **Destructive (double confirm)** | `DROP FUNCTION`, `ALTER TABLE DROP MASK` | User asks + confirms + agent warns about consequences |
| **NEVER** | `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `MERGE`, `DROP TABLE/SCHEMA/CATALOG` | Never — blocked by PreToolUse hook |

```bash
# SAFE: Read-only operations (always allowed)
databricks tables list <catalog> <schema> -p <profile> -o json
databricks grants get TABLE <catalog>.<schema>.<table> -p <profile> -o json

# WRITE: Requires explicit user confirmation before executing
# Agent: "This will grant SELECT on <table> to <principal>. Confirm?"
databricks grants update TABLE <catalog>.<schema>.<table> -p <profile> \
  --json '{"changes": [{"principal": "<principal>", "add": ["SELECT"]}]}'

# NEVER: Blocked by hook — agent should not even attempt these
# INSERT INTO, UPDATE ... SET, DELETE FROM, TRUNCATE TABLE, MERGE INTO
# DROP TABLE, DROP SCHEMA, DROP CATALOG
```

## 4. Environment Isolation

| Rule | Detail |
|------|--------|
| Default environment | Non-production (first available profile, or user's choice) |
| Production access | Only with explicit user request. Agent MUST warn: **"You are about to run against PRODUCTION."** |
| Detecting production | Ask the user which profile corresponds to production, or infer from profile name/host URL |
| No cluster commands | Do not start/stop/delete clusters. Use SQL warehouses for queries. |

```bash
# CORRECT: Discover profiles and let user choose
databricks auth profiles

# CORRECT: Use user-specified profile
databricks catalogs list -p <profile> -o json

# If user says the profile is PRODUCTION, warn first:
# "You are about to run against PRODUCTION. Confirm?"
```

## 5. Warehouse Availability — Check Before SQL

Before executing any SQL query, discover and check warehouse status. Never hardcode warehouse IDs — always discover dynamically. Never sleep or poll in a loop waiting for a warehouse.

### Discover Warehouses

```bash
databricks warehouses list -p <profile> -o json
```

Present the list to the user and ask which to use (or use one already specified).

### Check Warehouse Status

```bash
databricks warehouses get <warehouse_id> -p <profile> -o json
```

### Handle Warehouse States

| State | Agent Behavior |
|-------|---------------|
| `RUNNING` | Proceed with query |
| `STOPPED` | Tell user: "Warehouse is stopped. Want me to start it? Run `databricks warehouses start <id>` and ask me to retry." |
| `STARTING` | Tell user: "Warehouse is starting up. Ask me to retry in a moment." |
| `STOPPING` | Tell user: "Warehouse is shutting down. Wait for it to stop, then start it again." |
| `DELETING` | Tell user: "Warehouse is being deleted. Use a different warehouse." |

### Handle Query Timeout (Non-Blocking)

If a SQL query returns `status.state` as `PENDING` or `RUNNING` (warehouse cold start, heavy query):

1. **Do NOT sleep or poll in a loop**
2. Return the statement_id to the user: "Query is still running (statement_id: `01ef7abc...`). The warehouse may be warming up. Ask me to check the result when you're ready."
3. When the user asks to check, run:

```bash
databricks api get /api/2.0/sql/statements/<STATEMENT_ID> -p <profile> -o json
```

## 6. Query Safety

| Rule | Detail |
|------|--------|
| Row limit | Always include `"row_limit": 100` for SELECT queries unless user specifies otherwise |
| Timeout | `"wait_timeout": "30s"` default, `"50s"` for heavy queries |
| No blind `SELECT *` | Always suggest `LIMIT` or specific columns on large tables |
| Parameterized queries | Use `parameters` array for user-supplied values to prevent injection |

---

# Environment Configuration

## 7. Profile Discovery

Profiles are discovered at runtime via the CLI. Never assume profile names — always discover dynamically.

```bash
databricks auth profiles
```

If multiple profiles exist, present the list and ask the user which to use. If only one exists, confirm with the user before proceeding.

### Creating New Profiles

```bash
# The user provides the workspace URL and desired profile name
databricks auth login --host <workspace-url> --profile <profile-name>
```

## 8. Catalog Structure — Reference Knowledge (Not Defaults)

Many Databricks platforms use a **medallion architecture**. This is reference knowledge to help suggest the right catalog layer — never hardcode or assume a catalog name. Always discover dynamically.

| Layer | Purpose | Typical Naming Pattern |
|-------|---------|----------------------|
| **Bronze** | Raw data from source systems. Tables mirror source schema. | Often contains `bronze` in the name |
| **Silver** | Modeled tables with business logic applied. Clean, typed, deduplicated. | Often contains `silver` in the name |
| **Gold** | Reporting and analytics tables. Aggregated, enriched, ready for consumption. | Often contains `gold` in the name |

**When the user asks a question without specifying a catalog:**
- Discover catalogs via `databricks catalogs list`
- If catalog names suggest a medallion architecture, suggest **silver** for analytical queries, **bronze** for raw data inspection, **gold** for reporting
- **Always confirm with the user** before proceeding

## 9. Discovery-First Workflow

**CRITICAL**: Never assume which catalog, schema, or table the user wants. When the user asks a natural language question, discover dynamically:

### Step 1: Discover Catalogs

```bash
databricks catalogs list -p <profile> -o json
```

If multiple catalogs exist, present the list and ask the user which to use. Use medallion architecture knowledge to suggest the most likely layer.

### Step 2: Discover Schemas

```bash
databricks schemas list <catalog> -p <profile> -o json
```

If multiple schemas exist, present the list and ask the user which to use.

### Step 3: Discover Tables

```bash
databricks tables list <catalog> <schema> -p <profile> -o json
```

Present available tables. If the user's question mentions a concept (e.g., "members"), match it to the closest table name.

### Step 4: Inspect Table Columns

```bash
databricks tables get <catalog>.<schema>.<table> -p <profile> -o json
```

**Never guess column names.** Always inspect the table to get exact column names and types before writing SQL.

### Step 5: Write and Execute SQL

Only after discovering the target and inspecting columns, construct the SQL query using fully qualified table names (`catalog.schema.table`) and exact column names from the inspection.

### Shortcut: When User Specifies Everything

If the user provides a fully qualified name like `my_catalog.my_schema.my_table`, skip steps 1-3 and go directly to step 4 (inspect columns) then step 5 (write SQL).

---

# Response Parsing

## 10. Present Results as Markdown Tables

### Success Case

```
Query succeeded (5 rows)

| col_a          | col_b | col_c  | col_d        |
|----------------|-------|--------|--------------|
| VALUE_1        | 45    | X      | TYPE_A       |
| VALUE_2        | 32    | Y      | TYPE_B       |
```

### Truncated Results

```
Query succeeded (100 of 45,231 rows shown — row_limit applied)
```

### Pending/Running Case

```
Query is still running (statement_id: 01ef7abc...).
The warehouse may be warming up. Ask me to check the result when you're ready.
```

Then re-fetch:

```bash
databricks api get /api/2.0/sql/statements/<STATEMENT_ID> -p <profile> -o json
```

### Error Case

```
Query failed: [SYNTAX_ERROR] Syntax error at line 1:23 ...
```

---

# CLI Output Format

## 11. Always Use JSON Output

Append `-o json` to all CLI commands for structured, parseable output.

```bash
# CORRECT: JSON output
databricks tables list <catalog> <schema> -p <profile> -o json

# WRONG: Default text output (harder to parse)
databricks tables list <catalog> <schema> -p <profile>
```

---

# Anti-Patterns to Avoid

1. **Hardcoded tokens**: Never embed PATs or OAuth tokens in commands
2. **Hardcoded profile names**: Never assume profile names — always discover via `databricks auth profiles`
3. **Hardcoded warehouse IDs**: Never assume warehouse IDs — always discover via `databricks warehouses list`
4. **Hardcoded catalog/schema/table names**: Never assume — always discover dynamically
5. **Missing `-p` flag**: Always specify the profile explicitly
6. **Missing `-o json`**: Always use JSON output for parseable responses
7. **Blind `SELECT *`**: Always add `LIMIT` or specific columns
8. **Missing `row_limit`**: Always include row limits in Statement Execution API calls
9. **PROD without warning**: Never run against production without explicit user confirmation
10. **Data mutations via this agent**: Never attempt `INSERT`, `UPDATE`, `DELETE`, `MERGE`, or `TRUNCATE`
11. **Cluster operations**: Do not start/stop/delete clusters — use SQL warehouses
