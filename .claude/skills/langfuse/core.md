# Core Principles

## 1. CLI-First — No Hardcoded Tokens

All Langfuse operations go through `langfuse-cli`. Never hardcode API keys, host URLs, or project IDs.

```bash
# CORRECT: CLI manages auth via environment variables
npx langfuse-cli api observations list --limit 10 --json

# CORRECT: Auth via env file
npx langfuse-cli --env .env api observations list --limit 10 --json

# WRONG: Hardcoded credentials
curl -u "pk-lf-xxx:sk-lf-xxx" https://cloud.langfuse.com/api/public/traces
```

## 2. Authentication — Three Methods

The CLI supports three auth methods, in priority order:

### Method 1: `.env` file (recommended, takes precedence)

```bash
npx langfuse-cli --env .env api observations list --json
```

`.env` contents:

```bash
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
LANGFUSE_HOST=http://localhost:3000
```

### Method 2: Exported environment variables

```bash
export LANGFUSE_PUBLIC_KEY=pk-lf-...
export LANGFUSE_SECRET_KEY=sk-lf-...
export LANGFUSE_HOST=http://localhost:3000
npx langfuse-cli api observations list --json
```

### Method 3: Inline flags

```bash
npx langfuse-cli --public-key pk-lf-... --secret-key sk-lf-... --host http://localhost:3000 \
  api observations list --json
```

### Verifying Connectivity

```bash
npx langfuse-cli api health get --json
```

If auth fails, instruct the user to create API keys in the Langfuse UI (Settings → API Keys) and configure them locally (shell export, `.env` file, or `.claude/settings.local.json`). Never request or accept raw key values in chat.

---

## 3. Documentation First — Never Implement from Memory

Langfuse updates frequently. Before writing any integration code:

1. Fetch the docs index: `curl -s https://langfuse.com/llms.txt`
2. Fetch the specific page: `curl -s https://langfuse.com/docs/<path>.md`
3. Search if unsure: `curl -s "https://langfuse.com/api/search-docs?query=<query>"`

Only then write code using the patterns from the current docs.

---

## 4. Resource Discovery — 34 Resources, Progressive Disclosure

The CLI wraps the entire Langfuse OpenAPI spec and pins an API snapshot. Start
broad, drill down:

```bash
# Step 1: List all resources. Ones carrying dead actions are marked
npx langfuse-cli api help

# Step 2: List actions for a resource
npx langfuse-cli api help observations

# Step 3: Show flags for a specific action
npx langfuse-cli api help observations list

# Step 4: Preview the curl command
npx langfuse-cli api observations list --limit 5 --curl

# Machine-readable schema
npx langfuse-cli api schema --json
```

### Deprecation is enforced, not advisory

Against a v4 snapshot the CLI **refuses** to call a deprecated operation and
prints the replacement. A deprecated resource is also renamed: `traces list`
resolves as `legacy-traces list`. Read span and trace data from
`observations list` (`GET /api/public/v2/observations`) instead.

For a self-hosted deployment still on v3, pin the snapshot rather than avoiding
the CLI: `--api-version 3`, or `--api-version auto` to detect it from
`/api/public/health`.

### Available Resources

| Resource | Key Actions | Notes |
|----------|-------------|-------|
| `observations` | list | Span and trace data. `list` is v2 and current |
| `traces` | delete, delete-many | `list` and `get` are deprecated — read observations |
| `scores` | list, create, delete | `list` is v3 and current |
| `scores-v2` | list, get | Deprecated — use `scores` |
| `score-configs` | list, get, create, update | Score configuration templates |
| `prompts` | list, get, create, update | Prompt management (CRUD) |
| `datasets` | list, get, create | Dataset management |
| `dataset-items` | list, get, create | Items within datasets |
| `experiments` / `experiment-items` | list, get | Experiment runs |
| `annotation-queues` | list, get, create + items | Human review queues |
| `comments` | list, get, create | Comments on traces/observations |
| `models` | list, get, create, delete | Model definitions and pricing |
| `metrics` | list | Aggregated metrics |
| `health` | get | Health check endpoint |
| `media`, `otel`, `integrations`, `llm-connections` | varies | Ingest and integration surfaces |
| `organizations`, `projects`, `scim` | list + membership | Tenancy administration |
| `feedback` | create | Feedback submission |
| `unstable-*` | varies | Dashboards and evaluators; interface may change |
| `legacy-*` | varies | v3 shapes, reachable only via `--api-version 3` |

---

## 5. Output Formatting

### Always Use `--json`

```bash
# CORRECT: Structured JSON output
npx langfuse-cli api observations list --limit 5 --json

# WRONG: Default text output (harder to parse)
npx langfuse-cli api observations list --limit 5
```

### Pagination — two styles, not one

`observations` is cursor-based; most other lists are offset-based. Using the
wrong one silently returns the first page forever.

```bash
# Cursor-based (observations): let the CLI walk the pages
npx langfuse-cli api observations list --limit 100 --all --max-items 500 --json

# Cursor-based, one page at a time
npx langfuse-cli api observations list --limit 20 --cursor "<cursor-from-previous>" --json

# Offset-based (prompts, datasets, models, ...)
npx langfuse-cli api prompts list --limit 20 --page 2 --json
```

`--all` fetches every page and therefore cannot be combined with `--curl`.

### Preview Mode

```bash
# See the curl command without executing
npx langfuse-cli api observations list --limit 5 --curl
```

---

## 6. Safety Guardrails

| Level | Operations | When |
|-------|-----------|------|
| **Default (read-only)** | list, get, health, search | Always |
| **Write (explicit + confirm)** | create prompts, create scores, create datasets | Only when user explicitly asks |
| **Destructive (double confirm)** | delete traces, delete datasets, delete scores | Only when user explicitly asks AND confirms |

### Read-First Workflow

1. Always start with read operations (list, get) to understand the current state
2. Never create, update, or delete resources without explicit user request
3. For destructive operations, show the user what will be affected first

---

## 7. Presenting Results

### Trace Summary Table

```
Recent traces (5 of 1,234)

| Name           | Timestamp           | Latency | Tokens | Cost    | Errors |
|----------------|---------------------|---------|--------|---------|--------|
| chat-completion| 2026-03-03T18:39:06 | 2.3s    | 1,523  | $0.0045 | 0      |
| rag-pipeline   | 2026-03-03T18:38:12 | 5.1s    | 3,891  | $0.0120 | 1      |
```

### Session Summary

```
Session: abc-123 (12 traces)

| Turn | Name           | Latency | Cost    |
|------|----------------|---------|---------|
| 1    | user-query     | 1.2s    | $0.003  |
| 2    | tool-call      | 0.8s    | $0.001  |
```

### Error Case

```
API Error: 401 Unauthorized
→ Check LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY are set correctly
→ Keys are found in Langfuse UI → Settings → API Keys
```

---

## 8. Anti-Patterns to Avoid

1. **Hardcoded credentials**: Never embed API keys in commands — use env vars or `.env` files
2. **Memory-based implementation**: Never write integration code without fetching current docs first
3. **Missing `--json`**: Always use `--json` for parseable output
4. **Assuming a `-v2` resource is the newer one**: it is not. `scores list` is v3 and current; `scores-v2` is deprecated. Check `api help` for the `[deprecated]` marker
5. **Reading traces from `traces list`**: deprecated and refused on v4 — read `observations list` instead
6. **Blind mutations**: Never create/update/delete without user confirmation
7. **Missing `--limit`**: Always paginate list operations to avoid excessive data transfer
8. **Polling loops**: If an operation takes time, inform the user and let them decide when to check
