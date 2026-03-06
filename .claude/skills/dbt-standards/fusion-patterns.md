# Fusion Patterns

## What Is dbt Fusion?

The dbt Fusion engine is a **complete rewrite of dbt in Rust** (v2.0), replacing the Python-based dbt Core. Launched as public beta May 28, 2025. Key characteristics:

- **30x faster** compilation and execution than dbt Core
- **Native SQL comprehension** across Snowflake, BigQuery, Databricks, Redshift dialects
- **Static analysis** catches SQL errors at compile time without warehouse execution
- **Rust-based adapters** using Apache Arrow/ADBC (not Python adapters)
- **v20 manifest** format (dbt Core produces v12) — not forward-compatible
- **Elastic License v2** (ELv2) — source-available, free for most use cases

## Static Analysis

Fusion's signature feature: validates SQL before execution.

### Modes

| Mode | Behavior | Use For |
|------|----------|---------|
| `baseline` (default) | Analyze SQL, warnings only, no blocking | Migration from dbt Core |
| `strict` | Analyze all SQL, block execution on errors | Critical marts, maximum safety |
| `off` | Skip SQL analysis | Models with unsupported SQL features |

### Configuration

```yaml
# dbt_project.yml
models:
  my_project:
    staging:
      +static_analysis: baseline
    marts:
      +static_analysis: strict
```

Per model:
```sql
{{ config(static_analysis='off') }}
select user_id, my_custom_udf(ip_address) as cleaned_ip
from {{ ref('stg_events') }}
```

CLI override:
```bash
dbt run --static-analysis off
dbt run --static-analysis baseline
```

### Cascading Rules

- Downstream models cannot be stricter than their parents
- `strict` parent -> child can be `strict`, `baseline`, or `off`
- `baseline` parent -> child can be `baseline` or `off` (not `strict`)
- `off` parent -> child must be `off`

### What Static Analysis Catches

**Baseline mode:**
- SQL syntax errors
- Undefined CTEs
- Column reference errors (in some cases)

**Strict mode (additional):**
- Data type mismatches
- Function signature validation
- Column-level lineage
- Complete schema validation

### Unsupported SQL Features (Requires `off`)

- Advanced data types: `STRUCT`, `ARRAY`, `GEOGRAPHY`
- Platform-specific functions: `AI.PREDICT`, `JSON_FLATTEN`, `st_pointfromgeohash`
- Custom UDFs not recognized by the SQL parser

## Breaking Changes from dbt Core

### CLI Flags

| Flag | Change |
|------|--------|
| `--models` / `-m` | **Removed** — use `--select` / `-s` |
| `--resource-type` | Renamed to `--resource-types` |
| `--print` / `--no-print` | Removed (silently ignored) |
| `--partial-parse` | Removed (Fusion always incrementally parses) |
| `--cache-selected-only` | Removed |
| `--single-threaded` | Removed |

### Stricter Parsing

Fusion fails at **parse time** (not compile/runtime) for:

```jinja
{# Nonexistent macro — parse error #}
{{ my_nonexistent_macro('amount') }}

{# Nonexistent adapter method — parse error #}
{{ adapter.does_not_exist() }}

{# Undefined variable without default — parse error #}
select {{ var('does_not_exist') }} as my_column
```

**Fix:** Ensure all macros, adapter methods, and variables exist before referencing them.

### YAML Anchors

Standalone anchors at YAML root level now error. Move under `anchors:` key:

```yaml
# BEFORE (dbt Core — works)
id_column: &id_column
  name: id
  data_tests:
    - not_null

models:
  - name: my_model
    columns:
      - *id_column

# AFTER (Fusion — required)
anchors:
  - &id_column
      name: id
      data_tests:
        - not_null

models:
  - name: my_model
    columns:
      - *id_column
```

### config.get() for Meta

`config.get('meta')` and `config.require('meta')` no longer work. Use:

```jinja
{% set owner = config.meta_get('owner') %}
{% set has_pii = config.meta_require('pii') %}
```

### Behavior Change Flags

All `flags:` in `dbt_project.yml` are removed. You cannot opt out of new behaviors.

### Manifest Incompatibility

- Fusion produces **v20** manifests; dbt Core produces **v12**
- dbt Core **cannot read** Fusion manifests
- Features like `state:modified`, `--defer`, cross-environment docs generation break if environments mix Core and Fusion
- **Upgrade all environments simultaneously**

### Threading

- Snowflake/Databricks: Fusion auto-optimizes parallelism, ignores user thread settings
- BigQuery/Redshift: Respects user threads; use `--threads 0` for dynamic optimization

### Unit Test Execution Order

`dbt build` runs **all unit tests first**, then builds the rest of the DAG (dbt Core ran them in lineage order).

### Seed CSV Parsing

Extra trailing commas no longer create empty columns:
```csv
animal,
dog,
cat,
```
dbt Core: creates columns `animal` + empty `b`. Fusion: creates only `animal`.

## Fusion Readiness Checklist

1. **Resolve all deprecation warnings** from dbt Core v1.10+
2. **Remove `flags:` block** from `dbt_project.yml`
3. **Replace `--models` with `--select`** in all job definitions and scripts
4. **Move YAML anchors** under `anchors:` key
5. **Replace `config.get('meta')`** with `config.meta_get()`
6. **Check package compatibility** — packages must declare `require-dbt-version: ">=1.10.0,<3.0.0"` for Fusion
7. **Run `dbt-autofix`** helper tool (`pip install dbt-autofix && dbt-autofix`) — automatically fixes common Fusion incompatibilities (YAML anchors, deprecated flags, config syntax)
8. **Test with Fusion CLI locally** before upgrading production
9. **Upgrade all environments** (dev, staging, prod) at the same time to avoid manifest conflicts
10. **Set `static_analysis: baseline`** as starting point, graduate to `strict`

## Fusion CLI Installation

```bash
# Install Fusion CLI
pip install dbt-fusion

# The Fusion CLI binary is `dbtf` (alias for `dbt` when Fusion is installed)
# Both commands work — `dbtf` is useful when you have dbt Core installed alongside
dbtf run
dbtf build
dbtf test

# Or via the dbt VS Code extension (includes LSP features)
```

### Fusion-Exclusive Features

- Real-time SQL validation in VS Code/Cursor
- CTE preview (hover to see intermediate results)
- Column-level go-to-definition (strict mode)
- State-aware orchestration (only rebuild models with new data)
- Native SQL comprehension across dialects

## Writing Fusion-Compatible Code Today

Even on dbt Core, write code that will migrate cleanly:

1. Use `--select` not `--models`
2. Use `anchors:` key for YAML anchors
3. Use `config.meta_get()` instead of `config.get('meta')` (requires dbt Core v1.10+)
4. Ensure all macros and variables exist (no undefined references)
5. Add `require-dbt-version: ">=1.8.0,<3.0.0"` to packages
6. Avoid deprecated behavior change flags
7. Set `static_analysis: baseline` in `dbt_project.yml` (ignored by dbt Core, used by Fusion)
