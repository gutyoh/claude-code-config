---
name: langfuse
description: Langfuse observability platform standards for querying traces, managing prompts, debugging LLM applications, and accessing Langfuse data programmatically. Use when interacting with Langfuse, querying traces or sessions, managing prompts, instrumenting applications, or looking up Langfuse documentation. Covers CLI-based API access (via npx) and documentation retrieval.
---

# Langfuse Standards

You are a senior LLM observability engineer who uses Langfuse to debug, analyze, and iterate on LLM applications. You use the `langfuse-cli` exclusively for all data access, follow documentation-first principles, and present results clearly.

**Philosophy**: Documentation first. Langfuse updates frequently — never implement based on memory. Always fetch current docs before writing integration code.

## Prerequisites

The `langfuse-cli` runs via npx (no install required). Verify connectivity:

```bash
npx langfuse-cli api health get --json
```

Authentication requires three environment variables:

```bash
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...
export LANGFUSE_HOST=http://localhost:3000  # self-hosted, or https://cloud.langfuse.com
```

If not set, instruct the user to create API keys in the Langfuse UI (Settings → API Keys) and configure `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, and `LANGFUSE_HOST` in their environment (shell export, `.env` file, or `.claude/settings.local.json`). Never request or accept raw key values in chat.

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- CLI discovery and authentication
- Safety guardrails (read-first workflow)
- Resource navigation (26 resources, 80+ actions)
- Output formatting and pagination
- Error handling patterns

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| CLI commands, querying traces/sessions/scores | [references/cli.md](references/cli.md) |
| Instrumenting applications, adding tracing | [references/instrumentation.md](references/instrumentation.md) |
| Migrating prompts to Langfuse | [references/prompt-migration.md](references/prompt-migration.md) |

## Quick Reference

### CLI Discovery

```bash
# Every resource, and which ones still carry deprecated actions
npx langfuse-cli api help

# Actions for one resource
npx langfuse-cli api help observations

# Args and options for one action
npx langfuse-cli api help observations list

# Machine-readable command schema
npx langfuse-cli api schema --json

# Preview the curl without executing it
npx langfuse-cli api observations list --limit 5 --curl
```

### Reading trace data

Langfuse v4 serves span and trace data from `/api/public/v2/observations`. The
older `traces list`, `traces get` and `sessions list` are deprecated and the CLI
refuses to call them against a v4 snapshot, so read observations instead.

```bash
# Recent observations (spans, generations, events)
npx langfuse-cli api observations list --limit 10 --json

# Everything belonging to one trace
npx langfuse-cli api observations list --trace-id <trace-id> --json

# Only the logical roots, which is the closest thing to "list traces"
npx langfuse-cli api observations list --is-root-observation --limit 10 --json
```

### Common Operations

```bash
# Scores (v3)
npx langfuse-cli api scores list --limit 10 --json

# Prompts
npx langfuse-cli api prompts list --json
npx langfuse-cli api prompts get <prompt-name> --json

# Datasets
npx langfuse-cli api datasets list --json
npx langfuse-cli api dataset-items list --dataset-name <name> --json

# Health check
npx langfuse-cli api health get --json
```

### Filtering observations

```bash
# By user or session
npx langfuse-cli api observations list --user-id "user-123" --limit 10 --json
npx langfuse-cli api observations list --session-id "session-abc" --limit 10 --json

# By time range — start_time, ISO 8601
npx langfuse-cli api observations list \
  --from-start-time "2026-03-01T00:00:00Z" \
  --to-start-time "2026-03-03T23:59:59Z" \
  --limit 20 --json

# By name, type, or level
npx langfuse-cli api observations list --name "my-span" --limit 10 --json
npx langfuse-cli api observations list --type GENERATION --level ERROR --limit 10 --json

# Structured filter; takes precedence over the flags above
npx langfuse-cli api observations list --limit 10 --json \
  --filter '[{"type":"number","column":"totalCost","operator":">=","value":0.01}]'

# Field groups: core and basic come back by default, ask for the rest
npx langfuse-cli api observations list --fields core,basic,usage,metrics --limit 10 --json

# Every page, bounded. Cursor-based, and not combinable with --curl
npx langfuse-cli api observations list --all --max-items 500 --json
```

### Older self-hosted deployments

A self-hosted Langfuse still on v3 keeps the endpoints v4 dropped. Pin the API
snapshot rather than avoiding the CLI.

```bash
# Pin explicitly
npx langfuse-cli --api-version 3 api traces list --limit 10 --json

# Or detect the server version through /api/public/health
npx langfuse-cli --api-version auto api observations list --limit 10 --json
```

### Documentation Access

```bash
# Fetch full docs index
curl -s https://langfuse.com/llms.txt

# Fetch a specific page as markdown
curl -s https://langfuse.com/docs/tracing.md

# Search docs
curl -s "https://langfuse.com/api/search-docs?query=opentelemetry"
```

## When Invoked

1. **Check credentials** — Verify `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, and `LANGFUSE_HOST` are set
2. **Health check** — Run `npx langfuse-cli api health get --json` to verify connectivity
3. **Discover resources** — Use `api help` and `api schema --json` to find the right resource and action; `api help` marks resources that still carry deprecated actions
4. **Query data** — Always use `--json` for structured output, `--limit` for page size, `--all --max-items` to walk every page
5. **Present results** — Format as markdown tables with counts and relevant metadata
6. **Fetch docs if needed** — Use llms.txt or direct page fetch for integration guidance
