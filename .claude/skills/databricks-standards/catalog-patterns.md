# Catalog Patterns (Unity Catalog)

Unity Catalog uses a three-level namespace: `catalog.schema.table`. All exploration commands are read-only and always safe. All values are discovered dynamically — never hardcoded.

## Catalogs

### List All Catalogs

```bash
databricks catalogs list -p <profile> -o json
```

### Get Catalog Details

```bash
databricks catalogs get <catalog> -p <profile> -o json
```

---

## Schemas

### List Schemas in a Catalog

```bash
databricks schemas list <catalog> -p <profile> -o json
```

### Get Schema Details

```bash
databricks schemas get <catalog>.<schema> -p <profile> -o json
```

---

## Tables

### List Tables in a Schema

```bash
databricks tables list <catalog> <schema> -p <profile> -o json
```

### Get Table Details (Columns, Types, Properties)

```bash
databricks tables get <catalog>.<schema>.<table> -p <profile> -o json
```

### Check if Table Exists

```bash
databricks tables exists <catalog>.<schema>.<table> -p <profile> -o json
```

### List Table Summaries (Lightweight)

```bash
databricks tables list-summaries <catalog> -p <profile> -o json
```

---

## Table Constraints

### View Primary/Foreign Key Constraints

Table constraints are visible via `databricks tables get` in the response JSON. They encode relationships between fields in tables.

```bash
# Get table details — constraints are in the response
databricks tables get <catalog>.<schema>.<table> -p <profile> -o json
```

The response includes a `table_constraints` array with primary keys and foreign keys. Use this to understand table relationships.

---

## Volumes (Unity Catalog File Storage)

Volumes are Unity Catalog's mechanism for accessing, storing, and governing files.

### List Volumes in a Schema

```bash
databricks volumes list <catalog> <schema> -p <profile> -o json
```

### Read Volume Contents

```bash
databricks volumes read <catalog>.<schema>.<volume> -p <profile> -o json
```

---

## Functions (UDFs)

### List Functions in a Schema

```bash
databricks functions list <catalog> <schema> -p <profile> -o json
```

### Get Function Details

```bash
databricks functions get <catalog>.<schema>.<function> -p <profile> -o json
```

---

## System Schemas

System schemas provide access to `system.information_schema` and other system-level metadata.

### List System Schemas

```bash
databricks system-schemas list <metastore-id> -p <profile> -o json
```

---

## Connections (External Data Sources)

### List External Connections

```bash
databricks connections list -p <profile> -o json
```

### Get Connection Details

```bash
databricks connections get <connection-name> -p <profile> -o json
```

---

## Lineage

Data lineage is available via the Unity Catalog API. Use it for impact analysis and understanding data flow.

```bash
databricks api get /api/2.0/lineage-tracking/table-lineage \
  -p <profile> -o json \
  --json '{"table_name": "<catalog>.<schema>.<table>"}'
```

**Note**: Lineage requires the user to have `BROWSE` or `SELECT` privilege on the objects. Lineage data shows upstream and downstream dependencies.

---

## Common Exploration Workflows

### Full Schema Discovery

```bash
# 1. List catalogs
databricks catalogs list -p <profile> -o json

# 2. List schemas in target catalog (user chooses catalog)
databricks schemas list <catalog> -p <profile> -o json

# 3. List tables in target schema (user chooses schema)
databricks tables list <catalog> <schema> -p <profile> -o json

# 4. Get details for a specific table (user chooses table)
databricks tables get <catalog>.<schema>.<table> -p <profile> -o json
```

### Table Impact Analysis

```bash
# 1. Check table details and constraints
databricks tables get <catalog>.<schema>.<table> -p <profile> -o json

# 2. Check lineage (upstream/downstream)
databricks api get /api/2.0/lineage-tracking/table-lineage \
  -p <profile> -o json \
  --json '{"table_name": "<catalog>.<schema>.<table>"}'

# 3. Check who has access
databricks grants get TABLE <catalog>.<schema>.<table> -p <profile> -o json
```

---

## Anti-Patterns

1. **Forgetting `-o json`**: Always use JSON output for parseable responses
2. **Using three-part names inconsistently**: Always use `catalog.schema.table` for `tables get`, but `catalog schema` (space-separated) for `tables list`
3. **Ignoring table constraints**: Always check constraints when understanding schema relationships
4. **Not checking volumes**: Volumes are a core Unity Catalog securable — include them in audits
5. **Hardcoding catalog/schema/table names**: Always discover dynamically or use user-provided values
