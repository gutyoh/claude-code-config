# Governance Patterns

## Model Access

Control who can `ref()` your models. Access modifiers restrict cross-group and cross-project references.

| Access | Who Can Ref | Visible in Docs | Use For |
|--------|-------------|-----------------|---------|
| `private` | Same group only | Group members only | Implementation details, intermediate models |
| `protected` | Same project | Project members | Internal models used across groups |
| `public` | Any project (dbt Mesh) | Everyone | Stable data products, APIs for downstream teams |

### Configuration

```yaml
# In model YAML
models:
  - name: fct_orders
    config:
      access: public
      group: finance

  - name: int_orders_enriched
    config:
      access: private
      group: finance
```

```yaml
# In dbt_project.yml (folder-level default)
models:
  my_project:
    intermediate:
      +access: private
    marts:
      +access: protected
```

## Groups

Groups define ownership boundaries. Combine with access modifiers for governance.

```yaml
# models/_groups.yml
groups:
  - name: finance
    owner:
      name: Finance Analytics
      email: finance-analytics@company.com

  - name: marketing
    owner:
      name: Marketing Analytics
      email: marketing-analytics@company.com
```

**Rules:**
- Models with only intra-group dependencies should be `private`
- Models with cross-group dependencies should be `protected`
- Models consumed by external projects should be `public`
- Terminal nodes in a group's DAG (marts) are typically `protected` or `public`

## Model Contracts

Guarantee the shape of a model (column names, data types, constraints) at build time. Prevents downstream breakage.

### When to Use Contracts

- Public models consumed by other teams/projects
- Models backing dashboards or BI tools
- Models with defined SLAs
- Models versioned for consumers

### Configuration

```yaml
models:
  - name: dim_customers
    config:
      contract:
        enforced: true
    columns:
      - name: customer_id
        data_type: int
        constraints:
          - type: not_null
          - type: primary_key
      - name: customer_name
        data_type: varchar(256)
        constraints:
          - type: not_null
      - name: email
        data_type: varchar(512)
      - name: is_active
        data_type: boolean
      - name: created_at
        data_type: timestamp
```

### Constraint Support by Platform

| Constraint | Snowflake | BigQuery | Databricks | Redshift | Postgres |
|-----------|-----------|----------|------------|----------|----------|
| `not_null` | Enforced | Enforced | Enforced | Enforced | Enforced |
| `primary_key` | Metadata | Metadata | Metadata | Metadata | Enforced |
| `foreign_key` | Metadata | Metadata | Metadata | Metadata | Enforced |
| `unique` | Metadata | N/A | Metadata | Metadata | Enforced |
| `check` | Metadata | N/A | Metadata | Metadata | Enforced |

"Metadata" = defined in DDL but not enforced by the warehouse. Still valuable for documentation and governance tooling.

### Contract Rules

- When `enforced: true`, **every column** must declare `name` and `data_type`
- Columns are reordered to match the contract definition
- Adding/removing columns from a contracted model is a breaking change
- Contracts work with `table` and `incremental` materializations
- Views support column name/type checks but not constraints
- Not supported: `ephemeral`, `materialized_view`, Python models

## Model Versions

Version contracted models when making breaking changes, allowing consumers to migrate gracefully.

```yaml
models:
  - name: dim_customers
    latest_version: 2
    config:
      contract:
        enforced: true
    columns:
      - name: customer_id
        data_type: int
      - name: customer_name
        data_type: varchar(256)
      - name: email
        data_type: varchar(512)

    versions:
      - v: 2
        columns:
          - include: all
          - name: region
            data_type: varchar(128)

      - v: 1
        columns:
          - include: all
          - name: country_name
            data_type: varchar(128)
```

Reference versioned models:
```sql
select * from {{ ref('dim_customers', v=2) }}
select * from {{ ref('dim_customers') }}  -- resolves to latest_version
```

### Breaking Changes Detected

- Removed columns
- Changed `data_type` on existing columns
- Modified or removed constraints
- Deleted, renamed, or disabled contracted models

## dbt Mesh (Cross-Project References)

For organizations with multiple dbt projects sharing models.

### Project Dependencies

```yaml
# dependencies.yml (downstream project)
projects:
  - name: jaffle_shop_core
    dbt_cloud:
      project_id: "12345"
```

### Cross-Project Ref

```sql
-- In the downstream project
select * from {{ ref('jaffle_shop_core', 'fct_orders') }}
```

Only `public` models can be referenced across projects.

### Best Practices

- Treat public models as stable APIs — version them
- Enforce contracts on all public models
- Use groups to define team ownership
- Start with `protected` access, promote to `public` only when needed
- Document public models thoroughly — they are your data products
