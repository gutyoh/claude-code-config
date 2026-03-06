# Testing Patterns

## Test Types Overview

| Type | Purpose | Where Defined | When Runs |
|------|---------|---------------|-----------|
| **Generic (data) tests** | Validate data quality on columns/models | YAML (`data_tests:`) | After model builds |
| **Singular (data) tests** | One-off SQL business rule checks | `tests/singular/*.sql` | After model builds |
| **Unit tests** | Validate SQL logic on static inputs | YAML (`unit_tests:`) | Before model builds (dbt Core 1.8+) |

## Generic Tests

### Built-In Tests

Apply to every model's primary key at minimum:

```yaml
models:
  - name: stg_stripe__payments
    columns:
      - name: payment_id
        data_tests:
          - unique
          - not_null
      - name: status
        data_tests:
          - accepted_values:
              values: ['pending', 'completed', 'refunded', 'failed']
      - name: customer_id
        data_tests:
          - relationships:
              to: ref('stg_jaffle_shop__customers')
              field: customer_id
```

### Test Severity

```yaml
data_tests:
  - unique:
      config:
        severity: error  # error (default) or warn
  - not_null:
      config:
        severity: warn
        warn_if: ">10"
        error_if: ">100"
```

### dbt-utils Generic Tests

```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.3.0", "<2.0.0"]
```

Common tests:
```yaml
data_tests:
  - dbt_utils.not_empty_string
  - dbt_utils.expression_is_true:
      expression: "amount >= 0"
  - dbt_utils.unique_combination_of_columns:
      combination_of_columns:
        - customer_id
        - order_date
  - dbt_utils.recency:
      datepart: day
      field: created_at
      interval: 1
```

### dbt-expectations Tests

```yaml
# packages.yml
packages:
  - package: calogica/dbt_expectations
    version: [">=0.10.0", "<0.11.0"]
```

```yaml
data_tests:
  - dbt_expectations.expect_column_values_to_be_between:
      min_value: 0
      max_value: 10000
  - dbt_expectations.expect_column_values_to_match_regex:
      regex: "^[A-Z]{2}\\d{6}$"
  - dbt_expectations.expect_table_row_count_to_be_between:
      min_value: 1
```

## Singular Tests

SQL files in `tests/singular/` that return failing rows. Zero rows = pass.

```sql
-- tests/singular/assert_positive_total_amount.sql
select
    order_id,
    total_amount

from {{ ref('fct_orders') }}
where total_amount < 0
```

Configure singular tests:
```sql
-- tests/singular/assert_orders_have_customers.sql
{{ config(severity='warn', tags=['finance']) }}

select
    o.order_id

from {{ ref('fct_orders') }} as o
left join {{ ref('dim_customers') }} as c
    on o.customer_id = c.customer_id
where c.customer_id is null
```

## Unit Tests

Validate SQL logic before materialization (dbt Core 1.8+).

### When to Write Unit Tests

- Complex SQL: regex, date math, window functions, multi-branch `case when`
- Models with reported bugs (prevent regression)
- Edge cases not yet in production data
- High-criticality public/contracted models
- Before significant refactoring

### Do NOT Unit Test

- Simple `select` / rename models (staging)
- Standard warehouse functions (`min`, `max`, `count`)
- Simple `ref` passthrough

### Syntax

```yaml
# models/marts/finance/_finance__models.yml
unit_tests:
  - name: test_order_total_calculation
    description: "Verify order total includes tax and discount"
    model: fct_orders
    given:
      - input: ref('stg_jaffle_shop__orders')
        rows:
          - {order_id: 1, subtotal: 100.00, tax_rate: 0.08, discount: 10.00}
          - {order_id: 2, subtotal: 50.00, tax_rate: 0.08, discount: 0.00}
      - input: ref('stg_stripe__payments')
        rows:
          - {order_id: 1, amount: 98.00, status: completed}
          - {order_id: 2, amount: 54.00, status: completed}
    expect:
      rows:
        - {order_id: 1, total_amount: 98.00}
        - {order_id: 2, total_amount: 54.00}
```

### Testing Incremental Logic

```yaml
unit_tests:
  - name: test_incremental_filter
    model: fct_events
    overrides:
      macros:
        is_incremental: true
    given:
      - input: ref('stg_events')
        rows:
          - {event_id: 1, created_at: '2024-01-01'}
          - {event_id: 2, created_at: '2024-01-15'}
      - input: this
        rows:
          - {event_id: 0, created_at: '2024-01-10'}
    expect:
      rows:
        - {event_id: 2, created_at: '2024-01-15'}
```

### Running Tests

```bash
dbt test                                          # all tests
dbt test --select "test_type:data"                # data tests only
dbt test --select "test_type:unit"                # unit tests only
dbt test --select "fct_orders"                    # tests for one model
dbt test --select "source:stripe"                 # source tests
dbt test --select "test_type:singular"            # singular tests only
dbt test --select "test_type:generic"             # generic tests only
```

### Best Practices

- Run unit tests **only in dev/CI**, not production (static inputs = no value in prod)
- Build empty parents first: `dbt run --select "model_name" --empty`
- Only mock columns relevant to your test logic
- Use fixture files (`tests/fixtures/`) for complex test data

## Testing Strategy by Layer

| Layer | Required Tests | Recommended |
|-------|---------------|-------------|
| **Sources** | `freshness`, `not_null` + `unique` on PKs | `dbt_utils.recency` |
| **Staging** | `unique` + `not_null` on PK | `accepted_values` on enums |
| **Intermediate** | `unique` + `not_null` on PK if materialized | `expression_is_true` for logic |
| **Marts** | `unique` + `not_null` on PK, `relationships` on FKs | Unit tests for complex logic, contracts on public models |
