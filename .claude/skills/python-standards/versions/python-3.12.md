# Python 3.12 Type Annotations

Python 3.12 introduced PEP 695 with major improvements to type syntax.

---

## PEP 695: Type Parameter Syntax

### Generic Functions (New Syntax)

```python
# Python 3.12+: New syntax
def first[T](items: list[T]) -> T | None:
    return items[0] if items else None

# Python 3.11 and earlier: TypeVar required
from typing import TypeVar
T = TypeVar("T")
def first(items: list[T]) -> T | None:
    return items[0] if items else None
```

### Generic Classes

```python
# Python 3.12+: Clean generic class
class Stack[T]:
    def __init__(self) -> None:
        self._items: list[T] = []

    def push(self, item: T) -> None:
        self._items.append(item)

    def pop(self) -> T:
        return self._items.pop()

# Usage
stack = Stack[int]()
stack.push(42)
```

### Type Parameter Bounds

```python
# Constrain type parameter
from typing import SupportsLt

def max_value[T: SupportsLt](items: list[T]) -> T:
    return max(items)

# Multiple bounds (intersection)
def process[T: (Hashable, Comparable)](item: T) -> T:
    ...
```

---

## Type Aliases with `type` Statement

```python
# Python 3.12+: type statement
type UserId = str
type Coordinates = tuple[float, float]
type Handler[T] = Callable[[T], None]

# Python 3.11 and earlier: TypeAlias
from typing import TypeAlias
UserId: TypeAlias = str
Coordinates: TypeAlias = tuple[float, float]
```

---

## Built-in Generic Types

No imports needed for common generics:

```python
# CORRECT: Built-in generics (Python 3.9+)
def process(
    items: list[str],
    mapping: dict[str, int],
    options: set[str],
    callback: tuple[int, str],
) -> list[int]:
    ...

# WRONG: Don't import from typing
from typing import List, Dict, Set, Tuple  # Unnecessary
```

---

## Union Syntax

```python
# CORRECT: Use | for unions
def parse(value: str | int | None) -> Result:
    ...

# WRONG: Don't use Union
from typing import Union, Optional
def parse(value: Union[str, int, None]) -> Result:  # Old style
    ...
```

---

## Optional as `X | None`

```python
# CORRECT
def find_user(user_id: str) -> User | None:
    ...

# WRONG
from typing import Optional
def find_user(user_id: str) -> Optional[User]:  # Old style
    ...
```

---

## Forward References

In Python 3.12, you can often avoid quotes for forward references:

```python
# With `from __future__ import annotations` (Python 3.12)
from __future__ import annotations

class Node:
    def __init__(self, children: list[Node]) -> None:  # No quotes needed
        self.children = children

# Without the import, quotes still needed
class Node:
    def __init__(self, children: list["Node"]) -> None:  # Quotes required
        self.children = children
```

---

## Self Type

```python
from typing import Self

class Builder:
    def with_name(self, name: str) -> Self:
        self._name = name
        return self

    def with_value(self, value: int) -> Self:
        self._value = value
        return self

# Subclasses automatically get correct return type
class AdvancedBuilder(Builder):
    def with_extra(self, extra: str) -> Self:
        self._extra = extra
        return self

# Type checker knows this returns AdvancedBuilder, not Builder
builder = AdvancedBuilder().with_name("test").with_extra("data")
```

---

## Quick Reference

| Feature | Python 3.12+ Syntax | Old Syntax |
|---------|---------------------|------------|
| Generic function | `def f[T](x: T) -> T` | `T = TypeVar("T")` |
| Generic class | `class C[T]:` | `class C(Generic[T]):` |
| Type alias | `type X = int` | `X: TypeAlias = int` |
| Union | `A \| B` | `Union[A, B]` |
| Optional | `X \| None` | `Optional[X]` |
| List type | `list[T]` | `List[T]` |
| Dict type | `dict[K, V]` | `Dict[K, V]` |