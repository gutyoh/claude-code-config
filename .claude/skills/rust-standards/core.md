# Core Principles

## 1. The Compiler Is Your Ally

Encode invariants in the type system. Make illegal states unrepresentable. If the compiler accepts your code, it should be correct.

```rust
// CORRECT: Type system prevents invalid states
enum ConnectionState {
    Disconnected,
    Connected { session: Session },
    Authenticated { session: Session, user: User },
}

// WRONG: Boolean flags create invalid combinations
struct Connection {
    is_connected: bool,
    is_authenticated: bool,
    session: Option<Session>,  // Can be None when is_connected is true — bug!
    user: Option<User>,
}
```

## 2. Code Style

### Import Organization

All imports at the top of the file. Never use local imports unless there is a very good reason (e.g., avoiding circular dependencies in rare macro contexts).

```rust
// Group 1: std library
use std::borrow::Cow;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

// Group 2: external crates
use anyhow::{Context, Result};
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};

// Group 3: crate-internal
use crate::config::Config;
use crate::error::AppError;
```

**rustfmt handles grouping automatically** with:
```toml
# .rustfmt.toml
imports_granularity = "Crate"
group_imports = "StdExternalCrate"
```

### Import Style — Use Types Directly

Import types and use them by name. Never use them via long paths.

```rust
// CORRECT: Import and use directly
use std::borrow::Cow;
let value = Cow::Owned(String::from("hello"));

// WRONG: Using via path
let value = std::borrow::Cow::Owned(String::from("hello"));
```

### `impl Trait` Over Generic Bounds

Strongly prefer `impl Trait` syntax for function parameters. Changes are more localized — modifying the bound only touches the function signature, not every call site.

```rust
// CORRECT: impl Trait (preferred)
fn process(input: impl AsRef<str>) -> Result<()> { ... }
fn write_output(writer: impl Write) -> Result<()> { ... }

// WRONG: Turbofish generics (less localized)
fn process<T: AsRef<str>>(input: T) -> Result<()> { ... }
fn write_output<W: Write>(writer: W) -> Result<()> { ... }
```

**Exception**: Use explicit generics when the type parameter appears in the return type or must be specified by the caller:

```rust
// Generic needed: T appears in return type
fn parse<T: FromStr>(input: &str) -> Result<T, T::Err> { ... }
```

### `#[expect()]` Over `#[allow()]`

Always use `#[expect()]` instead of `#[allow()]` for lint suppressions. `expect` warns when the suppression becomes unnecessary, keeping the codebase clean.

```rust
// CORRECT: expect() — compiler warns if lint no longer triggers
#[expect(clippy::too_many_arguments)]
fn complex_init(a: u32, b: u32, c: u32, d: u32, e: u32, f: u32, g: u32) {}

// WRONG: allow() — silently persists even after refactoring
#[allow(clippy::too_many_arguments)]
fn complex_init(a: u32, b: u32, c: u32, d: u32, e: u32, f: u32, g: u32) {}
```

### Newspaper Style

Organize code with public/primary functions at the top, private utilities underneath — the reader sees the high-level API first.

```rust
impl Parser {
    /// Parse a complete document from source text.
    pub fn parse(&mut self, source: &str) -> Result<Document> {
        let tokens = self.tokenize(source)?;
        self.build_ast(tokens)
    }

    /// Parse a single expression.
    pub fn parse_expression(&mut self, source: &str) -> Result<Expr> {
        let tokens = self.tokenize(source)?;
        self.parse_expr_from_tokens(&tokens)
    }

    // --- Private helpers below ---

    fn tokenize(&self, source: &str) -> Result<Vec<Token>> { ... }
    fn build_ast(&mut self, tokens: Vec<Token>) -> Result<Document> { ... }
    fn parse_expr_from_tokens(&mut self, tokens: &[Token]) -> Result<Expr> { ... }
}
```

---

## 3. Error Handling

### Library Crates: `thiserror`

Define typed error enums with `thiserror` for library code. Each module should have its own error type.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("configuration file not found: {path}")]
    NotFound { path: PathBuf },

    #[error("invalid value for {key}: {reason}")]
    InvalidValue { key: String, reason: String },

    #[error("failed to parse configuration")]
    Parse(#[from] toml::de::Error),

    #[error(transparent)]
    Io(#[from] std::io::Error),
}
```

### Application Crates: `anyhow`

Use `anyhow` for application-level error handling where you don't need to match on error variants.

```rust
use anyhow::{bail, Context, Result};

fn load_config(path: &Path) -> Result<Config> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read config from {}", path.display()))?;

    let config: Config = toml::from_str(&content)
        .context("failed to parse configuration")?;

    if config.workers == 0 {
        bail!("worker count must be at least 1");
    }

    Ok(config)
}
```

### Error Handling Rules

| Rule | Detail |
|------|--------|
| Never panic in library code | Use `Result` for all fallible operations |
| Use `?` for propagation | Never match on `Result` just to re-wrap |
| Add context with `.context()` | Explain *what* failed, not *how* |
| Use `bail!` for early returns | Cleaner than `return Err(anyhow!(...))` |
| `#[from]` for automatic conversion | Use in `thiserror` enums for source errors |
| `#[error(transparent)]` for wrapping | When the inner error message is sufficient |

---

## 4. Ownership, Borrowing, and Lifetimes

### Prefer Borrowing in Function Signatures

```rust
// CORRECT: Borrow when you don't need ownership
fn process(data: &[u8]) -> Result<Output> { ... }
fn format_name(name: &str) -> String { ... }

// WRONG: Taking ownership unnecessarily
fn process(data: Vec<u8>) -> Result<Output> { ... }
fn format_name(name: String) -> String { ... }
```

### Use `Cow` for Conditional Ownership

```rust
use std::borrow::Cow;

fn normalize(input: &str) -> Cow<'_, str> {
    if input.contains(' ') {
        Cow::Owned(input.replace(' ', "_"))
    } else {
        Cow::Borrowed(input)
    }
}
```

### Lifetime Elision — Let the Compiler Work

Don't annotate lifetimes when the compiler can infer them.

```rust
// CORRECT: Elided lifetimes (compiler infers)
fn first_word(s: &str) -> &str { ... }

// WRONG: Unnecessary lifetime annotations
fn first_word<'a>(s: &'a str) -> &'a str { ... }
```

Only annotate when the compiler requires it (multiple input lifetimes, struct lifetimes, complex relationships).

---

## 5. Type System Best Practices

### Newtype Pattern for Type Safety

```rust
/// User ID — distinct from other integer identifiers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UserId(pub u64);

/// Order ID — distinct from UserId at compile time.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct OrderId(pub u64);

// Compiler prevents: find_order(user_id) when fn expects OrderId
fn find_order(order_id: OrderId) -> Option<Order> { ... }
```

### Builder Pattern for Complex Construction

```rust
pub struct ServerConfig {
    host: String,
    port: u16,
    workers: usize,
}

impl ServerConfig {
    pub fn builder() -> ServerConfigBuilder {
        ServerConfigBuilder::default()
    }
}

#[derive(Default)]
pub struct ServerConfigBuilder {
    host: Option<String>,
    port: Option<u16>,
    workers: Option<usize>,
}

impl ServerConfigBuilder {
    pub fn host(mut self, host: impl Into<String>) -> Self {
        self.host = Some(host.into());
        self
    }

    pub fn port(mut self, port: u16) -> Self {
        self.port = Some(port);
        self
    }

    pub fn build(self) -> Result<ServerConfig, &'static str> {
        Ok(ServerConfig {
            host: self.host.ok_or("host is required")?,
            port: self.port.unwrap_or(8080),
            workers: self.workers.unwrap_or(4),
        })
    }
}
```

### Enum Exhaustiveness

Use enums with `#[non_exhaustive]` for public APIs that may grow:

```rust
#[non_exhaustive]
#[derive(Debug, Clone)]
pub enum OutputFormat {
    Json,
    Csv,
    Table,
}
```

---

## 6. Module Organization and Visibility

### Visibility Rules

| Visibility | Use For |
|------------|---------|
| `pub` | Public API — part of the crate's contract |
| `pub(crate)` | Internal API — used across modules within the crate |
| `pub(super)` | Parent module access only |
| (private) | Implementation details — default |

### Re-export from Crate Root

```rust
// src/lib.rs — re-export public types for clean external API
pub use config::Config;
pub use error::AppError;
pub use runner::Runner;

mod config;
mod error;
mod runner;
```

### One Type Per File (When Complex)

Simple types can share a file. Complex types (100+ lines with methods) get their own file.

---

## 7. Docstrings and Comments

### Every Public Item Gets a Docstring

```rust
/// A compiled pipeline ready for execution.
///
/// Pipelines are created from source code via [`Pipeline::compile`] and can be
/// executed multiple times with different inputs. The compiled representation
/// is immutable and thread-safe.
pub struct Pipeline {
    // ...
}
```

### Docstring Rules

| Rule | Detail |
|------|--------|
| Cover motivation and usage | Not just "what it does" — explain *why* and *when* |
| Keep examples short | Public functions only, 8 lines max |
| Test all examples | Never add `ignore` to doc examples |
| Update stale docs | If you see an outdated docstring, fix it immediately |
| Add comments to complex code | Especially for non-obvious algorithms or unsafe justifications |

---

## 8. Performance Guidelines

| Guideline | Detail |
|-----------|--------|
| `&str` over `String` in params | Borrow when you don't need ownership |
| `&[T]` over `Vec<T>` in params | Accept slices for flexibility |
| `Cow<'_, str>` for conditional ownership | Avoid cloning when input might not change |
| `Box<[T]>` over `Vec<T>` for fixed collections | Saves capacity field overhead |
| Avoid `clone()` without justification | Each clone is a potential allocation |
| Prefer iterators over index loops | Compiler can optimize bounds checks away |
| Use `#[inline]` sparingly | Only for small, hot functions across crate boundaries |
| Profile before optimizing | Use `criterion` benchmarks, not intuition |

---

## 9. Unsafe Code

**NEVER write `unsafe` code** unless explicitly approved by the user. If you think `unsafe` is needed:

1. Leave a `todo!()` with explanation
2. Explain why safe alternatives won't work
3. Ask the user to review and approve

If `unsafe` is approved, always document the safety invariant:

```rust
// SAFETY: `ptr` is guaranteed valid by the arena allocator's invariant
// that all allocated pointers remain valid for the arena's lifetime.
unsafe { &*ptr }
```

---

## Anti-Patterns to Avoid

1. **`unwrap()` in library code**: Use `?`, `expect()` with message, or handle the error
2. **`clone()` to satisfy the borrow checker**: Restructure code instead — cloning is a code smell
3. **`String` parameters when `&str` suffices**: Borrow when you don't need ownership
4. **Turbofish generics for simple cases**: Use `impl Trait` syntax
5. **`#[allow()]` for lint suppression**: Use `#[expect()]` — it warns when unnecessary
6. **Local imports**: All imports at the top of the file
7. **God modules**: Split large modules by responsibility
8. **Missing docstrings**: Every public item needs a docstring explaining why, not just what
9. **Premature `Arc<Mutex<T>>`**: Consider channels, actors, or restructuring before shared mutable state
10. **`Box<dyn Trait>` by default**: Prefer static dispatch with generics/`impl Trait` unless dynamic dispatch is required
