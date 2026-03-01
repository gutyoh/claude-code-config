# API Design

## Accept Borrowed, Return Owned

```rust
// CORRECT: Accept &str, return String
pub fn normalize(input: &str) -> String {
    input.trim().to_lowercase()
}

// CORRECT: Accept &[T], return Vec<T>
pub fn deduplicate(items: &[Item]) -> Vec<Item> {
    let mut seen = HashSet::new();
    items.iter().filter(|item| seen.insert(item.id)).cloned().collect()
}
```

---

## Use `impl Trait` for Parameters

```rust
// CORRECT: Flexible input types
pub fn write_output(writer: impl Write, data: impl AsRef<[u8]>) -> Result<()> {
    // Accepts &[u8], Vec<u8>, String, &str, etc.
}

// Also correct: When trait bounds are complex, use where clause
pub fn process<R, W>(reader: R, writer: W) -> Result<()>
where
    R: Read + Seek,
    W: Write + Send,
{
    // ...
}
```

---

## Prefer Infallible Construction When Possible

```rust
// CORRECT: Infallible — no way to create an invalid Config
pub struct Config {
    workers: NonZeroUsize,
    port: u16,
}

// CORRECT: Fallible when validation is needed
impl Config {
    pub fn new(workers: usize, port: u16) -> Result<Self, ConfigError> {
        let workers = NonZeroUsize::new(workers)
            .ok_or(ConfigError::InvalidValue { key: "workers", reason: "must be > 0" })?;
        Ok(Self { workers, port })
    }
}
```

---

## Method Naming Conventions

| Pattern | Use For |
|---------|---------|
| `new()` | Primary constructor |
| `with_*()` | Builder-style modifiers |
| `from_*()` | Conversion constructors (`from_str`, `from_bytes`) |
| `into_*()` | Consuming conversions (`into_inner`, `into_vec`) |
| `as_*()` | Borrowing conversions (`as_str`, `as_bytes`, `as_ref`) |
| `to_*()` | Expensive/cloning conversions (`to_string`, `to_vec`) |
| `is_*()`, `has_*()` | Boolean predicates |
| `try_*()` | Fallible variants of otherwise infallible methods |
| `*_mut()` | Mutable access variant (`get_mut`, `iter_mut`) |

---

## Implement Standard Traits

Always implement standard traits when applicable:

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Config {
    name: String,
    workers: usize,
}

impl Display for Config {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Config({}, workers={})", self.name, self.workers)
    }
}
```

### Trait Checklist

| Trait | When |
|-------|------|
| `Debug` | Almost always — derive it |
| `Clone` | When copying makes sense |
| `PartialEq`, `Eq` | When equality comparison is meaningful |
| `Hash` | When the type will be used as a map key |
| `Display` | For user-facing string representation |
| `Default` | When a sensible default exists |
| `Send`, `Sync` | Usually automatic — verify for types with raw pointers |
| `From`/`Into` | For natural type conversions |
| `Serialize`/`Deserialize` | When the type crosses process boundaries |

---

## `#[non_exhaustive]` for Public Enums and Structs

```rust
// Allows adding variants in future without breaking downstream
#[non_exhaustive]
pub enum Error {
    NotFound,
    PermissionDenied,
    Timeout,
}

// Prevents external construction — forces use of builder/constructor
#[non_exhaustive]
pub struct Config {
    pub name: String,
    pub workers: usize,
}
```

---

## Avoid Premature Abstraction

```rust
// WRONG: Trait for a single implementation
pub trait Processor {
    fn process(&self, input: &[u8]) -> Result<Vec<u8>>;
}

pub struct DefaultProcessor;
impl Processor for DefaultProcessor { ... }

// CORRECT: Just write the implementation
pub struct Processor;
impl Processor {
    pub fn process(&self, input: &[u8]) -> Result<Vec<u8>> { ... }
}

// Add a trait later ONLY when you need multiple implementations
```

---

## Breaking Changes Are OK for Internal Code

Don't maintain backwards compatibility for `pub(crate)` APIs. Change them freely and update all callers in the same commit.

---

## Anti-Patterns

1. **Taking `String` when `&str` suffices**: Borrow in parameters, return owned
2. **Returning `impl Trait` when the concrete type is known**: Return the concrete type for clarity
3. **Missing `#[non_exhaustive]`**: Public enums and structs that may grow should use it
4. **Not deriving `Debug`**: Almost every type should derive `Debug`
5. **`Box<dyn Trait>` when generics work**: Prefer static dispatch for performance
6. **Complex generic bounds on every function**: Use `impl Trait` for simple cases
