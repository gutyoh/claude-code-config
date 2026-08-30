# Langfuse CLI Reference

## Install

```bash
# Run directly (recommended — no install needed)
npx langfuse-cli api <resource> <action>
bunx langfuse-cli api <resource> <action>

# Or install globally
npm i -g langfuse-cli
langfuse api <resource> <action>
```

## Discovery

```bash
# List all resources and auth info
npx langfuse-cli api help
npx langfuse-cli api schema --json

# List actions for a resource
npx langfuse-cli api <resource> --help

# Show args/options for a specific action
npx langfuse-cli api <resource> <action> --help

# Preview the curl command without executing
npx langfuse-cli api <resource> <action> --curl
```

## Credentials

Set environment variables:

```bash
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...
export LANGFUSE_HOST=http://localhost:3000  # self-hosted
# or: https://cloud.langfuse.com (EU), https://us.cloud.langfuse.com (US)
```

Alternative: pass `--env .env` to load from a file (takes precedence over env vars).

## Common Workflows

### Debugging a Specific Trace

```bash
# Get the trace
npx langfuse-cli api observations list --trace-id <trace-id> --json

# Get all observations in the trace (prefer v2)
npx langfuse-cli api observations list --trace-id <trace-id> --fields core,basic,io,usage --json

# Get scores for the trace
npx langfuse-cli api scores list --json \
  --filter '[{"type":"string","column":"traceId","operator":"=","value":"<trace-id>"}]'
```

### Finding Errors

```bash
# Traces with errors
npx langfuse-cli api observations list --limit 20 --json \
  --filter '[{"type":"number","column":"errorCount","operator":">","value":0}]'

# High-latency traces (>10s)
npx langfuse-cli api observations list --limit 20 --json \
  --filter '[{"type":"number","column":"latency","operator":">","value":10}]'
```

### Analyzing Costs

```bash
# Most expensive traces
npx langfuse-cli api observations list --limit 20 --json \
  --order-by "timestamp.desc" \
  --filter '[{"type":"number","column":"totalCost","operator":">=","value":0.01}]'

# Aggregated metrics (v2). The action is `get`, not `list`
npx langfuse-cli api metrics get --json
```

### Session Analysis

```bash
# List sessions
npx langfuse-cli api observations list --limit 20 --fields core,basic --json

# Get a specific session
npx langfuse-cli api observations list --session-id <session-id> --json

# All traces in a session
npx langfuse-cli api observations list --session-id <session-id> --json
```

### Prompt Management

```bash
# List all prompts
npx langfuse-cli api prompts list --json

# Get latest version of a prompt
npx langfuse-cli api prompts get <prompt-name> --json

# Get specific version
npx langfuse-cli api prompts get <prompt-name> --version 2 --json

# Get by label (e.g., "production")
npx langfuse-cli api prompts get <prompt-name> --label production --json

# Create new text prompt version
npx langfuse-cli api prompts create --json \
  --name "my-prompt" \
  --prompt "You are a {{role}}. Answer the question: {{question}}" \
  --type "text" \
  --labels '["staging"]'
```

### Dataset Operations

```bash
# List datasets
npx langfuse-cli api datasets list --json

# Get a dataset
npx langfuse-cli api datasets get <dataset-name> --json

# List items in a dataset
npx langfuse-cli api dataset-items list --dataset-name <dataset-name> --json
```

### Score Operations

```bash
# List scores (use v2 — v1 only has create/delete)
npx langfuse-cli api scores list --limit 20 --json

# Create a score
npx langfuse-cli api scores create --json \
  --trace-id <trace-id> \
  --name "quality" \
  --value 0.9
```

## Advanced Filtering

The `observations list` command supports a powerful `--filter` JSON parameter, which takes precedence over the individual query flags:

```bash
# Multiple conditions (AND)
npx langfuse-cli api observations list --limit 10 --json \
  --filter '[
    {"type":"datetime","column":"timestamp","operator":">=","value":"2026-03-01T00:00:00Z"},
    {"type":"number","column":"errorCount","operator":">","value":0},
    {"type":"arrayOptions","column":"tags","operator":"all of","value":["production"]}
  ]'

# Filter by metadata key
npx langfuse-cli api observations list --limit 10 --json \
  --filter '[
    {"type":"stringObject","column":"metadata","key":"customer_tier","operator":"=","value":"enterprise"}
  ]'
```

### Available Filter Columns

| Column | Type | Description |
|--------|------|-------------|
| `id` | string | Trace ID |
| `name` | string | Trace name |
| `timestamp` | datetime | Trace timestamp |
| `userId` | string | User ID |
| `sessionId` | string | Session ID |
| `tags` | arrayOptions | Tags array |
| `latency` | number | Latency in seconds |
| `inputTokens` | number | Total input tokens |
| `outputTokens` | number | Total output tokens |
| `totalTokens` | number | Total tokens |
| `totalCost` | number | Total cost in USD |
| `errorCount` | number | Count of ERROR observations |
| `level` | string | Highest severity level |
| `metadata` | stringObject | Metadata key-value pairs |

## Tips

- Use `--json` for machine-readable output
- Use `--curl` to preview the HTTP request without executing
- Pagination: `observations` is cursor-based (`--cursor`, or `--all --max-items`); most other lists are offset-based (`--limit` with `--page`)
- All list commands support filtering — check `<resource> <action> --help` for available options
- `observations list` is the v2 endpoint (`/api/public/v2/observations`) and the supported way to read span and trace data
- `metrics get` is the v2 metrics endpoint (`/api/public/v2/metrics`); there is no `metrics list`
- `scores list` is v3 and current; `scores-v2` is deprecated. A `-v2` suffix does not mean newer — check `api help` for the `[deprecated]` marker
- Ordering: `--order-by "timestamp.desc"` for newest-first
