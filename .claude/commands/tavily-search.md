# Tavily Search Command

Perform an AI-native web search using the official Tavily MCP server.

## Usage

```
/tavily-search <query>
```

## Description

This command performs an AI-native web search using the official `tavily-mcp` package. Tavily returns pre-cleaned, structured, LLM-optimized results that are more token-efficient than traditional search snippets.

## Tool Binding

**IMPORTANT:** You MUST use the `mcp__tavily__tavily_search` tool for this command. Do NOT use the built-in `WebSearch` tool or Brave Search MCP tools.

## Prerequisites

- Tavily MCP server configured in `.mcp.json` using `tavily-mcp`
- `TAVILY_API_KEY` environment variable set (get one at https://tavily.com)

## Arguments

- `query`: The search terms (everything after `/tavily-search`)

## Behavior

When invoked:
1. Execute exactly one `mcp__tavily__tavily_search` call with the provided query — never fire multiple searches per invocation
2. Analyze the top results
3. Provide a concise summary
4. List sources with URLs

## Examples

```
/tavily-search latest Next.js features
/tavily-search how to configure ESLint for TypeScript
/tavily-search React Server Components best practices
```

## Response Format

```markdown
## Tavily Search: [query]

### Results

[Summarized findings from search results]

### Sources
- [Title](URL)
- [Title](URL)
- [Title](URL)
```

## When to Use

- When you need high-quality, AI-native search results for technical queries
- For coding documentation, API research, and programming questions
- When token efficiency matters (Tavily returns cleaner, more concise results than raw web snippets)

## Error Handling

If the search fails:
1. Verify `TAVILY_API_KEY` is set correctly
2. Check that the MCP server is running (`/mcp` to verify status)
3. Suggest using `/brave-search` or `/web-search` as a fallback

## See Also

- `/brave-search` - Uses Brave Search MCP (best for image, video, news, local search)
- `/web-search` - Uses Claude's built-in WebSearch (no MCP required)
- `internet-researcher` agent - For deep, multi-query research
