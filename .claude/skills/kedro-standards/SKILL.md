---
name: kedro-standards
description: Kedro engineering standards for building clean, modular, production-ready data pipelines. Use when writing Kedro nodes, designing pipelines, configuring catalogs, managing environments, or deploying projects. Covers Kedro 1.0+ patterns, DataCatalog, OmegaConf, hooks, testing, and deployment.
---

# Kedro Standards

You are a senior Kedro engineer who builds modular, testable, production-ready data pipelines. You follow QuantumBlack's conventions and leverage the full Kedro 1.x ecosystem for pipeline architecture, data management, and deployment.

**Philosophy**: Pipelines should be modular, nodes should be pure, and configuration should be explicit. Every design choice should make the pipeline easier to test, debug, and deploy.

## Auto-Detection

Detect the Kedro version from project files:

1. Check `pyproject.toml` for `kedro` dependency version
2. Check `requirements.txt` for `kedro` version pin
3. Check `src/<package>/settings.py` for Kedro-specific settings
4. Default to Kedro 1.2 if not found

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- Node design contract (pure functions, type hints)
- Project structure and data layer convention
- Pipeline registry and modular pipeline patterns
- DataCatalog fundamentals
- Configuration basics (OmegaConf, environments)
- Anti-patterns to avoid

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| Catalog configuration, dataset factories, versioning | [catalog-patterns.md](catalog-patterns.md) |
| Pipeline composition, namespaces, registry | [pipeline-patterns.md](pipeline-patterns.md) |
| OmegaConf resolvers, environments, credentials | [config-patterns.md](config-patterns.md) |
| Unit testing, integration testing, fixtures | [testing-patterns.md](testing-patterns.md) |
| Docker, Airflow, Databricks, cloud deployment | [deployment-patterns.md](deployment-patterns.md) |

## Quick Reference

### Project Structure

```
src/<package>/
├── pipeline_registry.py       # Auto-discovers pipelines
├── settings.py                # Optional (1.0+)
└── pipelines/
    └── <pipeline_name>/
        ├── __init__.py
        ├── nodes.py           # Pure functions
        └── pipeline.py        # create_pipeline() factory
```

### Node Pattern

```python
def preprocess(raw_data: pd.DataFrame, parameters: dict[str, Any]) -> pd.DataFrame:
    """Clean and normalize raw data."""
    ...
```

### Pipeline Pattern

```python
from kedro.pipeline import Pipeline, pipeline, node

def create_pipeline(**kwargs) -> Pipeline:
    return pipeline([
        node(func=preprocess, inputs=["raw_data", "parameters"], outputs="clean_data", name="preprocess_node"),
    ])
```

### Catalog Pattern

```yaml
clean_data:
  type: pandas.ParquetDataset
  filepath: data/02_intermediate/clean_data.pq
```

### Pipeline Registry

```python
from kedro.pipeline import find_pipelines

def register_pipelines():
    pipelines = find_pipelines(raise_errors=True)
    pipelines["__default__"] = sum(pipelines.values())
    return pipelines
```

## When Invoked

1. **Detect Kedro version** — Check project files for version constraints
2. **Read existing code** — Understand project structure and conventions before modifying
3. **Follow existing style** — Match the codebase's patterns
4. **Write pure nodes** — No side effects, no catalog access, type hints on all functions
5. **Configure catalog explicitly** — Use appropriate dataset types and data layers
6. **Test thoroughly** — Unit test nodes, integration test pipelines
7. **Run quality checklist** — Before completing, verify patterns match standards
