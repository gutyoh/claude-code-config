# Logging Patterns (Loguru)

## Basic Setup

```python
from loguru import logger

# Remove default handler
logger.remove()

# Add custom handler
logger.add(
    "app.log",
    rotation="10 MB",
    retention="7 days",
    compression="gz",
    format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function}:{line} | {message}",
)
```

---

## Structured Logging with bind()

Bind context to logger for consistent metadata.

```python
from loguru import logger

class InvoiceProcessor:
    def __init__(self, provider_id: str) -> None:
        self._provider_id = provider_id
        self._logger = logger.bind(
            service=self.__class__.__name__,
            provider_id=provider_id,
        )

    def process(self, invoice_id: str) -> None:
        # All logs from this method include service and provider_id
        self._logger.info(f"Processing invoice {invoice_id}")

        try:
            result = self._do_process(invoice_id)
            self._logger.info(f"Invoice {invoice_id} processed successfully")
        except ProcessingError as e:
            self._logger.error(f"Failed to process invoice {invoice_id}: {e}")
            raise
```

---

## Log Levels

Use appropriate levels for different scenarios:

```python
# DEBUG: Detailed diagnostic information
logger.debug(f"Cache lookup for key {key}")

# INFO: Normal operation milestones
logger.info(f"Processing batch of {len(items)} items")

# WARNING: Unexpected but handled situations
logger.warning(f"Retrying request after {retry_count} failures")

# ERROR: Failures that need attention
logger.error(f"Failed to connect to database: {e}")

# CRITICAL: System-level failures
logger.critical("Unable to start service: missing configuration")
```

---

## Inline Logging (No Intermediate Variables)

```python
# CORRECT: Direct f-string in logger call
self._logger.info(f"Processing {len(items)} items for provider {provider_id}")

# AVOID: Intermediate variable adds noise
log_msg = f"Processing {len(items)} items for provider {provider_id}"
self._logger.info(log_msg)
```

---

## Exception Logging

```python
try:
    process_data()
except Exception as e:
    # Log with full traceback
    logger.exception(f"Failed to process data: {e}")
    raise

# Or use opt(exception=True) for non-exception contexts
logger.opt(exception=True).error("Something went wrong")
```

---

## Context Manager for Temporary Binding

```python
with logger.contextualize(request_id=request_id, user_id=user_id):
    # All logs in this block include request_id and user_id
    logger.info("Starting request processing")
    process_request()
    logger.info("Request completed")
```

---

## Filtering Logs

```python
# Filter by level
logger.add("errors.log", level="ERROR")

# Filter by module
logger.add("db.log", filter=lambda record: "database" in record["name"])

# Custom filter function
def important_only(record):
    return record["level"].no >= logger.level("WARNING").no

logger.add("important.log", filter=important_only)
```

---

## JSON Output for Production

```python
import json

def serialize(record):
    subset = {
        "timestamp": record["time"].isoformat(),
        "level": record["level"].name,
        "message": record["message"],
        **record["extra"],
    }
    return json.dumps(subset)

logger.add(
    "app.json",
    format="{message}",
    serialize=True,
)
```

---

## Testing with Loguru

```python
from loguru import logger
import pytest

@pytest.fixture
def capture_logs(capfd):
    """Capture loguru output for testing."""
    logger.remove()
    logger.add(lambda msg: print(msg, end=""), format="{message}")
    yield
    logger.remove()

def test_logs_error_on_failure(capture_logs, capfd):
    process_invalid_data()
    captured = capfd.readouterr()
    assert "Error" in captured.out
```
