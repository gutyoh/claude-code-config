# Interfaces: ABC vs Protocol

## When to Use Each

| Use Case | Choice | Reason |
|----------|--------|--------|
| Internal abstractions | ABC | Explicit inheritance, runtime validation |
| Third-party facades | Protocol | No inheritance needed, loose coupling |
| Multiple implementations planned | ABC | Code reuse via base class |
| Duck typing boundary | Protocol | Structural subtyping |
| Need `isinstance()` checks | ABC | Runtime type checking |

---

## ABC Pattern (Preferred for Internal Code)

```python
from abc import ABC, abstractmethod

class Repository(ABC):
    """Base class for all repositories."""

    @abstractmethod
    def get(self, id: str) -> Entity | None:
        """Retrieve an entity by ID."""
        ...

    @abstractmethod
    def save(self, entity: Entity) -> None:
        """Persist an entity."""
        ...

    def exists(self, id: str) -> bool:
        """Check if entity exists. Default implementation."""
        return self.get(id) is not None


class UserRepository(Repository):
    """Concrete implementation for users."""

    def get(self, id: str) -> User | None:
        return self._db.query(User).filter_by(id=id).first()

    def save(self, entity: User) -> None:
        self._db.add(entity)
        self._db.commit()
```

**Benefits of ABC:**
- Clear contract: implementers know exactly what to implement
- Runtime validation: `TypeError` if abstract methods not implemented
- Code reuse: common methods in base class
- IDE support: better autocomplete and refactoring

---

## Protocol Pattern (For External Boundaries)

```python
from typing import Protocol

class Logger(Protocol):
    """Any object with info/error methods."""

    def info(self, message: str) -> None: ...
    def error(self, message: str) -> None: ...


# Works with any logger that has these methods
def process_with_logging(data: Data, logger: Logger) -> Result:
    logger.info(f"Processing {len(data)} items")
    ...
```

**Benefits of Protocol:**
- Structural subtyping: no inheritance required
- Third-party compatibility: works with objects you don't control
- Minimal interface: define only what you need

---

## Dependency Injection with ABC

```python
from abc import ABC, abstractmethod

# Define the interface
class DataStore(ABC):
    @abstractmethod
    def read(self, key: str) -> bytes | None: ...

    @abstractmethod
    def write(self, key: str, value: bytes) -> None: ...


# Production implementation
class S3DataStore(DataStore):
    def __init__(self, bucket: str) -> None:
        self._bucket = bucket
        self._client = boto3.client("s3")

    def read(self, key: str) -> bytes | None:
        try:
            response = self._client.get_object(Bucket=self._bucket, Key=key)
            return response["Body"].read()
        except ClientError:
            return None

    def write(self, key: str, value: bytes) -> None:
        self._client.put_object(Bucket=self._bucket, Key=key, Body=value)


# Test implementation
class InMemoryDataStore(DataStore):
    def __init__(self) -> None:
        self._data: dict[str, bytes] = {}

    def read(self, key: str) -> bytes | None:
        return self._data.get(key)

    def write(self, key: str, value: bytes) -> None:
        self._data[key] = value


# Service depends on abstraction
class DataProcessor:
    def __init__(self, store: DataStore) -> None:
        self._store = store

    def process(self, key: str) -> Result:
        data = self._store.read(key)
        ...
```

---

## Runtime Type Checking

ABC supports `isinstance()` checks; Protocol does not (by default).

```python
# ABC: isinstance works
class Handler(ABC):
    @abstractmethod
    def handle(self, event: Event) -> None: ...

def dispatch(obj: object) -> None:
    if isinstance(obj, Handler):  # Works!
        obj.handle(event)

# Protocol: isinstance doesn't work by default
class Handler(Protocol):
    def handle(self, event: Event) -> None: ...

def dispatch(obj: object) -> None:
    if isinstance(obj, Handler):  # TypeError!
        ...

# Protocol with runtime checking (use sparingly)
@runtime_checkable
class Handler(Protocol):
    def handle(self, event: Event) -> None: ...

def dispatch(obj: object) -> None:
    if isinstance(obj, Handler):  # Now works, but slower
        ...
```

---

## Decision Flowchart

```
Do you control the implementations?
├── Yes → ABC (explicit contract, code reuse)
└── No → Protocol (structural typing)

Do you need isinstance() checks?
├── Yes → ABC
└── No → Either works

Do you need shared implementation code?
├── Yes → ABC (default methods)
└── No → Either works

Is it a minimal interface (1-2 methods)?
├── Yes → Protocol (simpler)
└── No → ABC (clearer contract)
```