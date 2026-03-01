---
name: web-search
description: Perform a quick internet search using Claude's built-in WebSearch tool. Use when the user asks to search the web, look something up, or needs current information.
argument-hint: <query>
---

# Web Search Command

Perform a quick internet search using Claude's built-in WebSearch tool.

## Usage

```
/web-search <query>
```

## Tool Binding

**IMPORTANT:** You MUST use the built-in `WebSearch` tool for this command. Do NOT use any MCP tools.

## Arguments

- `query`: The search terms (everything after `/web-search`)

## Behavior

When invoked:
1. Use the `WebSearch` tool with the provided query
2. Analyze the top results
3. Provide a concise summary
4. List sources with URLs

## Examples

```
/web-search latest Claude Code features
/web-search how to configure TypeScript strict mode
/web-search React 19 release notes
```

## Response Format

```markdown
## Search: [query]

### Results

[Summarized findings from search results]

### Sources
- [Title](URL)
- [Title](URL)
- [Title](URL)
```

## When to Use

- Quick lookups that don't require Brave Search API
- When `BRAVE_API_KEY` is not configured
- General web searches where built-in search is sufficient

## See Also

- `/brave-search` - Uses Brave Search MCP for potentially different results
- `internet-researcher` agent - For deep, multi-query research
