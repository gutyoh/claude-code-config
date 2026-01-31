# Configuration Patterns

## OmegaConf — The Only Config Loader

Kedro 1.0+ uses `OmegaConfigLoader` exclusively. All other config loaders have been removed.

### Config Loader Settings

```python
# src/<package_name>/settings.py (optional in 1.0+)
from kedro.config import OmegaConfigLoader

CONFIG_LOADER_CLASS = OmegaConfigLoader

CONFIG_LOADER_ARGS = {
    "base_env": "base",
    "default_run_env": "local",
    "config_patterns": {
        "spark": ["spark*/"],
        "mlflow": ["mlflow*"],
    },
    "merge_strategy": {
        "parameters": "soft",
        "catalog": "destructive",
    },
}
```

### Merge Strategies

| Strategy | Behavior | Use For |
|----------|----------|---------|
| `soft` | Merge keys from both base and environment — env overrides conflicting keys | Parameters (extend base with env-specific values) |
| `destructive` | Environment completely replaces base | Catalog (different storage per env), Spark config |

---

## Environment Directories

```
conf/
├── base/          # Always loaded first — shared defaults
├── local/         # Local dev overrides (gitignored)
├── staging/       # Staging environment
└── production/    # Production environment
```

```bash
# Run with specific environment (overrides base/)
kedro run --env=staging
kedro run --env=production
```

### Environment-per-Market Pattern

Scale pipelines across markets by creating one environment per market:

```
conf/
├── base/
├── market_us/
│   ├── catalog.yml    # US-specific storage paths
│   └── parameters.yml # US-specific parameters
├── market_eu/
│   ├── catalog.yml
│   └── parameters.yml
└── market_apac/
```

```bash
kedro run --env=market_us
kedro run --env=market_eu
```

### DuckDB Locally, BigQuery/Snowflake in Production

```yaml
# conf/local/catalog.yml
sales_data:
  type: pandas.SQLTableDataset
  credentials: local_db
  table_name: sales

# conf/production/catalog.yml
sales_data:
  type: pandas.SQLTableDataset
  credentials: bigquery_prod
  table_name: sales
```

---

## Globals Pattern

Share values across all config files using `globals.yml`.

```yaml
# conf/base/globals.yml
storage_path: s3://my-bucket/data
dataset_type:
  csv: pandas.CSVDataset
  parquet: pandas.ParquetDataset
global_random_state: 42
```

Reference in any config file:

```yaml
# conf/base/catalog.yml
companies:
  type: "${globals:dataset_type.csv}"
  filepath: "${globals:storage_path}/01_raw/companies.csv"

# conf/base/parameters.yml
model_options:
  random_state: ${globals:global_random_state}
```

---

## Runtime Parameters

Override parameters from the CLI without modifying files.

```bash
kedro run --params="model_options.learning_rate=0.01,model_options.batch_size=64"
```

### Runtime Params Resolver with Fallback

```yaml
# conf/base/parameters.yml
model_options:
  random_state: ${runtime_params:random_state, ${globals:global_random_state}}
```

This uses the CLI value if provided (`--params=random_state=42`), otherwise falls back to the globals value.

---

## Credentials — Security Rules

1. **Never commit `credentials.yml`** — it must be in `.gitignore`
2. **Always place in `conf/local/`** or environment-specific directories
3. **Reference via `credentials:` key** in catalog entries

```yaml
# conf/local/credentials.yml
my_database:
  username: admin
  password: secret123

# conf/base/catalog.yml
users_table:
  type: pandas.SQLTableDataset
  credentials: my_database
  table_name: users
```

### Environment Variables in Credentials

The `oc.env` resolver is re-enabled specifically for credentials files:

```yaml
# conf/local/credentials.yml
my_database:
  username: ${oc.env:DB_USERNAME}
  password: ${oc.env:DB_PASSWORD}
```

**Important**: `oc.env` is deactivated by default in all other config files for security. To use env vars outside credentials, register a custom resolver.

---

## Custom OmegaConf Resolvers

```python
# src/<package_name>/settings.py
from kedro.config import OmegaConfigLoader
from omegaconf import OmegaConf
from datetime import datetime

class CustomOmegaConfigLoader(OmegaConfigLoader):
    def __init__(self, conf_source, env=None, runtime_params=None, **kwargs):
        super().__init__(conf_source=conf_source, env=env, runtime_params=runtime_params, **kwargs)

        if not OmegaConf.has_resolver("add"):
            OmegaConf.register_new_resolver("add", lambda x, y: x + y)

        if not OmegaConf.has_resolver("now"):
            OmegaConf.register_new_resolver("now", lambda fmt: datetime.now().strftime(fmt))

CONFIG_LOADER_CLASS = CustomOmegaConfigLoader
```

Usage in config:

```yaml
# conf/base/parameters.yml
total_epochs: "${add:10,5}"  # Resolves to 15
run_date: "${now:%Y-%m-%d}"  # Resolves to current date
```

---

## Custom Config Patterns

Load arbitrary config files by pattern:

```python
CONFIG_LOADER_ARGS = {
    "config_patterns": {
        "spark": ["spark*/"],
        "mlflow": ["mlflow*"],
        "custom": ["custom*/"],
    },
}
```

Access in code:
```python
config_loader = context.config_loader
spark_config = config_loader["spark"]
```

---

## Hidden Files (Kedro 1.1+)

```python
CONFIG_LOADER_ARGS = {
    "ignore_hidden": True,  # Skip hidden files (e.g., .DS_Store)
}
```

---

## Per-Pipeline Parameters

Split parameters by pipeline for clarity:

```yaml
# conf/base/parameters.yml          — shared parameters
# conf/base/parameters_data_processing.yml — data_processing pipeline
# conf/base/parameters_data_science.yml    — data_science pipeline
```

OmegaConf merges all `parameters*.yml` files into a single `parameters` dict.

---

## Anti-Patterns

1. **Hardcoded values in code**: All configuration belongs in `conf/` — never hardcode paths, credentials, or parameters in Python
2. **Committing credentials**: `credentials.yml` must be gitignored — use env vars or secret managers in production
3. **Using `oc.env` outside credentials**: The resolver is disabled by default outside credentials files — register a custom resolver if needed
4. **Ignoring merge strategies**: Without explicit merge strategy, environment configs may not override base as expected
5. **Single giant `parameters.yml`**: Split into per-pipeline parameter files for maintainability
6. **Missing `globals.yml`**: If you repeat values across config files, extract them to globals
