# API Design

## Keyword-Only Arguments for Complex Functions

Functions with 4+ parameters should use keyword-only arguments after `*`.

```python
# CORRECT: Keyword-only after primary argument
def process_batch(
    records: list[dict],
    *,
    batch_size: int,
    provider_id: str,
    timeout: float,
    dry_run: bool = False,
) -> ProcessingResult:
    ...

# Call site is self-documenting
result = process_batch(
    records,
    batch_size=100,
    provider_id="12345",
    timeout=30.0,
)

# WRONG: All positional (confusing at call site)
def process_batch(records, batch_size, provider_id, timeout, dry_run=False):
    ...

# Caller has no idea what these args mean
result = process_batch(records, 100, "12345", 30.0)
```

---

## Default Values Are Dangerous

Avoid default parameter values unless 95%+ of callers want that default.

**Problems with defaults:**
1. Callers forget to provide values they should have specified
2. Bugs hide behind "reasonable" defaults
3. API changes become harder (changing a default is breaking)

```python
# DANGEROUS: timeout=30 seems reasonable but hides bugs
def fetch_data(url: str, timeout: float = 30.0) -> Response:
    ...

# Caller forgets timeout, uses default, has issues in production
fetch_data("https://slow-api.com")  # Silently uses 30s timeout

# BETTER: Require explicit timeout
def fetch_data(url: str, *, timeout: float) -> Response:
    ...

# Caller must think about timeout
fetch_data("https://slow-api.com", timeout=60.0)
```

**Exceptions where defaults are acceptable:**
- Boolean flags that are rarely True (`verbose=False`, `dry_run=False`)
- Test helpers and Fake classes (convenience over strictness)
- Optional metadata (`description: str | None = None`)

---

## Explicit Return Types

Always annotate return types for public functions.

```python
def get_config() -> Config:
    ...

async def process_items(items: list[Item]) -> list[Result]:
    ...

# For functions that may return None, be explicit
def find_user(user_id: str) -> User | None:
    ...
```

---

## Function Naming

| Pattern | Use For |
|---------|---------|
| `get_*` | Synchronous retrieval, O(1) or cached |
| `fetch_*` | Async/network retrieval, may be slow |
| `find_*` | Search that may return None |
| `create_*` | Constructor/factory that creates new object |
| `build_*` | Multi-step construction |
| `parse_*` | Convert string/bytes to structured data |
| `validate_*` | Check validity, raise on failure |
| `is_*`, `has_*` | Boolean predicates |

---

## Avoid Premature Abstraction

Don't create interfaces or abstractions for single implementations.

```python
# WRONG: Unnecessary abstraction
class IUserRepository(ABC):
    @abstractmethod
    def get_user(self, user_id: str) -> User: ...

class UserRepository(IUserRepository):
    def get_user(self, user_id: str) -> User:
        ...

# CORRECT: Just write the implementation
class UserRepository:
    def get_user(self, user_id: str) -> User:
        ...

# Add abstraction later ONLY if you need multiple implementations
```

---

## Breaking Changes Are OK

Don't maintain backwards compatibility for internal code. Break APIs and migrate immediately.

```python
# DON'T DO: Backwards-compatible shim
def process(items, batch_size=None, *, chunk_size=None):
    # Support both old and new parameter names
    size = chunk_size if chunk_size is not None else batch_size
    ...

# DO: Just change the API
def process(items, *, chunk_size: int):
    ...

# And update all callers in the same PR
```
