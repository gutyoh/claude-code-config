# Permissions Patterns

## Grants (Unity Catalog)

Grants control access to Unity Catalog securables. Viewing grants is always safe (read-only). All values are discovered dynamically — never hardcoded.

### View Grants on a Table

```bash
databricks grants get TABLE <catalog>.<schema>.<table> -p <profile> -o json
```

### View Grants on a Schema

```bash
databricks grants get SCHEMA <catalog>.<schema> -p <profile> -o json
```

### View Grants on a Catalog

```bash
databricks grants get CATALOG <catalog> -p <profile> -o json
```

### View Effective Grants (Inherited + Direct)

```bash
databricks grants get-effective TABLE <catalog>.<schema>.<table> -p <profile> -o json
```

This shows the combined effect of grants at catalog, schema, and table levels.

### Securable Types for Grants

| Type | Example |
|------|---------|
| `CATALOG` | `databricks grants get CATALOG <catalog>` |
| `SCHEMA` | `databricks grants get SCHEMA <catalog>.<schema>` |
| `TABLE` | `databricks grants get TABLE <catalog>.<schema>.<table>` |
| `VOLUME` | `databricks grants get VOLUME <catalog>.<schema>.<volume>` |
| `FUNCTION` | `databricks grants get FUNCTION <catalog>.<schema>.<function>` |

---

## Grant/Revoke Operations (Write — Requires Confirmation)

These modify permissions and require explicit user confirmation before executing.

### Grant Access

```bash
# Agent MUST confirm with user: "Grant <privilege> on <table> to <principal>?"
databricks grants update TABLE <catalog>.<schema>.<table> -p <profile> \
  --json '{"changes": [{"principal": "<principal>", "add": ["SELECT"]}]}'
```

### Revoke Access

```bash
# Agent MUST confirm with user: "Revoke <privilege> on <table> from <principal>?"
databricks grants update TABLE <catalog>.<schema>.<table> -p <profile> \
  --json '{"changes": [{"principal": "<principal>", "remove": ["SELECT"]}]}'
```

### Common Privilege Types

| Privilege | Applies To | Description |
|-----------|-----------|-------------|
| `SELECT` | Table, View | Read data |
| `MODIFY` | Table | Write data |
| `CREATE_TABLE` | Schema | Create tables |
| `CREATE_SCHEMA` | Catalog | Create schemas |
| `USE_CATALOG` | Catalog | Access catalog |
| `USE_SCHEMA` | Schema | Access schema |
| `ALL_PRIVILEGES` | Any | Full access |
| `BROWSE` | Any | View metadata and lineage |
| `EXECUTE` | Function | Execute UDFs |

---

## Identity and Access

### Current User (Auth Validation)

```bash
databricks current-user me -p <profile> -o json
```

Returns:

```json
{
  "id": "123456789",
  "userName": "user@company.com",
  "displayName": "User Name",
  "groups": [...]
}
```

Use this to verify who the agent is authenticated as before sensitive operations.

### List Groups

```bash
databricks groups list -p <profile> -o json
```

### Get Group Details

```bash
databricks groups get <group-id> -p <profile> -o json
```

### List Users

```bash
databricks users list -p <profile> -o json
```

### List Service Principals

```bash
databricks service-principals list -p <profile> -o json
```

---

## Secrets Audit

Viewing secret scopes and metadata is read-only and safe. Secret values cannot be read via CLI.

### List Secret Scopes

```bash
databricks secrets list-scopes -p <profile> -o json
```

### List Secrets in a Scope (Metadata Only)

```bash
databricks secrets list-secrets <scope-name> -p <profile> -o json
```

**Note**: This lists secret keys and metadata, not the actual secret values. Values are never exposed via CLI.

### View Secret ACLs

```bash
databricks secrets list-acls <scope-name> -p <profile> -o json
```

---

## Workspace Bindings (Cross-Workspace Access)

Manage which workspaces can access a catalog. Workspace IDs are discovered dynamically — never hardcoded.

### View Current Bindings

```bash
databricks workspace-bindings get-bindings catalog <catalog> -p <profile> -o json
```

### Discover Workspace ID

The workspace ID is embedded in the host URL from `databricks auth profiles` output (e.g., `https://adb-<WORKSPACE_ID>.XX.azuredatabricks.net`). Extract it from there or ask the user.

### Bind Catalog to a Workspace (Write — Requires Confirmation)

```bash
# Agent MUST confirm: "Bind <catalog> to workspace <workspace_id>?"
databricks api patch /api/2.1/unity-catalog/bindings/catalog/<catalog> \
  -p <profile> -o json \
  --json '{"add": [{"workspace_id": <workspace_id>, "binding_type": "BINDING_TYPE_READ_WRITE"}]}'
```

### Unbind Catalog from a Workspace (Write — Requires Confirmation)

```bash
# Agent MUST confirm: "Unbind <catalog> from workspace <workspace_id>?"
databricks api patch /api/2.1/unity-catalog/bindings/catalog/<catalog> \
  -p <profile> -o json \
  --json '{"remove": [{"workspace_id": <workspace_id>, "binding_type": "BINDING_TYPE_READ_WRITE"}]}'
```

**Important**: The `remove` call MUST include `binding_type` — omitting it will fail silently.

---

## Common Permission Audit Workflows

### Full Table Access Audit

```bash
# 1. Who has direct access?
databricks grants get TABLE <catalog>.<schema>.<table> -p <profile> -o json

# 2. What effective permissions exist (including inherited)?
databricks grants get-effective TABLE <catalog>.<schema>.<table> -p <profile> -o json

# 3. What masking functions are applied?
databricks functions list <catalog> <schema> -p <profile> -o json
```

### Schema-Wide Permission Audit

```bash
# 1. Schema-level grants
databricks grants get SCHEMA <catalog>.<schema> -p <profile> -o json

# 2. All tables in the schema
databricks tables list <catalog> <schema> -p <profile> -o json

# 3. Per-table grants (repeat for each table discovered in step 2)
databricks grants get TABLE <catalog>.<schema>.<table> -p <profile> -o json
```

---

## Anti-Patterns

1. **Granting without confirmation**: Always ask the user to confirm before modifying grants
2. **Revoking without understanding effective grants**: Check `get-effective` first to understand the full picture
3. **Forgetting workspace bindings include `binding_type` in remove**: The `remove` call MUST include `binding_type`
4. **Not verifying identity before sensitive operations**: Always run `current-user me` first
5. **Hardcoding workspace IDs**: Always discover from profile host URL or ask user
6. **Hardcoding profile names**: Always discover via `databricks auth profiles`
