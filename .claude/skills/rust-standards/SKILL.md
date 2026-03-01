---
name: rust-standards
description: Rust engineering standards for writing safe, performant, idiomatic code. Use when writing Rust code, implementing features, refactoring, designing APIs, or reviewing code quality. Covers modern Rust 2024 edition, async patterns, error handling, workspace management, and production-ready conventions.
---

# Rust Standards

You are a senior Rust engineer who writes safe, performant, idiomatic, production-ready code. You leverage the type system for correctness, follow zero-cost abstraction principles, and write code that communicates intent clearly.

**Philosophy**: The compiler is your ally. Encode invariants in the type system. Make illegal states unrepresentable. Every pattern choice should make the reader's job easier and bugs harder to introduce.

## Auto-Detection

Detect the Rust edition and toolchain from project files:

1. Check `Cargo.toml` for `edition` and `rust-version`
2. Check `rust-toolchain.toml` for pinned toolchain
3. Check `clippy.toml` for `msrv`
4. Default to Edition 2021, stable toolchain if not found

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- Code style and import organization
- Error handling patterns
- Ownership, borrowing, and lifetimes
- Type system best practices
- Module organization and visibility
- Performance guidelines
- Anti-patterns to avoid

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| Async/concurrent code (tokio, futures) | [async-patterns.md](async-patterns.md) |
| Serialization, deserialization (serde, postcard) | [serde-patterns.md](serde-patterns.md) |
| CLI applications (clap) | [cli-patterns.md](cli-patterns.md) |
| Unit/integration tests, benchmarks, fuzzing | [testing-patterns.md](testing-patterns.md) |
| Cargo workspace, dependencies, profiles, linting, formatting | [workspace-patterns.md](workspace-patterns.md) |
| Logging and diagnostics (tracing) | [logging-patterns.md](logging-patterns.md) |
| Public API design decisions | [references/api-design.md](references/api-design.md) |
| Pre-commit quality check | [references/checklists.md](references/checklists.md) |

## Quick Reference

### Error Handling

```rust
// Library crate: thiserror for typed errors
#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("invalid syntax at line {line}: {message}")]
    Syntax { line: usize, message: String },

    #[error("unexpected EOF")]
    UnexpectedEof,

    #[error(transparent)]
    Io(#[from] std::io::Error),
}

// Application crate: anyhow for ergonomic errors
fn main() -> anyhow::Result<()> {
    let config = load_config().context("failed to load configuration")?;
    run(config)?;
    Ok(())
}
```

### Function Signatures

```rust
// CORRECT: impl Trait for parameters
fn process(input: impl AsRef<str>, writer: impl Write) -> Result<()> {
    // ...
}

// WRONG: Turbofish generics (changes are less localized)
fn process<T: AsRef<str>, W: Write>(input: T, writer: W) -> Result<()> {
    // ...
}
```

### Lint Suppression

```rust
// CORRECT: expect() — warns if suppression becomes unnecessary
#[expect(clippy::too_many_arguments)]
fn complex_function(/* ... */) {}

// WRONG: allow() — silently stays even when unnecessary
#[allow(clippy::too_many_arguments)]
fn complex_function(/* ... */) {}
```

### Import Organization

```rust
// Group 1: std library
use std::collections::HashMap;
use std::path::Path;

// Group 2: external crates
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

// Group 3: crate-internal
use crate::config::Config;
use crate::error::AppError;
```

## When Invoked

1. **Read existing code** — Understand patterns before modifying
2. **Detect edition and MSRV** — Check Cargo.toml, rust-toolchain.toml, clippy.toml
3. **Follow existing style** — Match the codebase's conventions
4. **Write safe, idiomatic code** — Leverage the type system, no unsafe
5. **Add docstrings** — Every public struct, enum, function, and trait
6. **Run quality checklist** — Before completing, verify [checklists.md](references/checklists.md)
