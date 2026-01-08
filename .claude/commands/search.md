# Search Command

Perform an internet search using Brave Search.

## Usage

```
/search <query>
```

## Description

This command triggers an internet search for the provided query and returns summarized results with sources.

## Arguments

- `query`: The search terms (everything after `/search`)

## Behavior

When invoked:
1. Execute Brave web search with the provided query
2. Analyze top results
3. Provide concise summary
4. List sources with URLs

## Examples

```
/search latest Next.js features
/search how to configure ESLint for TypeScript
/search React Server Components best practices
```

## Response Format

The command will return:

```
## Search: [query]

### Results

[Summarized findings from search results]

### Sources
- [Title](URL)
- [Title](URL)
- [Title](URL)
```
