---
name: internet-research
description: Expert internet research using Tavily and Brave Search. Use when the user needs current information beyond knowledge cutoff, real-time data (prices, stats, news), fact verification, documentation lookups, latest package versions, or current events.
---

# Internet Research Skill

This skill provides Claude Code with expert-level internet research capabilities using two complementary MCP servers: **Tavily** (AI-native search, extraction, crawling) and **Brave Search** (multimedia search, news, local).

## Prerequisites

- **Tavily MCP** server configured in **user scope**
- **Brave Search MCP** server configured in **user scope**
- `TAVILY_API_KEY` and `BRAVE_API_KEY` environment variables set in your shell profile

**Setup (if not already done):**
```bash
# Add Tavily MCP to user scope
claude mcp add tavily --scope user \
  -e TAVILY_API_KEY='${TAVILY_API_KEY}' \
  -- npx -y tavily-mcp@latest

# Add Brave Search MCP to user scope
claude mcp add brave-search --scope user \
  -e BRAVE_API_KEY='${BRAVE_API_KEY}' \
  -- npx -y @brave/brave-search-mcp-server

# Verify both are configured
claude mcp list
```

## When to Use This Skill

Invoke this skill when the user needs:
- Current information beyond your knowledge cutoff
- Real-time data (prices, stats, news)
- Verification of facts or claims
- Documentation lookups
- Latest version information for packages/tools
- Current events or recent developments

## Task-Based Tool Routing

These two servers are **complementary tools with different jobs**, not competing alternatives. Route by task type:

| Task | Tool | Why |
|------|------|-----|
| Technical docs, APIs, coding questions | `mcp__tavily__tavily_search` | AI-native, token-efficient results |
| General/casual web search | `mcp__brave-search__brave_web_search` | Equal free quota (1,000/mo) |
| Image search | `mcp__brave-search__brave_image_search` | Brave exclusive |
| Video search | `mcp__brave-search__brave_video_search` | Brave exclusive |
| News search | `mcp__brave-search__brave_news_search` | Brave exclusive |
| Local business search | `mcp__brave-search__brave_local_search` | Brave exclusive |
| Extract content from URLs | `mcp__tavily__tavily_extract` | Tavily exclusive |
| Crawl a website | `mcp__tavily__tavily_crawl` | Tavily exclusive |
| Map a website's structure | `mcp__tavily__tavily_map` | Tavily exclusive |
| Deep multi-source research | `mcp__tavily__tavily_research` | Tavily exclusive |
| Either server's quota exhausted | The other one | Fallback |

## Available Tools — Tavily

### `mcp__tavily__tavily_search`
AI-native web search. Returns pre-cleaned, structured, LLM-optimized results. Best for technical and coding queries.

**Parameters:**
- `query` (required): Search terms
- `search_depth` (optional): `"basic"` | `"advanced"` | `"fast"` | `"ultra-fast"` (default: `"basic"`)
- `max_results` (optional): Number of results (default: 5, max: 20)
- `time_range` (optional): `"day"` | `"week"` | `"month"` | `"year"`
- `include_domains` (optional): Array of domains to include
- `exclude_domains` (optional): Array of domains to exclude
- `country` (optional): Boost results from specific country

### `mcp__tavily__tavily_extract`
Extract clean content from URLs in markdown or text format.

**Parameters:**
- `urls` (required): Array of URLs to extract content from
- `extract_depth` (optional): `"basic"` | `"advanced"` (use advanced for LinkedIn, protected sites)
- `format` (optional): `"markdown"` | `"text"` (default: `"markdown"`)

### `mcp__tavily__tavily_crawl`
Crawl a website with configurable depth and breadth.

**Parameters:**
- `url` (required): Root URL to begin crawling
- `max_depth` (optional): How far from base URL (default: 1)
- `limit` (optional): Total links to process (default: 50)

### `mcp__tavily__tavily_map`
Map a website's structure, returning discovered URLs.

**Parameters:**
- `url` (required): Root URL to begin mapping

### `mcp__tavily__tavily_research`
Comprehensive multi-source research with AI synthesis.

**Parameters:**
- `input` (required): Description of the research task
- `model` (optional): `"mini"` | `"pro"` | `"auto"` (default: `"auto"`)

## Available Tools — Brave Search

### `mcp__brave-search__brave_web_search`
General web search. Best for routine queries and preserving Tavily credits.

**Parameters:**
- `query` (required): Search terms
- `count` (optional): Number of results (default: 10, max: 20)
- `offset` (optional): Pagination offset

### `mcp__brave-search__brave_image_search`
Image search — only available via Brave.

### `mcp__brave-search__brave_video_search`
Video search — only available via Brave.

### `mcp__brave-search__brave_news_search`
News search with freshness controls — only available via Brave.

### `mcp__brave-search__brave_local_search`
Local business/place search — only available via Brave.

## Search Strategy

### Step 1: Formulate Effective Queries
- Be specific: "Next.js 14 app router migration guide" > "nextjs help"
- Include year for current info: "React best practices 2026"
- Use quotes for exact phrases: `"useEffect cleanup function"`

### Step 2: Route to the Right Tool
Use the task-based routing table above. Key rules:
- **Coding/docs/APIs** → `tavily_search` (AI-native quality matters here)
- **Images/video/news/local** → Brave (only option)
- **General web search** → `brave_web_search` (preserves Tavily credits)
- **URL content extraction** → `tavily_extract` (cleaner than WebFetch)
- **Deep research** → `tavily_research` (built-in multi-source synthesis)

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

| User Request | Tool | Effective Query |
|-------------|------|-----------------|
| "How to use React Server Components" | Tavily Search | "React Server Components tutorial 2026" |
| "Find images of the new MacBook" | Brave Image | "MacBook Pro 2026" |
| "Latest tech news today" | Brave News | "technology news today" |
| "What restaurants are near Union Square" | Brave Local | "restaurants Union Square" |
| "Research WebAssembly limitations" | Tavily Research | "Current state of WebAssembly support and limitations" |
| "What's the weather in Chicago" | Brave Web | "weather Chicago today" |
| "Extract the API docs from this URL" | Tavily Extract | (pass URL) |

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

If Tavily fails:
1. Check if `TAVILY_API_KEY` is set
2. Fall back to `mcp__brave-search__brave_web_search`
3. Fall back to knowledge cutoff information with disclaimer

If Brave fails:
1. Check if `BRAVE_API_KEY` is set
2. Fall back to `mcp__tavily__tavily_search`
3. Fall back to built-in WebSearch

## Quota Management

| Server | Free Tier | Best For |
|--------|-----------|----------|
| Tavily | 1,000 credits/mo | Technical/coding queries, extraction, crawling, research |
| Brave | 1,000 queries/mo ($5 free credits) | General web search, images, video, news, local |

- Route by task to maximize value from both free tiers
- Combined: ~2,000 queries/month with no waste
- Be efficient with queries — cache results mentally within conversation
