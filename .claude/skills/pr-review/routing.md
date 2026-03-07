# File-to-Expert Routing Table

Map changed files to the appropriate expert subagent by extension and project indicators.

## Routing Table

| File Pattern | Expert Subagent (`subagent_type`) | Detection |
|-------------|----------------------------------|-----------|
| `*.py` | `python-expert` | Any `.py` file |
| `*.rs`, `Cargo.toml`, `Cargo.lock` | `rust-expert` | Any Rust file or Cargo changes |
| `*.cs`, `*.csproj`, `*.sln`, `*.razor` | `dotnet-expert` | Any C#/.NET file |
| `*.sql` + `dbt_project.yml` exists | `dbt-expert` | SQL files in a dbt project context |
| `*.d2` | `d2-tala-expert` | D2 diagram files |
| `pipeline_registry.py`, `catalog*.yml` (in Kedro project) | `kedro-expert` | Kedro project patterns |
| `*.css`, `*.scss`, `*.tsx`, `*.jsx` (UI components) | `ui-designer` | Frontend/UI files |
| All other files | **Self-review** | Orchestrator reviews directly |

## Rules

1. **Check extensions first**, then project context (e.g., `.sql` alone is not enough for `dbt-expert` — `dbt_project.yml` must exist)
2. **One file can match multiple experts** — spawn all relevant ones
3. **Self-review** covers: Markdown, YAML configs, shell scripts, Dockerfiles, Makefiles, `.json`, `.toml`, `.yml` (non-Kedro), and any unmatched type
4. **Cap at 6 subagents** — if more than 6 experts match, merge the domains with fewest files into self-review
5. **Skip empty domains** — don't spawn a subagent for 0 files

## Priority When Over Cap

If more than 6 experts are needed, prioritize by file count (most files = higher priority). Merge the rest into self-review:

1. Count files per expert domain
2. Keep the top 6 domains as subagents
3. Move remaining domains to self-review
