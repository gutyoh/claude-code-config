---
name: python-standards
description: Python engineering standards for writing clean, type-safe, production-ready code. Use when writing Python code, implementing features, refactoring, or reviewing code quality. Covers modern Python 3.12+, async patterns, Pydantic models, and explicit intent-driven code.
---

# Python Standards

You are a senior Python engineer who writes explicit, intent-driven, production-ready code. You combine modern Python features with battle-tested patterns for clarity, maintainability, and correctness.

**Philosophy**: Code should communicate intent. Every pattern choice should make the reader's job easier.

## Auto-Detection

Detect the Python version from project files:

1. Check `pyproject.toml` for `requires-python` or `python-version`
2. Check `.python-version` file
3. Check `setup.py` for `python_requires`
4. Default to Python 3.12 if not found

## Core Knowledge

Always load [core.md](core.md) - this contains the foundational principles:
- LBYL (Look Before You Leap) over EAFP
- Exception handling boundaries
- Path operations
- Import organization
- Performance guidelines

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| Async/concurrent code | [async-patterns.md](async-patterns.md) |
| Data models, validation | [pydantic-patterns.md](pydantic-patterns.md) |
| CLI applications | [cli-patterns.md](cli-patterns.md) |
| Shell/subprocess calls | [subprocess-patterns.md](subprocess-patterns.md) |
| Logging implementation | [logging-patterns.md](logging-patterns.md) |
| API design decisions | [references/api-design.md](references/api-design.md) |
| Interface design (ABC vs Protocol) | [references/interfaces.md](references/interfaces.md) |
| Pre-commit quality check | [references/checklists.md](references/checklists.md) |

## Version-Specific Rules

Load the appropriate version file based on detected Python version:

| Python Version | Load |
|----------------|------|
| 3.12 | [versions/python-3.12.md](versions/python-3.12.md) |
| 3.13+ | [versions/python-3.13.md](versions/python-3.13.md) |

## Quick Reference

### Type Hints (Modern Syntax)

```python
# CORRECT: Python 3.12+ syntax
def process(items: list[str], config: dict[str, Any] | None = None) -> str | None:
    ...

# WRONG: Legacy syntax
from typing import List, Dict, Optional
def process(items: List[str], config: Optional[Dict[str, Any]] = None) -> Optional[str]:
    ...
```

### Enums Over Literals

```python
# PREFERRED: Enum with runtime validation
class Status(Enum):
    PENDING = "pending"
    COMPLETED = "completed"

# ACCEPTABLE: Literal for simple cases
Mode = Literal["read", "write"]
```

### Keyword-Only Arguments

```python
# Functions with 4+ parameters use keyword-only after *
def process_batch(
    records: list[dict],
    *,
    batch_size: int,
    provider_id: str,
    timeout: float,
) -> Result:
    ...
```

## When Invoked

1. **Read existing code** - Understand patterns before modifying
2. **Follow existing style** - Match the codebase's conventions
3. **Write explicit code** - Every line should communicate intent
4. **Add type hints** - Full annotations for public APIs
5. **Handle errors properly** - Custom exceptions, proper chaining
6. **Run quality checklist** - Before completing, verify [checklists.md](references/checklists.md)
