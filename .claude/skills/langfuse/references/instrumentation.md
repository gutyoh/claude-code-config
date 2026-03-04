# Instrumentation Guide

## Before Writing Any Code

1. **Fetch current docs** — Langfuse updates frequently:
   ```bash
   curl -s https://langfuse.com/docs/observability/get-started.md
   ```

2. **Check the integration page** for the user's framework:
   ```bash
   curl -s https://langfuse.com/llms.txt | grep -i "<framework>"
   ```

## Assess Current State

Before instrumenting, understand what the user already has:

```bash
# Check if langfuse SDK is installed
pip show langfuse 2>/dev/null || echo "Not installed"

# Check for existing Langfuse usage
grep -r "langfuse\|LANGFUSE" --include="*.py" --include="*.ts" --include="*.js" . 2>/dev/null | head -20

# Check for OpenTelemetry setup
grep -r "opentelemetry\|otel" --include="*.py" --include="*.ts" . 2>/dev/null | head -10
```

## Integration Methods (by framework)

### Native SDKs

| SDK | Install | Docs Page |
|-----|---------|-----------|
| Python | `pip install langfuse` | `/docs/sdk/python/decorators` |
| JS/TS | `npm install langfuse` | `/docs/sdk/typescript/guide` |

### Framework Integrations (50+)

| Framework | Integration Method | Docs Page |
|-----------|-------------------|-----------|
| OpenAI (Python) | `from langfuse.openai import openai` | `/docs/integrations/openai/python/get-started` |
| OpenAI (JS) | `observeOpenAI` wrapper | `/docs/integrations/openai/js/get-started` |
| LangChain | `CallbackHandler` | `/docs/integrations/langchain/tracing` |
| LlamaIndex | `set_global_handler("langfuse")` | `/docs/integrations/llama-index/get-started` |
| Vercel AI SDK | `LangfuseExporter` | `/docs/integrations/vercel-ai-sdk` |
| LiteLLM | `success_callback=["langfuse"]` | `/docs/integrations/litellm/tracing` |
| Anthropic | `@observe()` decorator | `/docs/integrations/anthropic/python` |

### OpenTelemetry (Recommended for new projects)

```bash
pip install langfuse[opentelemetry]
```

```python
from langfuse import get_client

client = get_client()
client.configure_otel_tracing()
```

Langfuse is moving toward OpenTelemetry as the primary tracing standard.

## Common Instrumentation Patterns

### Python `@observe()` Decorator

```python
from langfuse.decorators import observe, langfuse_context

@observe()
def my_function(input: str) -> str:
    # Your code here — automatically traced
    result = call_llm(input)
    return result

# Add metadata
@observe()
def my_function(input: str) -> str:
    langfuse_context.update_current_observation(
        metadata={"key": "value"},
        tags=["production"],
    )
    return call_llm(input)
```

### Session Tracking

```python
from langfuse.decorators import observe, langfuse_context

@observe()
def chat_turn(user_input: str, session_id: str) -> str:
    langfuse_context.update_current_trace(
        session_id=session_id,
        user_id="user-123",
    )
    return call_llm(user_input)
```

### Manual Span Creation

```python
from langfuse import get_client

client = get_client()

trace = client.trace(name="my-trace", user_id="user-123")
span = trace.span(name="retrieval")
# ... do work ...
span.end(output={"results": docs})

generation = trace.generation(
    name="llm-call",
    model="claude-sonnet-4-5-20250929",
    input=[{"role": "user", "content": "Hello"}],
)
# ... call LLM ...
generation.end(output="Response text", usage={"input": 100, "output": 50})
```

## Common Mistakes

1. **Not flushing** — Always call `langfuse.flush()` before process exit (or in serverless `finally` blocks)
2. **Missing session_id** — Without it, multi-turn conversations can't be grouped
3. **Not setting user_id** — Makes per-user cost tracking impossible
4. **Using wrong host** — Self-hosted users must set `LANGFUSE_HOST` (defaults to EU cloud)
5. **Forgetting to check docs** — Patterns change between versions; always fetch current docs first
