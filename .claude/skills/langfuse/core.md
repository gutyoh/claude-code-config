# Core Principles

## 1. CLI-First — No Hardcoded Tokens

All Langfuse operations go through `langfuse-cli`. Never hardcode API keys, host URLs, or project IDs.

```bash
# CORRECT: CLI manages auth via environment variables
npx langfuse-cli api traces list --limit 10 --json

# CORRECT: Auth via env file
npx langfuse-cli --env .env api traces list --limit 10 --json

# WRONG: Hardcoded credentials
curl -u "pk-lf-xxx:sk-lf-xxx" https://cloud.langfuse.com/api/public/traces
```

## 2. Authentication — Three Methods

The CLI supports three auth methods, in priority order:

### Method 1: `.env` file (recommended, takes precedence)

```bash
npx langfuse-cli --env .env api traces list --json
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
npx langfuse-cli api traces list --json
```

### Method 3: Inline flags

```bash
npx langfuse-cli --public-key pk-lf-... --secret-key sk-lf-... --server http://localhost:3000 \
  api traces list --json
```

### Verifying Connectivity

```bash
npx langfuse-cli api healths list --json
```

If auth fails, guide the user to their Langfuse UI → Settings → API Keys.

---

## 3. Documentation First — Never Implement from Memory

Langfuse updates frequently. Before writing any integration code:

1. Fetch the docs index: `curl -s https://langfuse.com/llms.txt`
2. Fetch the specific page: `curl -s https://langfuse.com/docs/<path>.md`
3. Search if unsure: `curl -s "https://langfuse.com/api/search-docs?query=<query>"`

Only then write code using the patterns from the current docs.

---

## 4. Resource Discovery — 26 Resources, Progressive Disclosure

The CLI wraps the entire Langfuse OpenAPI spec. Start broad, drill down:

```bash
# Step 1: List all resources
npx langfuse-cli api __schema

# Step 2: List actions for a resource
npx langfuse-cli api traces --help

# Step 3: Show flags for a specific action
npx langfuse-cli api traces list --help

# Step 4: Preview the curl command
npx langfuse-cli api traces list --limit 5 --curl
```

### Available Resources (26 total)

| Resource | Key Actions | Notes |
|----------|-------------|-------|
| `traces` | list, get, delete-public | Core — query and inspect traces |
| `sessions` | list, get | Group multi-turn conversations |
| `observations-v2s` | list | **Prefer over `observations`** — richer data |
| `prompts` | list, get, create, update | Prompt management (CRUD) |
| `prompt-versions` | list | Version history for prompts |
| `datasets` | list, get, create, update, delete, run | Dataset management |
| `dataset-items` | list, get, create, update | Items within datasets |
| `dataset-run-items` | list, get | Run results for dataset items |
| `score-v2s` | list, get | **Prefer over `scores`** — list and get support |
| `scores` | create, delete | v1 — only create/delete, use v2 for queries |
| `score-configs` | list, get, create, update | Score configuration templates |
| `metrics-v2s` | list | **Prefer over `metrics`** — richer data |
| `metrics` | list | v1 — basic metrics |
| `annotation-queues` | list, get, create, update, delete + items | Human review queues |
| `comments` | list, get, create | Comments on traces/observations |
| `models` | list, get, create, delete | Model definitions and pricing |
| `healths` | list | Health check endpoint |
| `ingestions` | create | Batch ingestion endpoint |
| `organizations` | list + membership management | Org-level operations |
| `projects` | list + membership management | Project-level operations |

---

## 5. Output Formatting

### Always Use `--json`

```bash
# CORRECT: Structured JSON output
npx langfuse-cli api traces list --limit 5 --json

# WRONG: Default text output (harder to parse)
npx langfuse-cli api traces list --limit 5
```

### Pagination

```bash
# First page, 20 items
npx langfuse-cli api traces list --limit 20 --page 1 --json

# Second page
npx langfuse-cli api traces list --limit 20 --page 2 --json
```

### Preview Mode

```bash
# See the curl command without executing
npx langfuse-cli api traces list --limit 5 --curl
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
4. **Using v1 endpoints when v2 exists**: Prefer `observations-v2s`, `metrics-v2s`, `score-v2s`
5. **Using `scores` for queries**: v1 `scores` only supports create/delete — use `score-v2s` for list/get
6. **Blind mutations**: Never create/update/delete without user confirmation
7. **Missing `--limit`**: Always paginate list operations to avoid excessive data transfer
8. **Polling loops**: If an operation takes time, inform the user and let them decide when to check
