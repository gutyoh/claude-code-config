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
npx langfuse-cli api healths list --json
```

Authentication requires three environment variables:

```bash
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...
export LANGFUSE_HOST=http://localhost:3000  # self-hosted, or https://cloud.langfuse.com
```

If not set, ask the user for their API keys (found in Langfuse UI → Settings → API Keys).

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
# List all 26 resources
npx langfuse-cli api __schema

# List actions for a resource
npx langfuse-cli api traces --help

# Show args/options for a specific action
npx langfuse-cli api traces list --help

# Preview the curl command without executing
npx langfuse-cli api traces list --limit 5 --curl
```

### Common Operations

```bash
# List recent traces
npx langfuse-cli api traces list --limit 10 --json

# Get a specific trace by ID
npx langfuse-cli api traces get <trace-id> --json

# List sessions
npx langfuse-cli api sessions list --limit 10 --json

# Get a session by ID
npx langfuse-cli api sessions get <session-id> --json

# List observations (prefer v2)
npx langfuse-cli api observations-v2s list --limit 10 --json

# List prompts
npx langfuse-cli api prompts list --json

# Get a prompt by name
npx langfuse-cli api prompts get <prompt-name> --json

# List scores (prefer v2)
npx langfuse-cli api score-v2s list --limit 10 --json

# List datasets
npx langfuse-cli api datasets list --json

# Health check
npx langfuse-cli api healths list --json
```

### Filtering Traces

```bash
# By user
npx langfuse-cli api traces list --user-id "user-123" --limit 10 --json

# By session
npx langfuse-cli api traces list --session-id "session-abc" --limit 10 --json

# By time range
npx langfuse-cli api traces list \
  --from-timestamp "2026-03-01T00:00:00Z" \
  --to-timestamp "2026-03-03T23:59:59Z" \
  --limit 20 --json

# By tags
npx langfuse-cli api traces list --tags "production" --limit 10 --json

# By name
npx langfuse-cli api traces list --name "my-trace-name" --limit 10 --json

# Advanced JSON filter (errors only)
npx langfuse-cli api traces list --limit 10 --json \
  --filter '[{"type":"number","column":"errorCount","operator":">","value":0}]'

# Expensive traces
npx langfuse-cli api traces list --limit 10 --json \
  --filter '[{"type":"number","column":"totalCost","operator":">=","value":0.01}]'
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
2. **Health check** — Run `npx langfuse-cli api healths list --json` to verify connectivity
3. **Discover resources** — Use `__schema` and `--help` to find the right resource and action
4. **Query data** — Always use `--json` for structured output, `--limit` for pagination
5. **Present results** — Format as markdown tables with counts and relevant metadata
6. **Fetch docs if needed** — Use llms.txt or direct page fetch for integration guidance
