# Testing Patterns

## Test Directory Structure

Mirror the project structure in tests:

```
tests/
├── conftest.py                         # Shared fixtures
├── pipelines/
│   ├── data_processing/
│   │   └── test_nodes.py              # Unit tests for node functions
│   └── data_science/
│       ├── test_nodes.py              # Unit tests
│       └── test_pipeline.py           # Integration tests
```

---

## Unit Testing Nodes

Nodes are pure functions — test them directly without Kedro infrastructure.

```python
import pytest
import pandas as pd
from my_project.pipelines.data_processing.nodes import preprocess_companies

@pytest.fixture
def raw_companies():
    return pd.DataFrame({
        "company_name": ["Company A", "Company B"],
        "iata_approved": ["t", "f"],
        "company_rating": ["80%", "90%"],
    })

def test_preprocess_companies_converts_booleans(raw_companies):
    result = preprocess_companies(raw_companies)
    assert result["iata_approved"].dtype == bool
    assert result.loc[0, "iata_approved"] is True
    assert result.loc[1, "iata_approved"] is False

def test_preprocess_companies_normalizes_ratings(raw_companies):
    result = preprocess_companies(raw_companies)
    assert result["company_rating"].max() <= 1.0
    assert result["company_rating"].min() >= 0.0
```

### Testing Nodes with Parameters

```python
@pytest.fixture
def model_parameters():
    return {
        "test_size": 0.2,
        "random_state": 42,
        "features": ["engines", "passenger_capacity"],
    }

def test_split_data_produces_correct_ratio(sample_data, model_parameters):
    result = split_data(sample_data, model_parameters)
    total = len(result["X_train"]) + len(result["X_test"])
    assert len(result["X_test"]) / total == pytest.approx(0.2, abs=0.05)
```

### Testing Nodes with Multiple Outputs

```python
def test_split_data_returns_all_keys(sample_data, model_parameters):
    result = split_data(sample_data, model_parameters)
    assert set(result.keys()) == {"X_train", "X_test", "y_train", "y_test"}
```

---

## Integration Testing Pipelines

Use `MemoryDataset` and `SequentialRunner` to test pipelines without file I/O.

```python
from kedro.io import DataCatalog, MemoryDataset
from kedro.runner import SequentialRunner
from my_project.pipelines.data_processing.pipeline import create_pipeline

@pytest.fixture
def test_catalog(raw_companies, raw_shuttles, model_parameters):
    return DataCatalog({
        "companies": MemoryDataset(raw_companies),
        "shuttles": MemoryDataset(raw_shuttles),
        "parameters": MemoryDataset(model_parameters),
    })

def test_data_processing_pipeline(test_catalog):
    runner = SequentialRunner()
    pipeline = create_pipeline()
    result = runner.run(pipeline, test_catalog)

    assert "preprocessed_companies" in result
    assert "preprocessed_shuttles" in result
    assert not result["preprocessed_companies"].empty
```

---

## Shared Fixtures in conftest.py

```python
# tests/conftest.py
import pytest
import pandas as pd

@pytest.fixture
def raw_companies():
    return pd.DataFrame({
        "company_name": ["A", "B", "C"],
        "iata_approved": ["t", "f", "t"],
        "company_rating": ["80%", "90%", "70%"],
    })

@pytest.fixture
def raw_shuttles():
    return pd.DataFrame({
        "shuttle_id": [1, 2, 3],
        "engines": [2, 4, 2],
        "passenger_capacity": [100, 200, 150],
    })

@pytest.fixture
def model_parameters():
    return {
        "test_size": 0.2,
        "random_state": 42,
        "features": ["engines", "passenger_capacity"],
    }
```

---

## Testing with Temporary Files

Use pytest's built-in `tmp_path` fixture for file-based catalog entries.

```python
def test_csv_roundtrip(tmp_path, raw_companies):
    filepath = tmp_path / "companies.csv"
    catalog = DataCatalog({
        "companies": CSVDataset(filepath=str(filepath)),
    })
    catalog.save("companies", raw_companies)
    loaded = catalog.load("companies")
    pd.testing.assert_frame_equal(loaded, raw_companies)
```

---

## Running Tests

```bash
# Run all tests
kedro test

# Or use pytest directly
pytest tests/

# Run specific pipeline tests
pytest tests/pipelines/data_processing/

# Run with coverage
pytest tests/ --cov=src/<package_name> --cov-report=term-missing
```

---

## Testing Best Practices

1. **Test node functions directly** — they're pure functions, making them trivially testable
2. **Use fixtures** for reusable test data in `conftest.py`
3. **Use `MemoryDataset`** for integration tests — avoids file I/O overhead
4. **Use `tmp_path`** for tests that need actual file operations
5. **Never use `catalog.yml` in tests** — create test catalogs with fixtures
6. **Mirror project structure** in test directories for discoverability
7. **Name tests descriptively** — `test_preprocess_converts_booleans` not `test_preprocess`
8. **Test edge cases** — empty DataFrames, missing columns, null values
9. **Mock external dependencies** — APIs, databases, cloud storage

---

## Anti-Patterns

1. **Testing the framework**: Don't test that Kedro runs nodes — test your node logic
2. **File-based tests without cleanup**: Use `tmp_path` to ensure cleanup after tests
3. **Importing catalog.yml in tests**: Create test-specific catalogs with `DataCatalog` and `MemoryDataset`
4. **Skipping integration tests**: Unit tests alone don't catch pipeline wiring errors — test the full pipeline too
5. **Giant test fixtures**: Keep fixtures small and focused — create specific fixtures per test module
