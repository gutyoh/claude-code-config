# Brave Search Command

Perform an internet search using the official Brave Search MCP server.

## Usage

```
/brave-search <query>
```

## Description

This command performs an internet search using the official `@brave/brave-search-mcp-server` package. It provides web results, images, videos, rich results, and AI summaries.

## Tool Binding

**IMPORTANT:** You MUST use the `mcp__brave-search__brave_web_search` tool for this command. Do NOT use the built-in `WebSearch` tool.

## Prerequisites

- Brave Search MCP server configured in `.mcp.json` using `@brave/brave-search-mcp-server`
- `BRAVE_API_KEY` environment variable set (get one at https://brave.com/search/api/)

## Arguments

- `query`: The search terms (everything after `/brave-search`)

## Behavior

When invoked:
1. Execute exactly one `mcp__brave-search__brave_web_search` call with the provided query — never fire multiple searches per invocation
2. Analyze the top results
3. Provide a concise summary
4. List sources with URLs

## Examples

```
/brave-search latest Next.js features
/brave-search how to configure ESLint for TypeScript
/brave-search React Server Components best practices
```

## Response Format

```markdown
## Brave Search: [query]

### Results

[Summarized findings from search results]

### Sources
- [Title](URL)
- [Title](URL)
- [Title](URL)
```

## When to Use

- When you specifically want Brave Search results
- For searches that may benefit from Brave's privacy-focused index
- When you need local search via `mcp__brave-search__brave_local_search`

## Error Handling

If the search fails:
1. Verify `BRAVE_API_KEY` is set correctly
2. Check that the MCP server is running (`/mcp` to verify status)
3. Suggest using `/web-search` as a fallback

## See Also

- `/web-search` - Uses Claude's built-in WebSearch (no MCP required)
- `internet-researcher` agent - For deep, multi-query research using Brave Search
