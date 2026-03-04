# Prompt Migration Guide

## Overview

Migrate hardcoded prompts to Langfuse for version control, A/B testing, and deployment workflows.

## Before Starting

Fetch the current prompt management docs:

```bash
curl -s https://langfuse.com/docs/prompts/get-started.md
```

## 8-Step Migration Flow

### Step 1: Inventory Existing Prompts

```bash
# Find hardcoded prompts in the codebase
grep -rn "system.*prompt\|SYSTEM_PROMPT\|system_message" \
  --include="*.py" --include="*.ts" --include="*.js" . | head -30

# Find template strings that look like prompts
grep -rn "You are\|As an AI\|Your role is" \
  --include="*.py" --include="*.ts" --include="*.js" . | head -20
```

### Step 2: Check Existing Prompts in Langfuse

```bash
npx langfuse-cli api prompts list --json
```

### Step 3: Understand Template Syntax

Langfuse uses `{{variable}}` double-brace syntax (Mustache-style):

```
You are a {{role}}. Answer the user's question about {{topic}}.

Context: {{context}}

Question: {{question}}
```

**Limitations**:
- No conditionals (`{{#if}}` / `{{#unless}}`)
- No loops (`{{#each}}`)
- No helpers or filters
- Variables only — `{{variable_name}}`

### Step 4: Create Prompts in Langfuse

```bash
# Text prompt
npx langfuse-cli api prompts create --json \
  --name "my-assistant" \
  --prompt "You are a {{role}} assistant. Help the user with: {{task}}" \
  --type "text" \
  --labels '["staging"]' \
  --config '{"temperature": 0.7, "model": "claude-sonnet-4-5-20250929"}'

# Chat prompt (OpenAI message format)
npx langfuse-cli api prompts create --json \
  --name "chat-assistant" \
  --type "chat" \
  --prompt '[
    {"role": "system", "content": "You are a {{role}} assistant."},
    {"role": "user", "content": "{{user_input}}"}
  ]' \
  --labels '["staging"]'
```

### Step 5: Refactor Code to Fetch from Langfuse

**Python:**

```python
from langfuse import get_client

client = get_client()

# Fetch prompt (cached automatically)
prompt = client.get_prompt("my-assistant")

# Compile with variables
compiled = prompt.compile(role="helpful", task="coding questions")

# Use with your LLM call
response = llm.chat(system=compiled, ...)
```

**JS/TS:**

```typescript
import { Langfuse } from "langfuse";

const langfuse = new Langfuse();

const prompt = await langfuse.getPrompt("my-assistant");
const compiled = prompt.compile({ role: "helpful", task: "coding questions" });
```

### Step 6: Link Prompts to Traces

```python
from langfuse.decorators import observe, langfuse_context

@observe()
def chat(user_input: str) -> str:
    prompt = langfuse_context.get_prompt("my-assistant")
    compiled = prompt.compile(role="helpful", task="general")

    # The prompt version is automatically linked to the trace
    generation = langfuse_context.update_current_observation(
        prompt=prompt,
    )

    return call_llm(compiled, user_input)
```

### Step 7: Deploy via Labels

```bash
# Promote staging to production
npx langfuse-cli api prompts update --json \
  --name "my-assistant" \
  --version 3 \
  --labels '["production"]'

# Fetch production version in code
prompt = client.get_prompt("my-assistant", label="production")
```

### Step 8: Verify Migration

```bash
# Verify prompt exists and has correct labels
npx langfuse-cli api prompts get "my-assistant" --json

# Check all versions
npx langfuse-cli api prompt-versions list --name "my-assistant" --json

# Verify traces are using the prompt
npx langfuse-cli api traces list --limit 5 --json \
  --filter '[{"type":"string","column":"name","operator":"contains","value":"my-assistant"}]'
```

## Naming Conventions

| Pattern | Example | Use For |
|---------|---------|---------|
| `feature-purpose` | `chat-system` | Main prompts |
| `feature-purpose-variant` | `chat-system-concise` | A/B test variants |
| `module.purpose` | `rag.reranker` | Module-scoped prompts |

## Common Mistakes

1. **Using Jinja2 syntax** — Langfuse uses `{{var}}`, not `{var}` or `{{ var | filter }}`
2. **Not setting labels** — Without labels, code fetches the latest version which may be untested
3. **Forgetting to link prompts to traces** — Pass the `prompt` object to the observation for version tracking
4. **Not caching** — The SDK caches prompts automatically; don't add your own caching layer on top
5. **Hardcoding fallbacks** — If Langfuse is down, the SDK returns the cached version; don't duplicate the prompt in code
