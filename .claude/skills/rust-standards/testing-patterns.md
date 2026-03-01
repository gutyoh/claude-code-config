# Testing Patterns

## Unit Tests

### Test Module Convention

Tests live in a `tests/` directory, NOT inside source modules (unless explicitly required).

```rust
// tests/config.rs
use mylib::config::Config;

#[test]
fn parse_valid_config() {
    let config = Config::from_str("workers = 4").unwrap();
    assert_eq!(config.workers, 4);
}

#[test]
fn parse_invalid_config_returns_error() {
    let result = Config::from_str("workers = -1");
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("invalid value"));
}
```

### Naming Conventions

```rust
// Pattern: <function_under_test>_<scenario>_<expected_result>
#[test]
fn parse_empty_input_returns_default() { ... }

#[test]
fn process_batch_with_zero_items_succeeds() { ... }

#[test]
fn validate_negative_port_returns_error() { ... }
```

---

## Testing with `pretty_assertions`

Use `pretty_assertions` for readable diff output on failures:

```rust
use pretty_assertions::assert_eq;

#[test]
fn serialize_roundtrip() {
    let original = Config { name: "test".into(), workers: 4 };
    let json = serde_json::to_string(&original).unwrap();
    let deserialized: Config = serde_json::from_str(&json).unwrap();
    assert_eq!(original, deserialized);
}
```

---

## Snapshot Testing (insta)

For output that changes often or is complex to assert manually:

```rust
use insta::assert_snapshot;
use insta::assert_debug_snapshot;

#[test]
fn format_error_message() {
    let error = ParseError::new("bad input", 42);
    assert_snapshot!(error.to_string());
}

#[test]
fn parse_complex_structure() {
    let result = parse("complex input");
    assert_debug_snapshot!(result);
}
```

Run `cargo insta review` to accept/reject snapshot changes.

---

## Data-Driven Tests (datatest-stable)

Test many cases from files (the pattern monty uses):

```rust
// tests/datatest_runner.rs
use std::path::Path;

use datatest_stable::harness;

fn run_test_case(path: &Path) -> datatest_stable::Result<()> {
    let source = std::fs::read_to_string(path)?;
    let expected = extract_expected_output(&source);
    let result = execute(&source)?;
    assert_eq!(result, expected);
    Ok(())
}

harness!(run_test_case, "test_cases", r".*\.txt$");
```

---

## Integration Tests

### Test Directory Structure

```
tests/
├── common/
│   └── mod.rs          # Shared test utilities
├── integration_basic.rs
├── integration_async.rs
└── snapshots/          # insta snapshots
```

### Shared Test Utilities

```rust
// tests/common/mod.rs
pub fn create_test_config() -> Config {
    Config {
        name: "test".into(),
        workers: 1,
        port: 0,  // Random available port
    }
}

pub fn assert_output_contains(output: &str, expected: &str) {
    assert!(
        output.contains(expected),
        "Expected output to contain {expected:?}, got {output:?}"
    );
}
```

```rust
// tests/integration_basic.rs
mod common;
use common::create_test_config;

#[test]
fn full_pipeline_execution() {
    let config = create_test_config();
    let result = run_pipeline(config);
    assert!(result.is_ok());
}
```

---

## Property Testing (proptest)

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn roundtrip_serialization(value: i64) {
        let serialized = serialize(value);
        let deserialized = deserialize(&serialized).unwrap();
        assert_eq!(value, deserialized);
    }

    #[test]
    fn parse_never_panics(input in ".*") {
        let _ = parse(&input);  // Should not panic
    }
}
```

---

## Benchmarks (criterion)

```rust
// benches/main.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_parse(c: &mut Criterion) {
    let input = include_str!("../test_data/large_input.txt");
    c.bench_function("parse large input", |b| {
        b.iter(|| parse(black_box(input)))
    });
}

fn bench_serialize(c: &mut Criterion) {
    let data = create_test_data();
    c.bench_function("serialize", |b| {
        b.iter(|| serde_json::to_string(black_box(&data)))
    });
}

criterion_group!(benches, bench_parse, bench_serialize);
criterion_main!(benches);
```

---

## Fuzz Testing (cargo-fuzz)

```rust
// fuzz/fuzz_targets/parse_input.rs
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &str| {
    // Should never panic, regardless of input
    let _ = mylib::parse(data);
});
```

```bash
# Run fuzzer
cargo +nightly fuzz run parse_input

# Run for 60 seconds
cargo +nightly fuzz run parse_input -- -max_total_time=60
```

---

## Testing Async Code

```rust
#[tokio::test]
async fn fetch_data_succeeds() {
    let server = MockServer::start().await;
    server.register(Mock::given(method("GET")).respond_with(ResponseTemplate::new(200))).await;

    let result = fetch_data(&server.uri()).await;
    assert!(result.is_ok());
}

#[tokio::test]
async fn timeout_on_slow_response() {
    let result = tokio::time::timeout(
        Duration::from_millis(100),
        slow_operation(),
    ).await;
    assert!(result.is_err());
}
```

---

## Test Organization Best Practices

1. **Tests in `tests/` directory** — not inside source modules unless explicitly needed
2. **Use `pretty_assertions`** — for readable diffs on assertion failures
3. **Use snapshot tests** — for complex output that changes during development
4. **Name tests descriptively** — `parse_empty_returns_default` not `test_parse`
5. **One assert per concept** — multiple asserts are fine if they test one logical thing
6. **Use data-driven tests** — for many input/output test cases
7. **Benchmark critical paths** — use criterion for reproducible measurements
8. **Fuzz parse boundaries** — any function that takes untrusted input should be fuzzed

---

## Anti-Patterns

1. **Tests inside source modules**: Keep tests in `tests/` directory
2. **`#[should_panic]` for error testing**: Use `Result` and assert on the error instead
3. **Many tiny test files**: Consolidate related tests into single files
4. **No assertion messages**: Add context to assertions for readable failures
5. **Testing implementation details**: Test behavior, not internal state
6. **Ignoring tests with `#[ignore]`**: Fix the test or remove it — ignored tests rot
