# Catalog Patterns

## Dataset Factories

Reduce repetitive catalog entries using pattern matching. More specific patterns match first; catch-all patterns match last. Explicit catalog entries always override factories.

### Namespace-Aware Factory

```yaml
# Match all datasets in a namespace
"{namespace}.{dataset_name}":
  type: pandas.ParquetDataset
  filepath: data/02_intermediate/{namespace}/{dataset_name}.pq
```

### Catch-All Default Factory

```yaml
# Lowest priority — matches any unregistered dataset
"{default_dataset}":
  type: pandas.CSVDataset
  filepath: data/{default_dataset}.csv
```

### Production Factory with Spark and Delta

```yaml
"{country}.prm_{dataset_name}":
  type: spark.SparkDataFrameDataset
  file_format: delta
  credentials: ${globals:datalake_credential}
  save_args:
    mode: overwrite
    mergeSchema: true
    partitionOverwriteMode: dynamic
  filepath: ${globals:storage_path}/{country}/03_primary/prm_{dataset_name}
  metadata:
    kedro-viz:
      layer: primary
```

### Debugging Factory Resolution

```bash
# List all factory patterns and their priority
kedro catalog list-patterns

# Show how patterns resolve to concrete datasets
kedro catalog resolve-patterns

# Describe all datasets in the pipeline
kedro catalog describe-datasets
```

---

## Versioned Datasets

Automatic timestamp-based versioning for reproducibility.

```yaml
regressor:
  type: pickle.PickleDataset
  filepath: data/06_models/regressor.pkl
  versioned: true
```

Each save creates a new timestamped version. Loads always return the latest version unless a specific version is pinned.

**When to version**: Model artifacts, feature tables, reporting outputs.
**When NOT to version**: Raw data (immutable by convention), intermediate data (regenerated from pipeline).

For production data versioning, prefer DVC, Delta Lake, or Apache Iceberg over Kedro's built-in versioning.

---

## Transcoding

Access the same data in multiple formats using the `@` separator.

```yaml
# Read as Spark, write as Spark
weather@spark:
  type: spark.SparkDataFrameDataset
  filepath: s3a://bucket/03_primary/weather
  file_format: delta
  save_args:
    mode: overwrite

# Read same data as Delta (for time travel, version rollback)
weather@delta:
  type: spark.DeltaTableDataset
  filepath: s3a://bucket/03_primary/weather
```

In pipeline, reference as `weather` — Kedro uses the `@spark` entry for save and `@delta` for load (or vice versa depending on pipeline direction).

---

## PartitionedDataset

Handle directories of files as a single logical dataset.

```yaml
my_partitioned_data:
  type: PartitionedDataset
  path: s3://bucket/path/to/folder
  dataset:
    type: pandas.CSVDataset
    load_args:
      sep: ","
  filename_suffix: ".csv"
```

The node receives a `dict[str, Callable]` where keys are partition names and values are lazy-loading callables.

---

## YAML Anchors for Shared Config

```yaml
_csv_defaults: &csv_defaults
  type: pandas.CSVDataset
  load_args:
    sep: ","

companies:
  <<: *csv_defaults
  filepath: data/01_raw/companies.csv

reviews:
  <<: *csv_defaults
  filepath: data/01_raw/reviews.csv
```

Use YAML anchors (prefixed with `_` to avoid being treated as datasets) for shared configuration blocks.

---

## Programmatic Catalog (Kedro 1.0+)

```python
from kedro.io import DataCatalog, MemoryDataset

catalog = DataCatalog()
catalog["my_dataset"] = MemoryDataset(data=my_dataframe)
```

Use programmatic catalog for testing and dynamic dataset registration in hooks.

---

## Dynamic Catalog via Hooks

```python
from kedro.framework.hooks import hook_impl
from kedro.io import DataCatalog

class DynamicCatalogHook:
    @hook_impl
    def after_catalog_created(self, catalog: DataCatalog, **kwargs) -> None:
        """Register datasets dynamically based on runtime conditions."""
        # Discover available data sources and register them
        ...
```

---

## SparkDatasetV2 (kedro-datasets 9.1+)

Unified dataset for local, Databricks-native, and remote Spark execution via Spark Connect.

```yaml
my_spark_data:
  type: spark.SparkDatasetV2
  filepath: /mnt/data/my_table
```

Supports:
- Local Spark sessions
- Databricks Connect (remote execution)
- Spark Connect protocol
- Automatic pandas-to-Spark conversion

---

## Anti-Patterns

1. **Hardcoding filepaths in nodes**: Always use catalog entries — filepaths belong in `catalog.yml`
2. **Duplicate catalog entries**: Use dataset factories for repeated patterns
3. **Missing `metadata.kedro-viz.layer`**: Always set layers for pipeline visualization
4. **Forgetting `load_args` / `save_args`**: Specify encoding, separators, modes explicitly
5. **Using `MemoryDataset` for data that should persist**: If you need to debug or rerun partial pipelines, declare datasets in catalog
6. **Versioning everything**: Only version artifacts that need reproducibility (models, reports) — not intermediate data
