# Incremental Patterns

## When to Use Incremental

Use incremental models when full-refresh tables take too long to build. Do NOT start with incremental — graduate to it when needed.

## Incremental Strategies by Platform

| Strategy | Snowflake | BigQuery | Databricks | Redshift | Use Case |
|----------|-----------|----------|------------|----------|----------|
| `merge` | Default | Default | Default | Yes | Upsert (update + insert) on `unique_key` |
| `delete+insert` | Yes | No | Yes | Default (with `unique_key`) | Delete matching rows, insert replacements |
| `append` | Yes | Yes | Yes | Default (no `unique_key`) | Insert-only, no updates (event logs) |
| `insert_overwrite` | No | Yes | Yes (Spark) | No | Replace entire partitions |
| `microbatch` | Yes (1.9+) | Yes (1.9+) | Yes (1.9+) | Yes (1.9+) | Time-series, parallel batch processing |

**Platform default notes:**
- **Snowflake/BigQuery/Databricks**: `merge` is the default strategy
- **Redshift**: `append` is the default when no `unique_key` is set; `delete+insert` is the default when `unique_key` IS set (inherited from dbt-postgres). `merge` is supported but not the default.

## Basic Incremental Pattern

```sql
{{ config(
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='merge',
) }}

with

source as (
    select * from {{ ref('stg_events') }}
),

final as (
    select
        event_id,
        user_id,
        event_type,
        created_at

    from source

    {% if is_incremental() %}
        where created_at > (select max(created_at) from {{ this }})
    {% endif %}
)

select * from final
```

## Merge Strategy (Default)

Updates existing rows and inserts new ones based on `unique_key`.

```sql
{{ config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='merge',
) }}
```

**When to use:** Most fact tables where rows can be updated (order status changes, late-arriving data).

**Caution on Snowflake:** Merge can fail with non-deterministic matches when `unique_key` has duplicates in the source. Use `delete+insert` as an alternative.

## Delete+Insert Strategy

Deletes matching rows first, then inserts all new rows. More predictable than merge.

```sql
{{ config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='delete+insert',
) }}
```

**When to use:** Partition-level replacement on Snowflake. When merge has non-deterministic match issues.

## Append Strategy

Insert-only — never updates or deletes existing rows.

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='append',
) }}
```

**When to use:** Immutable event logs, append-only fact tables. No `unique_key` needed.

## Insert Overwrite Strategy (BigQuery/Spark)

Replaces entire partitions rather than individual rows.

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={
        "field": "event_date",
        "data_type": "date",
        "granularity": "day"
    },
) }}
```

**When to use:** BigQuery partitioned tables. Replacing a full day/month of data is cheaper than row-level merges.

## Microbatch Strategy (dbt Core 1.9+)

Splits data into time-based batches and processes them in parallel. Best for large time-series datasets.

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    unique_key='event_id',
    event_time='created_at',
    begin='2020-01-01',
    batch_size='day',
    lookback=1,
) }}

select
    event_id,
    user_id,
    event_type,
    created_at

from {{ ref('stg_events') }}
```

**Configuration:**
- `event_time`: The timestamp column for batching
- `begin`: Start date for the first batch
- `batch_size`: `hour`, `day`, `month`, `year`
- `lookback`: Number of extra prior batches to reprocess (handles late-arriving data)

**Platform behavior:**
- Snowflake: Uses `delete+insert` per batch
- BigQuery: Uses `insert_overwrite` per batch
- Databricks: Uses `replace_where` per batch

## Incremental Predicates

Limit scans on the destination table for performance:

```sql
{{ config(
    materialized='incremental',
    unique_key='event_id',
    incremental_strategy='merge',
    incremental_predicates=[
        "DBT_INTERNAL_DEST.created_at > dateadd(day, -7, current_date)"
    ],
) }}
```

## on_schema_change

Handle column additions/removals between runs:

| Value | Behavior |
|-------|----------|
| `ignore` (default) | Extra columns silently dropped |
| `append_new_columns` | New columns added, removed columns kept |
| `sync_all_columns` | Schema fully synced (add new, remove old) |
| `fail` | Error if schema changes detected |

```sql
{{ config(
    materialized='incremental',
    unique_key='event_id',
    on_schema_change='append_new_columns',
) }}
```

## Full Refresh

Force a complete rebuild of any incremental model:

```bash
dbt run --select fct_events --full-refresh
```

In the model, `{{ this }}` returns the existing table. During `--full-refresh`, `is_incremental()` returns `false`.

## Best Practices

1. **Always use `unique_key`** for merge/delete+insert strategies to enable proper upsert logic
2. **Filter aggressively** in the `{% if is_incremental() %}` block — only process new/changed data
3. **Use `incremental_predicates`** to limit destination table scans on large tables
4. **Handle late-arriving data** with a lookback window (e.g., `created_at > max(created_at) - interval '3 days'`)
5. **Set `on_schema_change`** explicitly — don't rely on the default `ignore`
6. **Run `--full-refresh` periodically** to catch any drift between incremental and full logic
7. **Prefer `microbatch`** for large time-series fact tables on dbt Core 1.9+
8. **Test incremental logic** with unit tests using `overrides.macros.is_incremental: true`
