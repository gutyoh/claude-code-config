# Macros & Jinja Patterns

## Macro Basics

Macros are reusable Jinja functions stored in `macros/*.sql`. They generate SQL at compile time.

### Defining Macros

```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name, precision=2) %}
    round({{ column_name }} / 100.0, {{ precision }})
{% endmacro %}
```

### Using Macros

```sql
select
    payment_id,
    {{ cents_to_dollars('amount_cents') }} as amount

from {{ ref('stg_stripe__payments') }}
```

### Macro File Organization

```
macros/
├── cents_to_dollars.sql
├── generate_schema_name.sql
├── get_custom_schema.sql
└── tests/
    └── test_cents_to_dollars.sql
```

One macro per file. Name the file after the macro.

## Common Macro Patterns

### Generate Schema Name

Override the default schema naming to include custom schemas:

```sql
-- macros/generate_schema_name.sql
{% macro generate_schema_name(custom_schema_name, node) %}
    {% set default_schema = target.schema %}

    {% if custom_schema_name is none %}
        {{ default_schema }}
    {% else %}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {% endif %}
{% endmacro %}
```

### Grant Permissions Post-Hook

```sql
-- macros/grant_select.sql
{% macro grant_select(role) %}
    grant select on {{ this }} to role {{ role }}
{% endmacro %}
```

```yaml
# dbt_project.yml
models:
  my_project:
    marts:
      +post-hook:
        - "{{ grant_select('analytics_reader') }}"
```

### Logging Macro

```sql
-- macros/log_model_info.sql
{% macro log_model_info() %}
    {{ log("Building model: " ~ this ~ " at " ~ run_started_at, info=true) }}
{% endmacro %}
```

## Adapter Dispatch

Write cross-platform macros that adapt to the target warehouse:

```sql
-- macros/datediff.sql
{% macro datediff(datepart, start_date, end_date) %}
    {{ return(adapter.dispatch('datediff', 'my_project')(datepart, start_date, end_date)) }}
{% endmacro %}

{% macro default__datediff(datepart, start_date, end_date) %}
    datediff({{ datepart }}, {{ start_date }}, {{ end_date }})
{% endmacro %}

{% macro bigquery__datediff(datepart, start_date, end_date) %}
    date_diff({{ end_date }}, {{ start_date }}, {{ datepart }})
{% endmacro %}
```

## Jinja Best Practices

### Spacing and Formatting

```jinja
{# CORRECT: Spaces inside delimiters #}
{{ ref('stg_orders') }}
{% if is_incremental() %}
{% set my_var = 'value' %}

{# WRONG: No spaces #}
{{ref('stg_orders')}}
{%if is_incremental()%}
```

### Indentation

4-space indentation inside Jinja blocks:

```jinja
{% if target.name == 'prod' %}
    select *
    from {{ ref('fct_orders') }}
    where created_at > '2020-01-01'
{% else %}
    select *
    from {{ ref('fct_orders') }}
    limit 100
{% endif %}
```

### Comments

Use Jinja comments for notes excluded from compiled SQL:

```sql
{# This comment won't appear in the warehouse query log #}
select
    order_id,
    -- This SQL comment WILL appear in the compiled query
    customer_id

from {{ ref('stg_orders') }}
```

### Whitespace Control

Don't obsess over compiled SQL whitespace. Readability of source code matters more:

```jinja
{# Acceptable — focus on readable source #}
{% for payment_method in ['credit_card', 'bank_transfer', 'gift_card'] %}
    sum(case when payment_method = '{{ payment_method }}' then amount end)
        as {{ payment_method }}_amount
    {% if not loop.last %},{% endif %}
{% endfor %}
```

## Essential Packages

### dbt-utils

The most widely used dbt package. Utility macros and generic tests.

```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.3.0", "<2.0.0"]
```

Key macros:
- `{{ dbt_utils.star(from=ref('stg_orders')) }}` — select all columns
- `{{ dbt_utils.generate_surrogate_key(['order_id', 'line_item_id']) }}` — generate surrogate keys (renamed from `surrogate_key` in dbt-utils v1.0)
- `{{ dbt_utils.pivot('status', dbt_utils.get_column_values(ref('stg_orders'), 'status')) }}` — pivot columns
- `{{ dbt_utils.union_relations(relations=[ref('model_a'), ref('model_b')]) }}` — union models
- `{{ dbt_utils.date_spine(datepart='day', start_date="'2020-01-01'", end_date="current_date") }}` — generate date spine

Key tests:
- `dbt_utils.unique_combination_of_columns`
- `dbt_utils.expression_is_true`
- `dbt_utils.not_empty_string`
- `dbt_utils.recency`
- `dbt_utils.at_least_one`

### dbt-expectations

Great Expectations-inspired data quality tests:

```yaml
packages:
  - package: calogica/dbt_expectations
    version: [">=0.10.0", "<0.11.0"]
```

### dbt-audit-helper

Compare model outputs during refactoring:

```yaml
packages:
  - package: dbt-labs/audit_helper
    version: [">=0.12.0", "<1.0.0"]
```

### codegen

Generate YAML and SQL boilerplate:

```yaml
packages:
  - package: dbt-labs/codegen
    version: [">=0.12.0", "<1.0.0"]
```

```bash
dbt run-operation generate_source --args '{"schema_name": "raw", "database_name": "raw_db"}'
dbt run-operation generate_model_yaml --args '{"model_names": ["stg_stripe__payments"]}'
```

## Package Compatibility with Fusion

Packages must declare `require-dbt-version: ">=1.10.0,<3.0.0"` (or similar) to be Fusion-compatible. Check the [dbt package hub](https://hub.getdbt.com/) for the Fusion compatibility badge.

## Run Operations

Execute macros directly from the CLI:

```bash
dbt run-operation my_macro --args '{"arg1": "value1"}'
dbt run-operation grant_select --args '{"role": "analytics_reader"}'
```
