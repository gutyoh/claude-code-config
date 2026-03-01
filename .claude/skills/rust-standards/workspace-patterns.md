# Workspace Patterns

## Cargo Workspace Structure

### Standard Layout

```
project/
├── Cargo.toml              # Workspace root
├── Cargo.lock              # Committed for applications, gitignored for libraries
├── rust-toolchain.toml     # Pin toolchain for reproducibility
├── .rustfmt.toml           # Formatting config
├── clippy.toml             # Clippy config (optional, can use Cargo.toml)
├── .pre-commit-config.yaml # Pre-commit hooks
├── Makefile                # Build/test/lint targets
├── crates/
│   ├── mylib/              # Core library
│   │   ├── Cargo.toml
│   │   └── src/
│   ├── mylib-cli/          # CLI binary
│   │   ├── Cargo.toml
│   │   └── src/
│   ├── mylib-python/       # Python bindings (PyO3)
│   │   ├── Cargo.toml
│   │   └── src/
│   └── mylib-js/           # JS bindings (napi-rs)
│       ├── Cargo.toml
│       └── src/
└── tests/                  # Workspace-level integration tests
```

### Workspace `Cargo.toml`

```toml
[workspace]
resolver = "2"
members = [
    "crates/mylib",
    "crates/mylib-cli",
    "crates/mylib-python",
]
default-members = ["crates/mylib-cli"]

[workspace.package]
edition = "2024"
version = "0.1.0"
rust-version = "1.90"
license = "MIT"
authors = ["Your Name <your@email.com>"]
description = "Description of the project."
repository = "https://github.com/org/repo/"

[workspace.dependencies]
# Pin shared dependencies at workspace level
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
anyhow = "1.0"
thiserror = "2.0"
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
indexmap = { version = "2.9", features = ["serde"] }
pretty_assertions = "1.4"

[workspace.lints.clippy]
# Enable pedantic as baseline, selectively allow noisy lints
pedantic = { level = "warn", priority = -1 }
dbg_macro = "warn"
use_self = "warn"
allow_attributes = "warn"
undocumented_unsafe_blocks = "warn"
redundant_clone = "warn"
# Selectively allowed pedantic lints
cast_precision_loss = "allow"
doc_markdown = "allow"
match_same_arms = "allow"
missing_errors_doc = "allow"
similar_names = "allow"
too_many_lines = "allow"
```

### Crate-Level `Cargo.toml`

```toml
[package]
name = "mylib"
edition.workspace = true
version.workspace = true
rust-version.workspace = true
license.workspace = true
authors.workspace = true

[dependencies]
serde.workspace = true
anyhow.workspace = true

[dev-dependencies]
pretty_assertions.workspace = true

[lints]
workspace = true
```

---

## Release Profiles

```toml
[profile.release]
lto = "fat"           # Link-time optimization (slower build, faster binary)
codegen-units = 1     # Single codegen unit (slower build, better optimization)
strip = true          # Strip debug symbols from binary

[profile.profiling]
inherits = "release"
debug = true          # Keep debug info for profiling
strip = false
lto = false           # Faster build for profiling iterations
```

---

## Toolchain Pinning

```toml
# rust-toolchain.toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
```

---

## Formatting Configuration

```toml
# .rustfmt.toml
max_width = 120
imports_granularity = "Crate"
group_imports = "StdExternalCrate"
reorder_imports = true
```

---

## Clippy Configuration

Prefer workspace-level lints in `Cargo.toml` (see above). For additional configuration:

```toml
# clippy.toml (optional — for settings not supported in Cargo.toml)
msrv = "1.90"
```

### Lint Groups Reference

| Group | Treatment | Rationale |
|-------|-----------|-----------|
| `clippy::correctness` | deny (default) | Few false positives, catches real bugs |
| `clippy::pedantic` | warn (enable as baseline) | Opinionated but useful — selectively allow noisy lints |
| `clippy::style` | warn (default) | Code style suggestions |
| `clippy::perf` | warn (default) | Performance improvements |
| `clippy::nursery` | don't enable | Work-in-progress lints, may have bugs |
| `clippy::restriction` | don't enable | Restricts language features, too opinionated |
| `clippy::cargo` | consider | Validates Cargo.toml hygiene |

### CI Lint Command

```bash
# Lint with warnings as errors
cargo clippy --workspace --tests -- -D warnings

# Lint with all features
cargo clippy --workspace --tests --all-features -- -D warnings
```

---

## Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
fail_fast: true

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.0.1
    hooks:
      - id: no-commit-to-branch
      - id: check-yaml
      - id: check-toml
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-added-large-files

  - repo: https://github.com/codespell-project/codespell
    rev: v2.3.0
    hooks:
      - id: codespell
        additional_dependencies: [tomli]

  - repo: local
    hooks:
      - id: format-rs
        name: Format Rust
        entry: cargo +nightly fmt --all
        types: [rust]
        language: system
        pass_filenames: false
      - id: lint-rs
        name: Lint Rust
        entry: cargo clippy --workspace --tests -- -D warnings
        types: [rust]
        language: system
        pass_filenames: false
```

---

## Makefile Targets

Essential targets for any Rust project:

```makefile
.PHONY: format
format: ## Format Rust code
	cargo +nightly fmt --all

.PHONY: lint
lint: ## Lint with clippy
	cargo clippy --workspace --tests -- -D warnings
	cargo clippy --workspace --tests --all-features -- -D warnings

.PHONY: test
test: ## Run all tests
	cargo test --workspace

.PHONY: bench
bench: ## Run benchmarks
	cargo bench --workspace

.PHONY: check
check: format lint test ## Run all checks (format, lint, test)
```

---

## Feature Flags

```toml
[features]
default = []
full = ["serde", "async"]
serde = ["dep:serde", "dep:serde_json"]
async = ["dep:tokio"]

# Testing-only features (never in default)
ref-count-panic = []    # Panic on RC bugs (testing only)
ref-count-return = []   # Return RC data (testing only)
```

### Feature Flag Guidelines

| Guideline | Detail |
|-----------|--------|
| Minimal `default` | Only include what most users need |
| Additive features | Features should only add capabilities, never remove |
| Document each feature | Explain what enabling it does |
| Test with and without | CI should test `--no-default-features` and `--all-features` |
| Testing-only features | Clearly mark and never include in `default` |

---

## Dependency Management

### Version Pinning Strategy

| Dependency Type | Strategy |
|----------------|----------|
| Workspace deps | Pin major+minor in workspace `Cargo.toml` |
| Git deps | Pin to specific commit rev |
| Critical deps | Use `=` exact version in `Cargo.lock` (committed for apps) |
| Dev deps | Less strict — latest compatible is fine |

### Git Dependencies

```toml
# Pin to specific commit for reproducibility
ruff_parser = { git = "https://github.com/astral-sh/ruff.git", rev = "6ded4bed" }
```

---

## Anti-Patterns

1. **Not using workspace dependencies**: Pin shared deps once at workspace level
2. **Missing `rust-toolchain.toml`**: Pin toolchain for reproducible builds
3. **No `Cargo.lock` for applications**: Always commit lock files for binaries
4. **Committing `Cargo.lock` for libraries**: Libraries should not commit lock files
5. **Features that remove capabilities**: Features must be additive only
6. **Missing CI lint step**: Always run `clippy -- -D warnings` in CI
7. **No pre-commit hooks**: Catch formatting/lint issues before push
8. **`cargo build` without `--workspace`**: Always test the full workspace
