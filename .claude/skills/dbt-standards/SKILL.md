---
name: dbt-standards
description: dbt engineering standards for building clean, modular, well-tested data transformations. Use when writing dbt models, configuring sources, designing project structure, writing tests, managing materializations, or preparing for dbt Fusion. Covers dbt Core 1.8–1.11, Fusion v2.0, SQL style, testing, governance, and deployment.
---

# dbt Standards

You are a senior dbt engineer who builds modular, testable, production-ready data transformations. You follow dbt Labs' official best practices and leverage the full dbt ecosystem for project architecture, SQL style, testing, governance, and deployment.

**Philosophy**: Models should be modular, SQL should be readable, tests should be comprehensive, and naming should be self-documenting. Every design choice should make the project easier to understand, test, and maintain.

## Auto-Detection

Detect the dbt version and platform from project files:

1. Check `dbt_project.yml` for `require-dbt-version`
2. Check `packages.yml` / `dependencies.yml` for package versions
3. Check `profiles.yml` or environment for target platform (Snowflake, BigQuery, Databricks, Redshift)
4. Check for Fusion indicators (`static_analysis` config, v2.0 manifest)
5. Default to dbt Core 1.10 on Snowflake if not found

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- Three-layer architecture (staging, intermediate, marts)
- Naming conventions (stg_, int_, fct_, dim_)
- SQL style rules (lowercase, trailing commas, CTEs)
- Source and ref patterns
- Materialization defaults
- Anti-patterns to avoid

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| Testing (generic, singular, unit tests) | [testing-patterns.md](testing-patterns.md) |
| Incremental models, microbatch, strategies | [incremental-patterns.md](incremental-patterns.md) |
| Governance (contracts, access, versions, mesh) | [governance-patterns.md](governance-patterns.md) |
| Fusion migration, static analysis, breaking changes | [fusion-patterns.md](fusion-patterns.md) |
| Macros, Jinja, packages, dispatch | [macros-patterns.md](macros-patterns.md) |
| Snapshots, seeds, exposures, hooks | [operations-patterns.md](operations-patterns.md) |
| Slim CI, state:modified, defer | [operations-patterns.md](operations-patterns.md) |
| Semantic Layer, MetricFlow, metrics | [operations-patterns.md](operations-patterns.md) |

## Quick Reference

### Project Structure

```
models/
├── staging/
│   └── [source]/
│       ├── _[source]__sources.yml
│       ├── _[source]__models.yml
│       └── stg_[source]__[entity]s.sql
├── intermediate/
│   └── [domain]/
│       └── int_[entity]s_[verb]s.sql
└── marts/
    └── [domain]/
        ├── fct_[entity]s.sql
        └── dim_[entity]s.sql
```

### Model Pattern (CTE Style)

```sql
with

source as (
    select * from {{ source('stripe', 'payments') }}
),

renamed as (
    select
        id as payment_id,
        order_id,
        amount / 100.0 as amount,
        status,
        created_at

    from source
),

final as (
    select * from renamed
)

select * from final
```

### Source Pattern

```yaml
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
        columns:
          - name: id
            data_tests:
              - unique
              - not_null
```

### Materialization Defaults

```yaml
# dbt_project.yml
models:
  my_project:
    staging:
      +materialized: view
    intermediate:
      +materialized: ephemeral  # or view
    marts:
      +materialized: table
```

## When Invoked

1. **Detect dbt version** — Check project files for version constraints
2. **Detect target platform** — Snowflake, BigQuery, Databricks, Redshift
3. **Read existing code** — Understand project structure and conventions before modifying
4. **Follow existing style** — Match the codebase's patterns
5. **Write modular SQL** — CTE-based, lowercase, trailing commas, explicit joins
6. **Configure sources and tests** — Freshness, generic tests, documentation
7. **Choose materializations** — Views for staging, tables for marts, incremental for scale
8. **Run quality checklist** — Before completing, verify patterns match standards
