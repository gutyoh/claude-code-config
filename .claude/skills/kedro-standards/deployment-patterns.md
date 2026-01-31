# Deployment Patterns

## Packaging

```bash
# Package project as a wheel file
kedro package

# Install the packaged project
pip install dist/<package_name>-0.1-py3-none-any.whl

# Run the packaged project
python -m <package_name>
```

---

## Docker (kedro-docker)

```bash
pip install kedro-docker

# Generate Dockerfile
kedro docker init

# Build Docker image
kedro docker build

# Run pipeline in container
kedro docker run

# Run with specific pipeline
kedro docker run -- --pipeline=data_processing
```

---

## Airflow (kedro-airflow)

```bash
pip install kedro-airflow

# Generate Airflow DAG from Kedro pipeline
kedro airflow create
```

The generated DAG creates one Airflow task per Kedro node. The DAG file is placed in `airflow_dags/` by default.

### Customizing the DAG

```bash
# Target specific output directory
kedro airflow create --target-dir=/path/to/airflow/dags

# Generate for specific pipeline
kedro airflow create --pipeline=data_processing
```

---

## Databricks

### Three Deployment Approaches

| Approach | Description | When to Use |
|----------|-------------|-------------|
| **Asset Bundles (kedro-databricks)** | Deploy as Databricks Jobs via Asset Bundles | Recommended for CI/CD |
| **Wheel file on DBFS** | Package and upload to DBFS, run as Job | Simple deployments |
| **Workspace notebooks** | Develop directly in Databricks | Prototyping, exploration |

### kedro-databricks Plugin (Recommended)

```bash
pip install kedro-databricks

# Generate Databricks Asset Bundle config from Kedro pipelines
kedro databricks init

# Deploy to Databricks
kedro databricks deploy
```

Generates Databricks Asset Bundle resource definitions from Kedro pipeline structure. Each pipeline becomes a Databricks Job.

### SparkDatasetV2 for Databricks

```yaml
# conf/base/catalog.yml
my_table:
  type: spark.SparkDatasetV2
  filepath: catalog_name.schema_name.table_name
```

Supports local Spark, Databricks Connect, and Spark Connect — same dataset definition works across environments.

### Unity Catalog Integration

```yaml
# conf/production/catalog.yml
my_table:
  type: spark.SparkDataFrameDataset
  filepath: catalog_name.schema_name.table_name
```

### Environment-Specific Catalog for Databricks

```yaml
# conf/local/catalog.yml (local dev with DuckDB or local files)
sales_data:
  type: pandas.ParquetDataset
  filepath: data/03_primary/sales.pq

# conf/production/catalog.yml (Databricks with Delta Lake)
sales_data:
  type: spark.SparkDataFrameDataset
  filepath: catalog.schema.sales
  file_format: delta
```

**Note**: `dbx` is deprecated since 2023. Use Databricks Asset Bundles instead.

---

## Dagster (kedro-dagster)

```bash
pip install kedro-dagster

# Generate Dagster definitions from Kedro pipelines
kedro dagster init
```

Kedro pipelines map to Dagster assets. Full documentation at https://kedro-dagster.readthedocs.io/

---

## Other Platforms

| Platform | Plugin | Install |
|----------|--------|---------|
| Kubeflow | kedro-kubeflow | `pip install kedro-kubeflow` |
| Vertex AI | kedro-vertexai | `pip install kedro-vertexai` |
| Azure ML | kedro-azureml | `pip install kedro-azureml` |
| Prefect | kedro-prefect | `pip install kedro-prefect` |
| Snowflake | kedro-snowflake | `pip install kedro-snowflake` |

---

## MLflow Integration (kedro-mlflow)

### Setup

```bash
pip install kedro-mlflow

# Initialize MLflow config
kedro mlflow init
```

Creates `conf/base/mlflow.yml`.

### Configuration

```yaml
# conf/base/mlflow.yml
server:
  mlflow_tracking_uri: http://localhost:5000

tracking:
  experiment:
    name: my_experiment
  run:
    nested: true
  params:
    dict_params:
      flatten: true
      separator: "."
```

### Automatic Tracking

kedro-mlflow hooks automatically log:
- All parameters from `parameters.yml`
- Metrics from `MlflowMetricsHistoryDataset`
- Models from `MlflowModelTrackingDataset`
- Artifacts from `MlflowArtifactDataset`

### MLflow Model Packaging (MLflow 3.0)

```yaml
# conf/base/catalog.yml
regressor:
  type: kedro_mlflow.io.models.MlflowModelTrackingDataset
  flavor: mlflow.sklearn
  save_args:
    name: my_model  # MLflow 3.0 convention (replaces artifact_path)
```

### Version Compatibility

| kedro-mlflow | kedro | mlflow |
|---|---|---|
| 2.0.x | >=1.0 | >=3.0 only |
| 1.0.x | >=1.0 | 1.x or 2.x |
| 0.13.x | 0.19.x | 1.x or 2.x |

---

## FastAPI Integration (kedro-boot)

```bash
pip install kedro-boot
```

Maps Kedro pipeline objects to FastAPI endpoints. Run results are injected via FastAPI dependency injection.

---

## CI/CD Pattern

### GitHub Actions Example

```yaml
name: Kedro Pipeline
on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install -r requirements.txt
      - run: pytest tests/

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt
      - run: kedro package
      # Deploy the wheel to your target platform
```

---

## Anti-Patterns

1. **Using `dbx`**: Deprecated since 2023 — use Databricks Asset Bundles via kedro-databricks
2. **Hardcoding deployment config in code**: Use environment directories (`conf/production/`) for deployment-specific configuration
3. **Skipping `kedro package`**: Always package before deploying — don't copy raw source to production
4. **Same catalog for all environments**: Use environment-specific catalog files for local, staging, and production
5. **Missing CI/CD pipeline**: Always test before deploying — run `pytest` and `kedro run` in CI
6. **Manual deployments**: Automate with kedro-databricks, kedro-airflow, or kedro-docker
