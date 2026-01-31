# Core Principles

## 1. Nodes Are Pure Functions

Node functions MUST be pure — output depends solely on inputs, with no side effects. This is the foundational contract of Kedro.

```python
import pandas as pd

# CORRECT: Pure function — input in, output out
def preprocess_companies(companies: pd.DataFrame) -> pd.DataFrame:
    """Normalize company ratings and convert boolean flags."""
    companies["iata_approved"] = companies["iata_approved"].map({"t": True, "f": False})
    companies["company_rating"] = (
        companies["company_rating"].str.replace("%", "", regex=False).astype(float) / 100
    )
    return companies

# WRONG: Side effects — reads file directly
def preprocess_companies(filepath: str) -> pd.DataFrame:
    companies = pd.read_csv(filepath)  # Bypasses DataCatalog
    ...
```

**Rules:**
- Never read/write files inside a node — all I/O goes through the DataCatalog
- Never access the catalog object inside a node
- Never modify global state, send emails, or call external APIs
- Logging is acceptable — it's the only tolerated side effect
- Always add type hints to node function parameters and return types

## 2. Type Hints on All Node Functions

```python
from typing import Any

# CORRECT: Full type annotations
def split_data(
    data: pd.DataFrame,
    parameters: dict[str, Any],
) -> dict[str, pd.DataFrame]:
    """Split data into train and test sets."""
    ...

# WRONG: Missing type hints
def split_data(data, parameters):
    ...
```

## 3. Always Name Nodes Explicitly

Default node names in Kedro 1.0+ use the function name + SHA-256 hash. Always provide explicit names for clarity.

```python
# CORRECT: Explicit name
node(
    func=preprocess_companies,
    inputs="companies",
    outputs="preprocessed_companies",
    name="preprocess_companies_node",
)

# WRONG: Relying on auto-generated name
node(
    func=preprocess_companies,
    inputs="companies",
    outputs="preprocessed_companies",
)
```

## 4. Parameter Access Patterns

```python
# Access full parameters dict
node(func=my_func, inputs=["data", "parameters"], outputs="output", name="my_node")

# Access specific parameter (preferred — more explicit)
node(func=my_func, inputs=["data", "params:model_options"], outputs="output", name="my_node")

# Access nested parameter
node(func=my_func, inputs=["data", "params:model_options.learning_rate"], outputs="output", name="my_node")
```

Prefer `params:` prefix for specific parameters over passing the entire `parameters` dict. This makes node dependencies explicit and visible in pipeline visualization.

---

# Project Structure

## Standard Layout (Kedro 1.0+)

```
project-dir/
├── conf/
│   ├── base/                      # Shared across all environments
│   │   ├── catalog.yml            # DataCatalog definitions
│   │   ├── parameters.yml         # Pipeline parameters
│   │   ├── parameters_<pipeline>.yml  # Per-pipeline parameters
│   │   ├── globals.yml            # OmegaConf global variables
│   │   └── logging.yml            # Logging configuration
│   └── local/                     # Local overrides (gitignored)
│       ├── catalog.yml
│       └── credentials.yml        # Credentials (never committed)
├── data/                          # Local data (gitignored)
│   ├── 01_raw/
│   ├── 02_intermediate/
│   ├── 03_primary/
│   ├── 04_feature/
│   ├── 05_model_input/
│   ├── 06_models/
│   ├── 07_model_output/
│   └── 08_reporting/
├── src/
│   └── <package_name>/
│       ├── __init__.py
│       ├── __main__.py
│       ├── pipeline_registry.py   # Auto-discovers pipelines
│       ├── settings.py            # Optional (1.0+)
│       └── pipelines/
│           └── <pipeline_name>/
│               ├── __init__.py
│               ├── nodes.py       # Pure functions
│               └── pipeline.py    # create_pipeline() factory
├── tests/
│   ├── conftest.py
│   └── pipelines/
│       └── <pipeline_name>/
│           └── test_nodes.py
├── pyproject.toml
└── README.md
```

## Data Layer Convention

Data flows forward through numbered layers. Never create circular dependencies between layers.

| Layer | Directory | Purpose |
|-------|-----------|---------|
| Raw | `01_raw/` | Immutable source data — never modified |
| Intermediate | `02_intermediate/` | Cleaned, typed, parsed data |
| Primary | `03_primary/` | Domain-modeled, joined, enriched entities |
| Feature | `04_feature/` | Feature-engineered datasets |
| Model Input | `05_model_input/` | Train/test splits, model-ready data |
| Models | `06_models/` | Trained model artifacts |
| Model Output | `07_model_output/` | Predictions, scores, classifications |
| Reporting | `08_reporting/` | Aggregated summaries, visualizations |

**Rule**: Input datasets for a node in layer N should come from layer N or earlier. Raw data is immutable — never write to `01_raw/`.

## Layer Metadata for Kedro-Viz

```yaml
preprocessed_companies:
  type: pandas.ParquetDataset
  filepath: data/02_intermediate/preprocessed_companies.pq
  metadata:
    kedro-viz:
      layer: intermediate
```

---

# Pipeline Registry

## Auto-Discovery (Kedro 1.0+)

```python
# src/<package_name>/pipeline_registry.py
from kedro.pipeline import find_pipelines

def register_pipelines():
    pipelines = find_pipelines(raise_errors=True)
    pipelines["__default__"] = sum(pipelines.values())
    return pipelines
```

`find_pipelines()` auto-discovers all `create_pipeline()` functions under `pipelines/`. Use `raise_errors=True` (default in 1.2) to fail fast on import errors.

## Pipeline Factory Pattern

Each pipeline module must export a `create_pipeline()` factory:

```python
# src/<package_name>/pipelines/data_processing/pipeline.py
from kedro.pipeline import Pipeline, pipeline, node
from .nodes import preprocess_companies, preprocess_shuttles

def create_pipeline(**kwargs) -> Pipeline:
    return pipeline([
        node(
            func=preprocess_companies,
            inputs="companies",
            outputs="preprocessed_companies",
            name="preprocess_companies_node",
        ),
        node(
            func=preprocess_shuttles,
            inputs="shuttles",
            outputs="preprocessed_shuttles",
            name="preprocess_shuttles_node",
        ),
    ])
```

---

# DataCatalog Fundamentals

## All I/O Through the Catalog

```yaml
# conf/base/catalog.yml
companies:
  type: pandas.CSVDataset
  filepath: data/01_raw/companies.csv

preprocessed_companies:
  type: pandas.ParquetDataset
  filepath: data/02_intermediate/preprocessed_companies.pq
```

Datasets not declared in catalog.yml are stored as `MemoryDataset` (in-memory only, lost after pipeline run). If you need to persist intermediate data for debugging or rerunning, add it to the catalog.

## Common Dataset Types

| Type | Use For |
|------|---------|
| `pandas.CSVDataset` | Raw CSV files |
| `pandas.ParquetDataset` | Intermediate/primary tabular data |
| `pandas.ExcelDataset` | Excel files |
| `pandas.JSONDataset` | JSON data |
| `pandas.SQLTableDataset` | Database tables |
| `spark.SparkDataFrameDataset` | Spark DataFrames |
| `spark.SparkDatasetV2` | Unified local/Databricks Spark (1.2+) |
| `spark.DeltaTableDataset` | Delta Lake tables |
| `pickle.PickleDataset` | Model artifacts, Python objects |
| `polars.CSVDataset` | Polars DataFrames |
| `text.TextDataset` | Plain text files |
| `yaml.YAMLDataset` | YAML configuration |
| `json.JSONDataset` | JSON documents |

Install dataset extras as needed:
```bash
pip install "kedro-datasets[pandas,spark,polars]"
```

---

# Configuration Basics

## OmegaConf (Default and Only Config Loader)

Kedro 1.0+ uses `OmegaConfigLoader` exclusively. Other loaders have been removed.

```yaml
# conf/base/parameters.yml
model_options:
  test_size: 0.2
  random_state: 42
  features:
    - engines
    - passenger_capacity
    - d_check_complete
```

## Environment Directories

```
conf/
├── base/          # Shared (always loaded first)
├── local/         # Local dev overrides (gitignored)
├── staging/       # Staging environment
└── production/    # Production environment
```

Select environment at runtime:
```bash
kedro run --env=staging
```

## Credentials — Never Commit

```yaml
# conf/local/credentials.yml (gitignored)
my_database:
  username: admin
  password: secret123
```

Reference in catalog:
```yaml
my_table:
  type: pandas.SQLTableDataset
  credentials: my_database
  table_name: users
  save_args:
    if_exists: replace
```

---

# Anti-Patterns to Avoid

1. **Impure nodes**: Never access files, databases, or APIs directly in node functions — use the DataCatalog
2. **Catalog manipulation in nodes**: Never call `catalog.load()` or `catalog.save()` inside a node
3. **Missing node names**: Always provide explicit `name` parameter — auto-generated names are hard to reference
4. **Circular layer dependencies**: Data flows forward through layers — raw → intermediate → primary → feature
5. **Hardcoded paths in code**: Always use configuration files for paths, credentials, and environment-specific values
6. **Giant monolithic pipelines**: Split into modular pipelines under `pipelines/`, each independently testable
7. **`MemoryDataset` as a crutch**: If you need to persist intermediate data for debugging, add it to `catalog.yml`
8. **Skipping the DataCatalog**: Don't read/write files with pandas directly — route everything through the catalog
9. **Committing `data/` or `credentials.yml`**: These must be in `.gitignore`
10. **Not using `find_pipelines()`**: Since Kedro 0.18.3+, prefer auto-discovery over manual pipeline registration
11. **Star imports in nodes**: Always import specific functions — `from x import *` breaks traceability
12. **Side effects in nodes**: No disk writes, no email sending, no global state mutation (logging is the exception)
