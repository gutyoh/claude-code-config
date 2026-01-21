# Python 3.13 Type Annotations

Python 3.13 introduced PEP 649 (Deferred Evaluation of Annotations), which changes how annotations work.

---

## CRITICAL: Do NOT Use `from __future__ import annotations`

PEP 649 provides deferred annotation evaluation natively. The future import is **no longer needed** and can cause issues.

```python
# WRONG in Python 3.13+
from __future__ import annotations  # DON'T DO THIS

class Node:
    children: list[Node]

# CORRECT in Python 3.13+
class Node:
    children: list[Node]  # Just works!
```

**Why?**
- PEP 649 evaluates annotations lazily (only when accessed)
- `from __future__ import annotations` converts annotations to strings
- These two approaches are incompatible and can cause runtime errors

---

## Forward References Work Naturally

No quotes needed for forward references in Python 3.13:

```python
# Python 3.13+: Forward references just work
class TreeNode:
    def __init__(
        self,
        value: int,
        left: TreeNode | None = None,   # No quotes!
        right: TreeNode | None = None,  # No quotes!
    ) -> None:
        self.value = value
        self.left = left
        self.right = right
```

---

## Recursive Types Without Future Import

```python
# Python 3.13+: Recursive types work naturally
type JSON = dict[str, JSON] | list[JSON] | str | int | float | bool | None

def parse_json(data: str) -> JSON:
    ...
```

---

## Circular Imports Work Better

PEP 649's lazy evaluation helps with circular import scenarios:

```python
# module_a.py
class A:
    def get_b(self) -> B:  # B not yet defined, but works!
        from module_b import B
        return B()

# module_b.py
from module_a import A

class B:
    def get_a(self) -> A:
        return A()
```

---

## All PEP 695 Syntax Still Works

Everything from Python 3.12 continues to work:

```python
# Generic functions
def first[T](items: list[T]) -> T | None:
    return items[0] if items else None

# Generic classes
class Container[T]:
    def __init__(self, value: T) -> None:
        self.value = value

# Type aliases
type UserId = str
type Handler[T] = Callable[[T], None]

# Type bounds
def process[T: Comparable](items: list[T]) -> T:
    return max(items)
```

---

## Migration from 3.12 to 3.13

When upgrading:

1. **Remove** `from __future__ import annotations` from all files
2. **Remove** quotes from forward references (optional but cleaner)
3. **Test** annotation access at runtime (if you use `get_type_hints()`)

```python
# Before (Python 3.12)
from __future__ import annotations

class Node:
    children: list["Node"]

# After (Python 3.13)
class Node:
    children: list[Node]
```

---

## Accessing Annotations at Runtime

If your code inspects annotations at runtime:

```python
from typing import get_type_hints

class Example:
    value: int
    name: str

# PEP 649: Annotations are evaluated lazily
hints = get_type_hints(Example)  # Works, evaluates annotations here
```

---

## Quick Reference: Python 3.13 Changes

| Aspect | Python 3.12 | Python 3.13 |
|--------|-------------|-------------|
| `from __future__ import annotations` | Recommended for forward refs | **Do NOT use** |
| Forward references | Need quotes or future import | Just work naturally |
| Circular type references | Tricky | Easier with lazy evaluation |
| PEP 695 syntax | Available | Still available |
| Annotation evaluation | Eager (or strings with future) | Lazy (PEP 649) |