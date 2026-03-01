# Quality Checklists

Run through these checklists before completing code.

---

## Pre-Commit Checklist

### Safety
- [ ] No `unsafe` code (unless explicitly approved with documented safety invariant)
- [ ] No `unwrap()` in library code — use `?`, `expect()`, or handle the error
- [ ] No `panic!()` in library code — return `Result` instead
- [ ] No `clone()` to satisfy borrow checker — restructure code instead

### Error Handling
- [ ] Library errors use `thiserror` with typed error enums
- [ ] Application errors use `anyhow` with `.context()` messages
- [ ] All `Result` values are propagated with `?` or handled explicitly
- [ ] Error messages explain *what* failed, not *how*

### Code Style
- [ ] All imports at top of file — no local imports
- [ ] Imports grouped: std → external → crate-internal
- [ ] `impl Trait` syntax used for function parameters (not explicit generic type parameters)
- [ ] `#[expect()]` used instead of `#[allow()]` for lint suppression
- [ ] Newspaper style: public functions first, private utilities below

### Types and Ownership
- [ ] `&str` used over `String` in function parameters where possible
- [ ] `&[T]` used over `Vec<T>` in function parameters where possible
- [ ] `Cow<'_, str>` used for conditional ownership
- [ ] Newtype pattern for type-safe identifiers
- [ ] Standard traits derived (`Debug`, `Clone`, `PartialEq` where applicable)

### Documentation
- [ ] Every public struct, enum, and function has a docstring
- [ ] Docstrings explain motivation and usage, not just "what it does"
- [ ] Doc examples are tested (no `ignore` attribute)
- [ ] Stale comments and docstrings updated
- [ ] Complex code has inline comments

### Formatting and Linting
- [ ] `cargo fmt` passes (or `make format-rs`)
- [ ] `cargo clippy -- -D warnings` passes (or `make lint-rs`)
- [ ] No new warnings introduced

---

## Async Code Checklist

- [ ] No mutex guards held across `.await` points
- [ ] No blocking calls (`std::fs`, `std::net`) in async functions
- [ ] CPU-heavy work wrapped in `spawn_blocking`
- [ ] Spawned tasks are `Send + 'static`
- [ ] Cancellation is handled (cleanup on drop)
- [ ] Timeouts set on external calls

---

## Serde Checklist

- [ ] `#[serde(deny_unknown_fields)]` on config types
- [ ] `#[serde(default)]` for optional fields
- [ ] `#[serde(skip_serializing_if = "Option::is_none")]` for optional output
- [ ] `#[serde(rename_all)]` matches target format convention
- [ ] Roundtrip serialization tested

---

## CLI Checklist

- [ ] Using `clap` derive for argument parsing
- [ ] `#[command(version)]` included
- [ ] Errors go to stderr, output to stdout
- [ ] Non-zero exit code on failure
- [ ] `--help` is informative with descriptions on all arguments

---

## Testing Checklist

- [ ] Tests in `tests/` directory (not inline modules)
- [ ] Using `pretty_assertions` for readable diffs
- [ ] Test names follow `function_scenario_expected` pattern
- [ ] Edge cases tested (empty input, boundary values, errors)
- [ ] Integration tests exercise the public API
- [ ] Benchmarks for performance-critical paths

---

## Workspace Checklist

- [ ] Shared dependencies pinned at workspace level
- [ ] `rust-toolchain.toml` pins the toolchain
- [ ] `.rustfmt.toml` at repo root
- [ ] Workspace lints configured in root `Cargo.toml`
- [ ] `Cargo.lock` committed (for applications)
- [ ] Pre-commit hooks installed
- [ ] CI runs format check + clippy + tests

---

## Code Review Questions

Ask yourself before submitting:

1. **Would a new contributor understand this code from the docstrings and comments?**
2. **If this fails at 3 AM, can I debug it from the error messages and logs?**
3. **What happens when the input is empty, huge, or malicious?**
4. **Is this the simplest solution that works?**
5. **Am I fighting the borrow checker, or is my design wrong?**
