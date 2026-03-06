# Core Principles

## 1. Three-Layer Architecture

Data flows from source-conformed to business-conformed through three layers. Never create circular references between layers.

| Layer | Prefix | Purpose | Materialization |
|-------|--------|---------|-----------------|
| **Staging** | `stg_` | 1:1 with source tables. Rename, cast, clean. No joins. | `view` |
| **Intermediate** | `int_` | Purpose-built transformations. Joins, pivots, aggregations. | `ephemeral` or `view` |
| **Marts** | `fct_` / `dim_` | Business entities. Wide, rich, consumer-ready. | `table` or `incremental` |

**Rules:**
- Staging models select only from `{{ source() }}` — never from `{{ ref() }}`
- Intermediate models select from staging or other intermediate models — never from sources
- Marts select from staging or intermediate — never directly from sources
- Only marts should be queried by end users, dashboards, and BI tools

## 2. Naming Conventions

### Model Names

```
stg_[source]__[entity]s.sql          # staging (double underscore)
int_[entity]s_[verb]s.sql            # intermediate
fct_[entity]s.sql                    # fact tables (events, transactions)
dim_[entity]s.sql                    # dimension tables (entities, attributes)
```

**Examples:**
- `stg_stripe__payments.sql`
- `stg_jaffle_shop__customers.sql`
- `int_payments_pivoted_to_orders.sql`
- `int_customers_aggregated_by_region.sql`
- `fct_orders.sql`
- `dim_customers.sql`

### Column Names

| Type | Convention | Example |
|------|-----------|---------|
| Primary key | `<object>_id` | `customer_id`, `order_id` |
| Foreign key | `<referenced_object>_id` | `customer_id` in `fct_orders` |
| Boolean | `is_` or `has_` prefix | `is_active`, `has_subscription` |
| Timestamp | `<event>_at` (UTC) | `created_at`, `updated_at` |
| Date | `<event>_date` | `created_date`, `shipped_date` |
| Price/money | Decimal, or `_in_cents` suffix | `amount`, `price_in_cents` |
| Counts | `<object>_count` | `order_count`, `session_count` |

**General rules:**
- All `snake_case`
- Pluralize model names (`customers`, not `customer`)
- No abbreviations — spell out full names
- No reserved SQL keywords as column names
- Primary keys are string data types

### Column Ordering

Within a `select` statement, order columns by:
1. Primary key / IDs
2. Foreign keys
3. Strings / categoricals
4. Numerics
5. Booleans
6. Dates
7. Timestamps

---

## 3. SQL Style

### Formatting Rules

- **Lowercase** everything — keywords, functions, column names
- **4-space indentation**
- **Trailing commas** (comma at end of line, not beginning)
- **80-character line limit**
- **Explicit `as`** for all aliases
- **Explicit join types** — `inner join`, `left join` (never bare `join`)
- Use `union all` over `union` unless deduplication is required

### CTE Pattern

Every model uses CTEs. Structure:

```sql
with

-- Import CTEs (one per source/ref)
source as (
    select * from {{ source('jaffle_shop', 'orders') }}
),

customers as (
    select * from {{ ref('stg_jaffle_shop__customers') }}
),

-- Functional CTEs (one logical step each)
orders_with_amounts as (
    select
        order_id,
        customer_id,
        amount / 100.0 as amount,
        status,
        created_at

    from source
    where status != 'deleted'
),

-- Final CTE
final as (
    select
        o.order_id,
        o.customer_id,
        c.customer_name,
        o.amount,
        o.status,
        o.created_at

    from orders_with_amounts as o
    left join customers as c
        on o.customer_id = c.customer_id
)

select * from final
```

**CTE Rules:**
- Import CTEs at the top — one per `ref()` or `source()`
- Functional CTEs — one logical unit of work each, descriptive names
- Final CTE — named `final`, model ends with `select * from final`
- Use Jinja comments (`{# #}`) for notes excluded from compiled SQL
- Prefix columns with CTE name when joining multiple tables

### Grouping and Ordering

- Use **numeric grouping**: `group by 1, 2, 3`
- Fields precede aggregates and window functions in `select`

---

## 4. Source and Ref Patterns

### Sources

Declare all raw tables as sources in YAML. Never hardcode table references.

```yaml
# models/staging/stripe/_stripe__sources.yml
sources:
  - name: stripe
    database: raw
    schema: stripe
    config:
      freshness:
        warn_after: {count: 12, period: hour}
        error_after: {count: 24, period: hour}
      loaded_at_field: _etl_loaded_at
    tables:
      - name: payments
      - name: customers
```

Reference in SQL:
```sql
select * from {{ source('stripe', 'payments') }}
```

### Refs

Reference all models via `{{ ref() }}` — never hardcode schema/table names.

```sql
select * from {{ ref('stg_stripe__payments') }}
```

### Rules

- Every source table gets exactly one staging model (1:1)
- `source()` only appears in staging models
- `ref()` appears in intermediate and marts models
- Never mix `source()` and `ref()` in the same model

---

## 5. Materialization Defaults

### Decision Framework

```
Start with a view
  → When the view takes too long to QUERY → make it a table
    → When the table takes too long to BUILD → make it incremental
```

### Layer Defaults

| Layer | Default | Rationale |
|-------|---------|-----------|
| Staging | `view` | Fresh data, building blocks, rarely queried directly |
| Intermediate | `ephemeral` or `view` | Not queried by end users; ephemeral avoids warehouse objects |
| Marts | `table` | Queried by dashboards and users; needs performance |
| Large marts | `incremental` | When full-refresh tables take too long |

### Materialized Views / Dynamic Tables

For near-real-time use cases where views are too slow but full-refresh tables are overkill:

| Platform | Feature | dbt Config |
|----------|---------|------------|
| **BigQuery** | Materialized View | `materialized='materialized_view'` |
| **Databricks** | Materialized View | `materialized='materialized_view'` |
| **Snowflake** | Dynamic Table | `materialized='dynamic_table'` (not `materialized_view`) |
| **Redshift** | Materialized View | `materialized='materialized_view'` |

**Note:** Snowflake does not support `materialized_view` — use `dynamic_table` instead. Model contracts are not supported on materialized views or dynamic tables.

### Python Models

dbt supports Python models (`.py` files) on Snowflake, BigQuery, Databricks, and Redshift (since dbt Core 1.3, supported in Fusion). Use for ML preprocessing, pandas/PySpark transformations, or logic that's difficult in SQL.

```python
# models/intermediate/int_customers_scored.py
def model(dbt, session):
    dbt.config(materialized="table")
    customers = dbt.ref("stg_jaffle_shop__customers")
    # pandas/PySpark transformations here
    return customers
```

**Limitations:** Python models can only be materialized as `table` or `incremental` (not `view` or `ephemeral`).

### Configure at Folder Level

```yaml
# dbt_project.yml
models:
  my_project:
    staging:
      +materialized: view
    intermediate:
      +materialized: ephemeral
    marts:
      +materialized: table
```

Override per-model only when necessary:
```sql
{{ config(materialized='incremental', unique_key='event_id') }}
```

---

## 6. YAML Style

- **2-space indentation**
- **80-character line limit**
- List items indented
- One `_sources.yml` and one `_models.yml` per source/domain folder
- Use dbt JSON schema with Prettier for validation and formatting

### Model Documentation Pattern

```yaml
# models/staging/stripe/_stripe__models.yml
models:
  - name: stg_stripe__payments
    description: Staged Stripe payments with renamed columns and cents-to-dollars conversion.
    columns:
      - name: payment_id
        description: Primary key.
        data_tests:
          - unique
          - not_null
      - name: amount
        description: Payment amount in dollars.
```

---

## 7. Jinja Style

- Spaces inside delimiters: `{{ this }}` not `{{this}}`
- 4-space indentation inside Jinja blocks
- Newlines to separate logical blocks
- Readability over compiled SQL perfection

```jinja
{% macro cents_to_dollars(column_name, precision=2) %}
    round({{ column_name }} / 100.0, {{ precision }})
{% endmacro %}
```

---

## 8. Folder Organization

```
dbt_project/
├── dbt_project.yml
├── packages.yml
├── profiles.yml              # local only, gitignored
├── models/
│   ├── staging/
│   │   └── [source]/
│   │       ├── _[source]__sources.yml
│   │       ├── _[source]__models.yml
│   │       └── stg_[source]__[entity]s.sql
│   ├── intermediate/
│   │   └── [domain]/
│   │       ├── _int__models.yml
│   │       └── int_[entity]s_[verb]s.sql
│   └── marts/
│       └── [domain]/
│           ├── _[domain]__models.yml
│           ├── fct_[entity]s.sql
│           └── dim_[entity]s.sql
├── tests/
│   ├── generic/              # custom generic tests
│   └── singular/             # one-off SQL tests
├── macros/
│   └── [macro_name].sql
├── seeds/
│   └── [seed_name].csv
├── snapshots/
│   └── [snapshot_name].yml   # v1.9+ YAML snapshots
└── analyses/
    └── [analysis_name].sql
```

---

## 9. Medallion Architecture Mapping (Databricks / Lakehouse)

The dbt three-layer architecture maps directly to the Databricks medallion architecture. They are the same pattern with different naming.

| dbt Layer | Medallion Layer | Purpose | dbt Prefix | Unity Catalog Schema |
|-----------|----------------|---------|------------|---------------------|
| **Staging** | **Bronze** | Raw data, 1:1 with source. Rename, cast, clean. | `stg_` | `bronze` or `raw` |
| **Intermediate** | **Silver** | Cleaned, joined, business logic applied. | `int_` | `silver` or `curated` |
| **Marts** | **Gold** | Aggregated, consumer-ready. Dashboards, BI, ML. | `fct_` / `dim_` | `gold` or `analytics` |

### Unity Catalog Organization

```
catalog: my_project_dev          # environment-specific catalog
├── schema: bronze               # staging models
│   └── stg_stripe__payments
├── schema: silver               # intermediate models
│   └── int_payments_pivoted
└── schema: gold                 # marts
    ├── fct_orders
    └── dim_customers
```

### dbt Configuration for Medallion

```yaml
# dbt_project.yml
models:
  my_project:
    staging:
      +materialized: view
      +schema: bronze
    intermediate:
      +materialized: view
      +schema: silver
    marts:
      +materialized: table
      +schema: gold
```

### Custom Schema Macro for Medallion

By default, dbt prepends `target.schema` to custom schemas. Override to use clean medallion names:

```sql
-- macros/generate_schema_name.sql
{% macro generate_schema_name(custom_schema_name, node) %}
    {% if custom_schema_name is none %}
        {{ target.schema }}
    {% elif target.name == 'prod' %}
        {{ custom_schema_name | trim }}
    {% else %}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {% endif %}
{% endmacro %}
```

This produces:
- **prod**: `bronze`, `silver`, `gold` (clean names)
- **dev**: `dev_jsmith_bronze`, `dev_jsmith_silver`, `dev_jsmith_gold` (isolated)

### Databricks-Specific Best Practices

- Use **Delta Lake** tables (default on Databricks) for all materializations
- Use **liquid clustering** (`cluster_by`) instead of partitioning for Databricks SQL:
  ```sql
  {{ config(
      materialized='incremental',
      unique_key='event_id',
      incremental_strategy='merge',
      cluster_by=['event_date', 'customer_id'],
  ) }}
  ```
- Use **`incremental_strategy='merge'`** (default) or `'replace_where'` for microbatch
- Set **`file_format: delta`** (default since dbt-databricks 1.6+)
- Use **Unity Catalog** three-level namespace: `catalog.schema.table`
- Store raw/bronze data in **external locations** or **managed tables** depending on governance needs

### Access Control Mapping

| Medallion Layer | Who Accesses | dbt Access Modifier |
|----------------|-------------|---------------------|
| Bronze | Data engineers | `private` |
| Silver | Data engineers, data scientists | `protected` |
| Gold | Analysts, BI tools, applications | `public` |

---

## Anti-Patterns to Avoid

1. **Hardcoded table references**: Never write `raw.stripe.payments` — use `{{ source() }}` and `{{ ref() }}`
2. **Source references outside staging**: Only staging models should use `{{ source() }}` — everything else uses `{{ ref() }}`
3. **Joins in staging**: Staging is 1:1 with source tables — rename, cast, clean only
4. **Missing tests**: Every model needs at least `unique` + `not_null` on its primary key
5. **`select *` in final models**: Explicitly list columns in marts to control the contract
6. **Abbreviations in names**: `cust` instead of `customer`, `amt` instead of `amount`
7. **Uppercase SQL**: dbt convention is all lowercase
8. **Leading commas**: dbt convention is trailing commas
9. **Missing `source()` freshness**: All sources should have `loaded_at_field` and freshness thresholds
10. **Overly deep DAGs**: If a model depends on 10+ upstream models, consider simplifying the intermediate layer
11. **Business logic in staging**: Staging is for cleaning, not for business rules — push logic to intermediate/marts
12. **Using `--models` flag**: Deprecated — use `--select` / `-s` (required for Fusion)
