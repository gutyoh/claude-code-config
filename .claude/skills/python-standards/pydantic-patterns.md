# Pydantic Patterns

## Model Definition

### Basic Model with Validation

```python
from pydantic import BaseModel, Field, field_validator, ConfigDict
from decimal import Decimal

class InvoiceLineItem(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    line_number: int = Field(ge=1, description="Line number (1-indexed)")
    description: str = Field(min_length=1, description="Item description")
    quantity: Decimal = Field(gt=0, decimal_places=2)
    unit_price: Decimal = Field(ge=0, decimal_places=2)

    @field_validator("description")
    @classmethod
    def normalize_description(cls, v: str) -> str:
        return " ".join(v.split())
```

### Model with Computed Fields

```python
from pydantic import computed_field

class Invoice(BaseModel):
    line_items: list[InvoiceLineItem]
    tax_rate: Decimal = Field(default=Decimal("0.07"))

    @computed_field
    @property
    def subtotal(self) -> Decimal:
        return sum(item.quantity * item.unit_price for item in self.line_items)

    @computed_field
    @property
    def tax_amount(self) -> Decimal:
        return self.subtotal * self.tax_rate

    @computed_field
    @property
    def total(self) -> Decimal:
        return self.subtotal + self.tax_amount
```

---

## ConfigDict Options

```python
from pydantic import ConfigDict

class StrictModel(BaseModel):
    model_config = ConfigDict(
        str_strip_whitespace=True,      # Strip whitespace from strings
        strict=True,                     # No type coercion
        frozen=True,                     # Immutable after creation
        extra="forbid",                  # Error on unknown fields
        validate_default=True,           # Validate default values
        use_enum_values=True,            # Serialize enums as values
    )
```

---

## Validation Patterns

### Field Validators

```python
from pydantic import field_validator

class User(BaseModel):
    email: str
    age: int

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        if "@" not in v:
            raise ValueError("Invalid email format")
        return v.lower()

    @field_validator("age")
    @classmethod
    def validate_age(cls, v: int) -> int:
        if v < 0 or v > 150:
            raise ValueError("Age must be between 0 and 150")
        return v
```

### Model Validators

```python
from pydantic import model_validator

class DateRange(BaseModel):
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def validate_date_range(self) -> "DateRange":
        if self.end_date < self.start_date:
            raise ValueError("end_date must be after start_date")
        return self
```

---

## Serialization

### Custom Serialization

```python
from pydantic import field_serializer

class Record(BaseModel):
    created_at: datetime
    amount: Decimal

    @field_serializer("created_at")
    def serialize_datetime(self, v: datetime) -> str:
        return v.isoformat()

    @field_serializer("amount")
    def serialize_decimal(self, v: Decimal) -> str:
        return str(v.quantize(Decimal("0.01")))
```

### Export Methods

```python
# To dictionary
data = model.model_dump()
data = model.model_dump(exclude_none=True)
data = model.model_dump(by_alias=True)

# To JSON string
json_str = model.model_dump_json()
json_str = model.model_dump_json(indent=2)
```

---

## Inheritance Patterns

### Base Model with Common Config

```python
class BaseEntity(BaseModel):
    model_config = ConfigDict(
        str_strip_whitespace=True,
        extra="forbid",
    )

    id: str
    created_at: datetime
    updated_at: datetime | None = None

class User(BaseEntity):
    name: str
    email: str

class Product(BaseEntity):
    name: str
    price: Decimal
```

---

## Dataclasses for Simple Cases

Use `@dataclass` for simple data containers without validation needs.

```python
from dataclasses import dataclass

@dataclass
class ProcessingConfig:
    batch_size: int
    max_workers: int
    timeout_seconds: float

@dataclass(frozen=True)  # Immutable
class Coordinates:
    lat: float
    lon: float
```

**When to use which:**

| Use Case | Choice |
|----------|--------|
| External input validation | Pydantic |
| API request/response | Pydantic |
| Internal data transfer | dataclass |
| Simple config | dataclass |
| Need serialization | Pydantic |
| Immutable value objects | dataclass(frozen=True) |
