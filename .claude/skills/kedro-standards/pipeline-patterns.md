# Pipeline Patterns

## Pipeline Composition

Combine modular pipelines using the `+` operator.

```python
def register_pipelines():
    pipelines = find_pipelines(raise_errors=True)
    pipelines["__default__"] = sum(pipelines.values())
    return pipelines
```

Or compose manually:

```python
def register_pipelines():
    return {
        "data_processing": data_processing.create_pipeline(),
        "data_science": data_science.create_pipeline(),
        "__default__": data_processing.create_pipeline() + data_science.create_pipeline(),
    }
```

---

## Namespace Pattern (Pipeline Reuse)

Reuse the same pipeline logic with different data and parameters by applying namespaces.

### Base Pipeline

```python
# src/<package>/pipelines/model_training/pipeline.py
def create_pipeline(**kwargs) -> Pipeline:
    return pipeline([
        node(func=train_model, inputs=["X_train", "y_train", "params:model_options"], outputs="model", name="train_node"),
        node(func=evaluate_model, inputs=["model", "X_test", "y_test"], outputs="metrics", name="evaluate_node"),
    ])
```

### Namespaced Instances

```python
from kedro.pipeline import pipeline
from .pipelines.model_training.pipeline import create_pipeline as base_training

linear_pipeline = pipeline(
    base_training(),
    namespace="linear_regression",
    parameters={"params:model_options": "params:linear_regression.model_options"},
    inputs={"X_train", "X_test", "y_train", "y_test"},  # Shared — not prefixed
)

rf_pipeline = pipeline(
    base_training(),
    namespace="random_forest",
    parameters={"params:model_options": "params:random_forest.model_options"},
    inputs={"X_train", "X_test", "y_train", "y_test"},
)
```

Namespace auto-prefixes:
- Dataset names: `X_train` → `linear_regression.X_train` (unless listed in `inputs`)
- Node names: `train_node` → `linear_regression.train_node`
- Parameter references: remapped via `parameters` argument

### Shared Datasets Across Namespaces

Use the `inputs` argument to declare datasets shared across namespaces — these will NOT be prefixed.

```python
pipeline(
    base_pipeline,
    namespace="my_ns",
    inputs={"shared_lookup_table", "global_config"},  # Not prefixed with namespace
)
```

### Disabling Auto-Prefixing (Kedro 1.0+)

```python
pipeline(
    base_pipeline,
    namespace="my_ns",
    prefix_datasets_with_namespace=False,  # All datasets keep original names
)
```

---

## Running Pipelines

### Single Pipeline

```bash
kedro run --pipeline=data_processing
```

### Multiple Pipelines (Kedro 1.2+)

```bash
kedro run --pipelines=data_processing,data_science
```

### By Namespace (Kedro 1.0+)

```bash
kedro run --namespaces=linear_regression,random_forest
```

### By Tags

```python
node(
    func=preprocess,
    inputs="raw",
    outputs="clean",
    name="preprocess_node",
    tags=["preprocessing", "data_quality"],
)
```

```bash
kedro run --tags=preprocessing
```

### By Node Selection

```bash
# Specific nodes
kedro run --nodes=preprocess_node,train_node

# From a node to the end
kedro run --from-nodes=preprocess_node

# From the start to a node
kedro run --to-nodes=train_node
```

### Incremental Runs (Kedro 1.0+)

```bash
# Skip nodes whose persistent outputs already exist
kedro run --only-missing-outputs
```

---

## Runners

| Runner | Description | When to Use |
|--------|-------------|-------------|
| `SequentialRunner` | Default. Runs nodes in topological order. | Debugging, most cases |
| `ParallelRunner` | Multiprocessing. Each node in a separate process. | CPU-bound, independent nodes |
| `ThreadRunner` | Multithreading. Concurrent execution. | I/O-bound operations |

```bash
kedro run --runner=ParallelRunner
kedro run --runner=ThreadRunner
```

### ParallelRunner Configuration

```bash
# Set multiprocessing start method (default: fork on Linux, spawn on macOS/Windows)
export KEDRO_MP_CONTEXT=forkserver
kedro run --runner=ParallelRunner
```

**Important**: `ParallelRunner` requires all datasets to be serializable. `MemoryDataset` cannot be shared between processes — all inter-node data must be persisted to catalog.

---

## Multiple Outputs from a Node

### Dict Outputs

```python
def split_data(data: pd.DataFrame, parameters: dict[str, Any]) -> dict[str, pd.DataFrame]:
    X_train, X_test, y_train, y_test = train_test_split(...)
    return {"X_train": X_train, "X_test": X_test, "y_train": y_train, "y_test": y_test}

node(
    func=split_data,
    inputs=["model_input_table", "params:model_options"],
    outputs=dict(X_train="X_train", X_test="X_test", y_train="y_train", y_test="y_test"),
    name="split_data_node",
)
```

### Tuple Outputs

```python
def split_data(data: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    return train_df, test_df

node(
    func=split_data,
    inputs="data",
    outputs=["train_data", "test_data"],
    name="split_node",
)
```

---

## Anti-Patterns

1. **Manual pipeline registration**: Use `find_pipelines()` instead of manually importing each pipeline
2. **Unnamed nodes**: Always provide `name` — needed for `--nodes`, `--from-nodes`, `--to-nodes`
3. **Monolithic pipelines**: Split large pipelines into focused modules (data_processing, feature_engineering, model_training)
4. **Circular dependencies**: Pipeline DAG must be acyclic — if node A depends on B's output, B cannot depend on A's output
5. **Ignoring `ParallelRunner` constraints**: If using `ParallelRunner`, all intermediate datasets must be in the catalog (not `MemoryDataset`)
6. **Overusing namespaces**: Only namespace pipelines that are genuinely reused with different data/params — don't namespace for the sake of it
