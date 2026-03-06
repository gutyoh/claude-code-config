# Operations Patterns

## Snapshots

Snapshots implement Type-2 Slowly Changing Dimensions (SCD2) to track historical changes in mutable tables.

### YAML Configuration (dbt Core 1.9+, recommended)

```yaml
# snapshots/orders_snapshot.yml
snapshots:
  - name: orders_snapshot
    relation: ref('stg_jaffle_shop__orders')
    config:
      schema: snapshots
      unique_key: order_id
      strategy: timestamp
      updated_at: updated_at
      hard_deletes: invalidate  # v1.9+ (replaces legacy invalidate_hard_deletes)
```

### Strategies

**Timestamp (recommended):**
```yaml
config:
  strategy: timestamp
  updated_at: updated_at  # column to detect changes
```

**Check (compare column values):**
```yaml
config:
  strategy: check
  check_cols: ['status', 'amount']  # or 'all'
```

### Hard Deletes

```yaml
config:
  hard_deletes: 'new_record'  # creates row with dbt_is_deleted = true
  # or
  hard_deletes: 'invalidate'  # sets dbt_valid_to on deleted rows
```

### Custom Meta Columns

```yaml
config:
  snapshot_meta_column_names:
    dbt_valid_from: valid_from
    dbt_valid_to: valid_to
    dbt_scd_id: scd_id
  dbt_valid_to_current: "cast('9999-12-31' as date)"
```

### Running Snapshots

```bash
dbt snapshot
dbt snapshot --select orders_snapshot
```

### Best Practices

- Prefer `timestamp` strategy — handles schema changes more robustly
- Add `unique` + `not_null` tests on snapshot `unique_key`
- Run snapshots on a schedule (hourly to daily)
- Store in a dedicated `snapshots` schema
- Use `dbt_valid_to_current` for easier date range filtering

---

## Seeds

Static CSV files loaded into your warehouse. Use for small lookup tables and reference data.

```
seeds/
├── country_codes.csv
└── employee_mapping.csv
```

### Configuration

```yaml
# dbt_project.yml
seeds:
  my_project:
    +schema: seeds
    country_codes:
      +column_types:
        country_code: varchar(2)
        country_name: varchar(100)
```

### Running Seeds

```bash
dbt seed
dbt seed --select country_codes
dbt seed --full-refresh  # drop and recreate
```

### Best Practices

- Seeds are for small, static data (< 1000 rows)
- Version control the CSV files
- Specify `column_types` to avoid type inference issues
- Do NOT use seeds for large datasets — use sources instead
- Reference seeds via `{{ ref('country_codes') }}`

---

## Exposures

Document downstream consumers of your dbt models (dashboards, ML pipelines, applications).

```yaml
# models/marts/_exposures.yml
exposures:
  - name: weekly_revenue_dashboard
    description: Revenue dashboard viewed by finance leadership.
    type: dashboard
    maturity: high
    url: https://bi.company.com/dashboards/123
    depends_on:
      - ref('fct_orders')
      - ref('dim_customers')
    owner:
      name: Finance Analytics
      email: finance@company.com
```

### Exposure Types

- `dashboard` — BI dashboards
- `notebook` — Jupyter/Databricks notebooks
- `analysis` — Ad-hoc analysis
- `ml` — Machine learning models
- `application` — Software applications

### Benefits

- Lineage visibility: see what depends on your models
- Impact analysis: know which dashboards break if you change a model
- Ownership: document who owns downstream consumers

---

## Analyses

SQL files that compile but don't create warehouse objects. For ad-hoc queries and reporting.

```sql
-- analyses/monthly_revenue.sql
select
    date_trunc('month', order_date) as month,
    sum(amount) as total_revenue

from {{ ref('fct_orders') }}
group by 1
order by 1 desc
```

Run with:
```bash
dbt compile --select "analysis:monthly_revenue"
```

Then copy the compiled SQL from `target/compiled/` and run it manually.

---

## Hooks

SQL executed at specific points during dbt runs.

### Hook Types

| Hook | When | Scope |
|------|------|-------|
| `pre-hook` | Before a model/seed/snapshot builds | Per model |
| `post-hook` | After a model/seed/snapshot builds | Per model |
| `on-run-start` | At the start of `dbt run/build/seed/snapshot/test` | Entire run |
| `on-run-end` | At the end of `dbt run/build/seed/snapshot/test` | Entire run |

### Configuration

```yaml
# dbt_project.yml

# Run-level hooks
on-run-start:
  - "{{ log('Starting dbt run', info=true) }}"
  - "create schema if not exists {{ target.schema }}_staging"

on-run-end:
  - "grant usage on schema {{ target.schema }} to role analytics_reader"

# Model-level hooks
models:
  my_project:
    marts:
      +post-hook:
        - "grant select on {{ this }} to role analytics_reader"
        - "analyze {{ this }}"
```

Per-model in SQL:
```sql
{{ config(
    post_hook="grant select on {{ this }} to role analytics_reader"
) }}
```

### Common Use Cases

- Grant permissions after building models
- Analyze/optimize tables after builds
- Create UDFs or stored procedures at run start
- Log run metadata
- Vacuum/cluster tables (Redshift/Databricks)
- Set session parameters

### Best Practices

- Keep hooks simple and idempotent
- Use macros for complex hook logic
- Test hooks in dev before production
- Document hook side effects
- Prefer `post-hook` over `on-run-end` for model-specific actions

---

## Source Freshness

Monitor data pipeline health by checking when sources were last updated.

### Configuration

```yaml
sources:
  - name: stripe
    config:
      freshness:
        warn_after: {count: 12, period: hour}
        error_after: {count: 24, period: hour}
      loaded_at_field: _etl_loaded_at
    tables:
      - name: payments
      - name: customers
        config:
          freshness:
            warn_after: {count: 6, period: hour}
      - name: products
        config:
          freshness: null  # skip freshness check
```

### Filter for Performance

```yaml
config:
  freshness:
    warn_after: {count: 12, period: hour}
  filter: _etl_loaded_at >= date_sub(current_date(), interval 1 day)
```

### Running Freshness Checks

```bash
dbt source freshness
dbt source freshness --select "source:stripe"
dbt source freshness --select "source:stripe.payments"
```

### Conditional Runs Based on Freshness

```bash
# Run only models whose sources have fresh data
dbt build --select "source_status:fresher+"
```

### Best Practices

- Run freshness checks at least 2x the frequency of your lowest SLA
- Use `filter` on large tables to avoid expensive full scans
- Set `freshness: null` on tables without a reliable `loaded_at` column
- Integrate freshness checks into your job scheduler

---

## Slim CI / State-Aware Selection

The most important CI/CD pattern for dbt at scale. Compare against production artifacts to only build/test changed models.

### Core Commands

```bash
# Build only modified models + their downstream dependents
dbt build --select "state:modified+" --defer --state path/to/prod/artifacts

# Test only modified models + downstream
dbt test --select "state:modified+" --defer --state path/to/prod/artifacts

# Run only modified models (no downstream)
dbt run --select "state:modified" --defer --state path/to/prod/artifacts
```

### How It Works

1. **`--state`**: Points to a directory containing `manifest.json` from a previous production run
2. **`state:modified`**: Selects only models whose SQL, config, or upstream dependencies have changed
3. **`+` suffix**: Includes downstream dependents (the "blast radius")
4. **`--defer`**: If a model isn't selected (unchanged), dbt resolves `{{ ref() }}` against the production environment instead of failing

### CI Job Pattern

```bash
# 1. Fetch production artifacts (manifest.json, run_results.json)
# Download from your CI artifact storage (S3, GCS, GitHub Actions artifacts, etc.)
mkdir -p prod_artifacts
cp /path/to/prod/target/manifest.json ./prod_artifacts/
cp /path/to/prod/target/run_results.json ./prod_artifacts/

# 2. Run slim CI
dbt build \
  --select "state:modified+" \
  --defer \
  --state ./prod_artifacts \
  --fail-fast
```

### With `--empty` for Cost Savings

Build schema-only versions of modified models (zero rows) to validate SQL without warehouse compute:

```bash
dbt run --select "state:modified+" --defer --state ./prod_artifacts --empty
dbt test --select "state:modified+,test_type:unit" --defer --state ./prod_artifacts
```

### Best Practices

- Persist `manifest.json` and `run_results.json` from production runs as CI artifacts
- Use `--fail-fast` in CI to abort on first failure
- Clone incremental models before testing to avoid full-refresh in CI
- Combine with `source_status:fresher+` for freshness-aware orchestration
- In dbt Cloud, CI jobs automatically defer to the production environment

---

## Semantic Layer (MetricFlow)

The dbt Semantic Layer allows you to define business metrics centrally in YAML using MetricFlow. Metrics are defined once and queried consistently across BI tools, APIs, and AI agents.

### Semantic Models

Define the semantic structure on top of your mart models:

```yaml
semantic_models:
  - name: orders
    defaults:
      agg_time_dimension: order_date
    model: ref('fct_orders')
    entities:
      - name: order_id
        type: primary
      - name: customer_id
        type: foreign
    dimensions:
      - name: order_date
        type: time
        type_params:
          time_granularity: day
      - name: status
        type: categorical
    measures:
      - name: order_total
        agg: sum
        expr: amount
      - name: order_count
        agg: count
```

### Metrics

```yaml
metrics:
  - name: revenue
    description: Total revenue from completed orders.
    type: simple
    label: Revenue
    type_params:
      measure: order_total
    filter:
      - "{{ Dimension('order_id__status') }} = 'completed'"

  - name: revenue_growth
    description: Month-over-month revenue growth.
    type: derived
    type_params:
      expr: (current_revenue - prior_revenue) / prior_revenue
      metrics:
        - name: revenue
          alias: current_revenue
        - name: revenue
          alias: prior_revenue
          offset_window: 1 month
```

### MetricFlow Commands

```bash
dbt sl list metrics                     # list all metrics
dbt sl list dimensions --metrics revenue # dimensions for a metric
dbt sl query --metrics revenue --group-by order_date__month  # query
```

### Key Concepts

- **Semantic models**: YAML abstractions on top of dbt models with entities, dimensions, and measures
- **Metrics**: Business definitions built from measures (simple, derived, cumulative, ratio)
- **Saved queries**: Reusable query definitions for common metric requests
- **Exports**: Materialize saved queries into your warehouse via dbt jobs
- MetricFlow in dbt Core works locally; the full Semantic Layer API (for BI tool integration) requires dbt Cloud
