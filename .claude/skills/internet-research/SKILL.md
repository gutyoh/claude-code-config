---
name: internet-research
description: Expert internet research using Brave Search. Use when the user needs current information beyond knowledge cutoff, real-time data (prices, stats, news), fact verification, documentation lookups, latest package versions, or current events.
---

# Internet Research Skill

This skill provides Claude Code with expert-level internet research capabilities using the Brave Search MCP server.

## Prerequisites

- Brave Search MCP server configured in `.mcp.json`
- `BRAVE_API_KEY` environment variable set

## When to Use This Skill

Invoke this skill when the user needs:
- Current information beyond your knowledge cutoff
- Real-time data (prices, stats, news)
- Verification of facts or claims
- Documentation lookups
- Latest version information for packages/tools
- Current events or recent developments

## Available Tools

When this skill is active, you have access to:

### `mcp__brave-search__brave_web_search`
General web search for any query.

**Parameters:**
- `query` (required): Search terms
- `count` (optional): Number of results (default: 10, max: 20)
- `offset` (optional): Pagination offset

### `mcp__brave-search__brave_local_search`
Search for local businesses and places.

**Parameters:**
- `query` (required): Business/place search terms
- `count` (optional): Number of results

## Search Strategy

### Step 1: Formulate Effective Queries
- Be specific: "Next.js 14 app router migration guide" > "nextjs help"
- Include year for current info: "React best practices 2026"
- Use quotes for exact phrases: `"useEffect cleanup function"`

### Step 2: Execute Search
```
Use mcp__brave-search__brave_web_search with your query
```

### Step 3: Analyze Results
- Check source credibility (official docs > random blogs)
- Verify date freshness
- Cross-reference if critical

### Step 4: Synthesize Response
- Summarize key findings
- Cite sources with URLs
- Note any conflicting information
- Indicate confidence level

## Example Queries

| User Request | Effective Query |
|-------------|-----------------|
| "What's new in React?" | "React 19 new features 2026" |
| "Best Node.js framework" | "Node.js framework comparison 2026 express fastify" |
| "How to deploy to Vercel" | "Vercel deployment guide Next.js" |
| "Latest TypeScript version" | "TypeScript latest version release" |

## Response Format

When presenting research results:

```markdown
## Research Results

**Query:** [what you searched for]

### Key Findings

1. **[Finding 1]**
   - Details...
   - Source: [URL]

2. **[Finding 2]**
   - Details...
   - Source: [URL]

### Summary

[Concise synthesis of findings]

### Sources
- [Source 1](URL)
- [Source 2](URL)
```

## Error Handling

If search fails:
1. Check if `BRAVE_API_KEY` is set
2. Try alternative query formulation
3. Fall back to knowledge cutoff information with disclaimer

## Rate Limits

- Free tier: 2,000 queries/month
- Be efficient with queries
- Cache results mentally within conversation
