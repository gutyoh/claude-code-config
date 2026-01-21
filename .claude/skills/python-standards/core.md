# Core Principles

## 1. Explicit Over Implicit

Code should declare its intent clearly. Avoid patterns that hide behavior or require the reader to infer what's happening.

```python
# CORRECT: Intent is clear
if key in mapping:
    value = mapping[key]
    process(value)

# WRONG: Exception as control flow hides intent
try:
    value = mapping[key]
    process(value)
except KeyError:
    pass
```

## 2. Look Before You Leap (LBYL)

Check conditions proactively rather than catching exceptions. This makes control flow visible and intent explicit.

**Use LBYL for:**
- Dictionary access (`if key in mapping`)
- Path operations (`if path.exists()`)
- Attribute checks (`if hasattr(obj, 'attr')`)
- Collection bounds (`if index < len(items)`)

**Exceptions to LBYL (EAFP is acceptable):**
- Third-party APIs that provide no check alternative
- Race conditions (file operations where check-then-act is unsafe)
- Error boundaries (CLI/API entry points)
- Adding context before re-raising

```python
# ACCEPTABLE: Third-party API with no alternative
try:
    result = external_api.fetch(resource_id)
except ExternalAPIError as e:
    raise ServiceError(f"Failed to fetch {resource_id}") from e

# ACCEPTABLE: CLI error boundary
@app.command()
def main() -> None:
    try:
        run_pipeline()
    except PipelineError as e:
        typer.echo(f"Error: {e}", err=True)
        raise SystemExit(1) from e
```

## 3. Never Swallow Exceptions

Silent exception handling hides bugs and makes debugging impossible.

```python
# FORBIDDEN - Never do this
try:
    risky_operation()
except Exception:
    pass

# CORRECT: Let exceptions propagate or handle explicitly
risky_operation()
```

## 4. Exception Chaining

Always chain exceptions to preserve context using `from e` or `from None`.

```python
try:
    parse_config(path)
except yaml.YAMLError as e:
    raise ConfigurationError(f"Invalid config at {path}") from e

# Use `from None` when the original exception is not useful
try:
    value = int(user_input)
except ValueError:
    raise ValidationError("Expected a number") from None
```

## 5. Custom Exceptions Per Module

Define clear exception hierarchies for your domain.

```python
class ServiceError(Exception):
    """Base exception for this service."""

class ConfigurationError(ServiceError):
    """Invalid configuration."""

class ProcessingError(ServiceError):
    """Processing failed."""
```

---

# Path Operations

## Always Use pathlib

```python
from pathlib import Path

# CORRECT
config_path = Path.home() / ".config" / "app.yml"
if config_path.exists():
    content = config_path.read_text(encoding="utf-8")

# WRONG: os.path
import os.path
config_path = os.path.join(os.path.expanduser("~"), ".config", "app.yml")
```

## Check Existence Before Resolution

```python
# CORRECT: Check first (LBYL)
if path.exists():
    resolved = path.resolve()
    if current_dir.is_relative_to(resolved):
        process(resolved)

# WRONG: Exception handling for path validation
try:
    resolved = path.resolve()
except OSError:
    pass
```

## Always Specify Encoding

```python
content = path.read_text(encoding="utf-8")
path.write_text(data, encoding="utf-8")
```

---

# Imports

## Module-Level Imports (Default)

```python
# CORRECT: All imports at top
import json
from pathlib import Path
from loguru import logger
from myapp.config import Config

def process() -> None:
    data = json.loads(content)
```

## Inline Imports (Exceptions Only)

Acceptable for:
- Circular import prevention
- TYPE_CHECKING blocks
- Conditional feature loading

```python
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from myapp.models import HeavyModel  # Avoid import cycle

def optional_feature() -> None:
    if debug_mode:
        from myapp.debug import DebugTools  # Only when needed
        DebugTools.inspect()
```

---

# Import-Time Side Effects

## Defer Computation with @cache

```python
from functools import cache

# WRONG: Computed at import time
CONFIG_PATH = Path.home() / ".config" / "app.yml"

# CORRECT: Deferred until first call
@cache
def get_config_path() -> Path:
    return Path.home() / ".config" / "app.yml"
```

## Lightweight __init__ Pattern

Heavy I/O belongs in classmethods/factories, not `__init__`.

```python
# WRONG: Heavy I/O in __init__
class ConfigLoader:
    def __init__(self, path: Path) -> None:
        self.config = yaml.safe_load(path.read_text())  # I/O in constructor

# CORRECT: Lightweight __init__, heavy I/O in classmethod
class ConfigLoader:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config  # Just assignment

    @classmethod
    def from_file(cls, path: Path) -> "ConfigLoader":
        """Load configuration from a YAML file."""
        content = path.read_text(encoding="utf-8")
        config = yaml.safe_load(content)
        return cls(config)
```

---

# Performance

## O(1) Magic Methods

`__len__`, `__bool__`, `__contains__` must be constant time.

```python
# WRONG: O(n) __len__
def __len__(self) -> int:
    return sum(1 for _ in self._items)

# CORRECT: O(1) __len__
def __len__(self) -> int:
    return self._count
```

## O(1) Properties

Properties should never do I/O or expensive computation.

```python
# WRONG: I/O in property
@property
def size(self) -> int:
    return self._fetch_from_database()

# CORRECT: Explicit method name signals cost
def fetch_size(self) -> int:
    return self._fetch_from_database()
```

---

# Code Organization

## Maximum 4 Indentation Levels

Extract helper functions to reduce nesting.

```python
# WRONG: Too deep (5 levels)
def process(items):
    for item in items:
        if item.valid:
            for child in item.children:
                if child.enabled:
                    for grandchild in child.descendants:
                        handle(grandchild)

# CORRECT: Extract helpers
def process(items):
    for item in items:
        if item.valid:
            process_children(item.children)

def process_children(children):
    for child in children:
        if child.enabled:
            process_descendants(child.descendants)
```

## Single Responsibility

Classes should be 200-400 lines max. If larger, consider splitting.

---

# Anti-Patterns to Avoid

1. **Bare except clauses**: Always catch specific exceptions
2. **Mutable default arguments**: Use `None` and create inside function
3. **Star imports**: `from module import *` breaks traceability
4. **Nested ternaries**: Use if/elif/else or match statements
5. **God classes**: Split large classes by responsibility
6. **Premature abstraction**: Don't create interfaces for single implementations
7. **Backwards compatibility by default**: Break APIs and migrate immediately
