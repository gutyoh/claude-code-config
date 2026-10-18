# Read full pages with /full-search

`/web-search` returns search snippets. `/full-search` returns what a page actually renders: JavaScript-built
pages, PDFs, and sites that block a plain fetch, as Markdown files the agent reads only when it needs them.
It runs one script, `.claude/skills/full-search/scripts/full-search`, so it works the same in Claude Code,
Codex, OpenCode, Muse, or a plain shell.

```text
/full-search https://example.com/pricing        read one or more pages
/full-search how to configure envfs on NixOS    search, then read the best results
```

## Providers

The script uses the first provider that returns real content, and moves on when a page is an error,
a block page or a bot challenge:

| Order | Provider | Key | Used for |
|-------|----------|-----|----------|
| 1 | Firecrawl | optional | Most pages, JavaScript and PDFs included |
| 2 | Tavily | optional | Sites Firecrawl refuses, such as Reddit and LinkedIn |
| 3 | Bright Data | required | Only when `BRIGHTDATA_API_TOKEN` is set |
| 4 | Direct fetch | none | Static pages; the only route for private addresses |

Searches go to Tavily, then Firecrawl, then Brave when `BRAVE_API_KEY` is set.

Private and tailnet addresses, and names that do not resolve, are fetched directly and never sent to a
provider. A public page that redirects to a private address is refused.

## Add keys (optional)

With no keys, Firecrawl and Tavily answer from their keyless tiers, which cap requests per IP per day.
Keys raise those caps. Set any of these in the environment:

| Variable | Pool variable |
|----------|---------------|
| `FIRECRAWL_API_KEY` | `FIRECRAWL_API_KEY_POOL` |
| `TAVILY_API_KEY` | `TAVILY_API_KEY_POOL` |
| `BRAVE_API_KEY` | `BRAVE_API_KEY_POOL` |
| `BRIGHTDATA_API_TOKEN` | `BRIGHTDATA_API_TOKEN_POOL` |

A pool is a comma-separated list. The single variable is tried first, then the pool.

Each of the eight names comes from the first place that has it: the environment, then
`mcp-keys.env`, then fnox. A Tavily key in one place does not hide Firecrawl keys in another. A
provider tries its single key first, then its pool, whichever place each came from. To use only the
environment's keys, set `FULL_SEARCH_FNOX=0` and leave the file out.

### From mcp-keys.env

The script reads those eight names, and only those, from `~/.claude/mcp-keys.env` (or
`$MCP_KEYS_ENV_FILE`), the file the [quick start](../README.md#quick-start) puts the Brave and Tavily
keys in. The file is parsed, never run, the way a shell reads it: a value in quotes or ended by ` #`,
and the last line for a name wins. An empty value leaves that name to fnox.

### From fnox (optional)

When [fnox](https://fnox.jdx.dev) is installed, the script asks it for the names still missing that its
listing shows, each with a 10-second limit and no prompt. fnox runs from your home directory, so a
`fnox.toml` in a repository you cloned never supplies keys, unless your home directory is itself that
checkout, as in some CI containers; there set `FULL_SEARCH_FNOX=0`. Import your store from fnox's
global config, `~/.config/fnox/config.toml`:

```toml
import = ["/path/to/your/fnox.toml"]
```

## Rotation

Each key that fails for a reason that belongs to the key rests in a cooldown file shared by every agent on
the machine, `${XDG_STATE_HOME:-~/.local/state}/full-search/cooldown`. It holds a short hash of each key,
never the key:

| Answer | Rest |
|--------|------|
| Out of credit: Firecrawl 402 | Until that account renews, from Firecrawl's credit-usage endpoint, which costs no credit; a day when it does not answer |
| Spend limit: Firecrawl 402 with credit left | One hour |
| Out of credit: Tavily 432/433, Brave quota 429 | Tavily until the 1st of next month, its reset; Brave until its `X-RateLimit-Reset` |
| Rejected: 401 | One week |
| Rate limited: 429 | Its `Retry-After` or `retry_after_seconds`, else 60 s |
| Server error, site refused (403), page error | No rest |

The next key, then the keyless tier, then the next provider answers. Check the state with:

```sh
~/.claude/skills/full-search/scripts/full-search --status
```

It prints each key's last 4 characters, and why and for how long it rests.
