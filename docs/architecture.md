# Architecture

This document explains how the claude-code-config system is designed and why the design choices were made. It covers the symlink architecture, the agent+skill pattern, the hook system, the statusline data pipeline, and the MCP key management system.

## System overview

The core idea is simple: a single Git repository contains all Claude Code configuration. A setup script symlinks the repo's `.claude/` directory into `~/.claude/`, making everything available globally. Pulling updates from Git automatically updates the configuration.

```mermaid
flowchart TD
    REPO["Git Repository<br/><i>claude-code-config/</i>"]
    SETUP["setup.sh<br/><i>Creates symlinks</i>"]
    GLOBAL["~/.claude/<br/><i>Global config</i>"]
    SESSION["Claude Code Session<br/><i>Any project directory</i>"]

    REPO --> SETUP
    SETUP -->|symlinks| GLOBAL
    GLOBAL -->|loaded at startup| SESSION

    subgraph "What gets symlinked"
        HOOKS[".claude/hooks/"]
        SCRIPTS[".claude/scripts/"]
        SKILLS[".claude/skills/"]
        AGENTS[".claude/agents/"]
    end

    REPO --> HOOKS
    REPO --> SCRIPTS
    REPO --> SKILLS
    REPO --> AGENTS
```

This means no files are copied. The symlinks point back to the Git repo. When you `git pull`, the changes propagate instantly — no reinstallation required.

## The agent + skill pattern

Every domain expert follows the same two-component pattern: an **agent** that defines persona and behavior, and a **skill** that provides the actual knowledge.

```mermaid
flowchart LR
    CLAUDE["Claude Code<br/><i>Main conversation</i>"]
    AGENT["Agent<br/><i>.claude/agents/python-expert.md</i>"]
    SKILL["SKILL.md<br/><i>Entry point + routing</i>"]
    CORE["core.md<br/><i>Always loaded</i>"]
    PATTERNS["*-patterns.md<br/><i>Conditionally loaded</i>"]

    CLAUDE -->|delegates to| AGENT
    AGENT -->|loads skill| SKILL
    SKILL -->|always| CORE
    SKILL -->|based on task| PATTERNS
```

### Why separate agents from skills?

The separation serves two purposes:

1. **Context efficiency**: The agent loads `SKILL.md` which contains a conditional loading table. Only the relevant pattern files are loaded based on the task. A Python expert writing async code loads `async-patterns.md` but not `cli-patterns.md`. This preserves context window space.

2. **Reusability**: Multiple agents can load the same skill. The `pr-manager` agent loads both `pr-writing` and `pr-operations` skills. A future `full-stack-expert` could load both `python-standards` and `dotnet-standards`.

### The conditional loading pattern

Every skill follows this structure:

- `SKILL.md`: entry point with frontmatter, persona, conditional loading table, quick reference
- `core.md`: foundational principles that are ALWAYS loaded
- `*-patterns.md`: topic-specific patterns loaded ONLY when relevant
- `references/`: optional deep-dive material (checklists, API design)

The conditional loading table in `SKILL.md` tells the agent which files to read:

| Task Type | Load |
|-----------|------|
| Async code | async-patterns.md |
| Pydantic models | pydantic-patterns.md |
| CLI applications | cli-patterns.md |

This is context engineering — providing the right information at the right time, not everything all at once.

## The hook system

Hooks are standalone bash scripts that run at specific points in Claude Code's lifecycle. Each hook follows the Claude Code hook protocol: receive JSON on stdin, write to stdout/stderr, and return exit codes to control behavior.

```mermaid
flowchart TD
    EVENT["Claude Code Event<br/><i>PreToolUse, Stop, etc.</i>"]
    MATCH{"Matcher<br/><i>regex on tool name</i>"}
    HOOK["Hook Script<br/><i>.claude/hooks/*.sh</i>"]
    RESULT{"Exit Code"}
    ALLOW["Exit 0<br/><i>Allow the action</i>"]
    BLOCK["Exit 2<br/><i>Block + feed error to Claude</i>"]

    EVENT --> MATCH
    MATCH -->|matches| HOOK
    MATCH -->|no match| ALLOW
    HOOK --> RESULT
    RESULT -->|0| ALLOW
    RESULT -->|2| BLOCK
```

Each hook solves a specific problem:

- **enforce-git-pull-rebase**: ensures linear commit history by injecting `--rebase` into all `git pull` commands. The hook rewrites the command and returns it via `updatedInput` JSON.
- **open-file-in-ide**: works around JetBrains bug #3085 where diagnostics timeout if the file is not the active tab. Uses a 3-tier IDE detection system (env var → running process → PATH fallback).
- **rate-limit-brave-search**: enforces per-second rate limiting on Brave Search API calls using a filesystem mutex (`mkdir` atomic lock) and a timestamp file. Prevents quota exhaustion on the free tier.
- **validate-readonly-sql**: blocks destructive SQL operations (INSERT, UPDATE, DELETE, DROP, etc.) in databricks CLI commands. Configured at the agent level (databricks-expert frontmatter), not project level.
- **refresh-usage-cache**: fires a background Haiku API call to cache rate limit utilization data. Runs on every tool call and on agent stop.

## The statusline data pipeline

The statusline renders real-time metrics in Claude Code's status bar. It uses a 3-tier priority chain for usage data, ensuring resilience when any single data source is unavailable.

```mermaid
flowchart TD
    INPUT["Claude Code stdin<br/><i>JSON with model, version, cost</i>"]
    P1["Priority 1: Native fields<br/><i>rate_limit.five_hour_percentage</i><br/>(future Anthropic feature)"]
    P2["Priority 2: Hook cache<br/><i>~/.claude/cache/claude-usage.json</i><br/>(written by refresh-usage-cache hook)"]
    P3["Priority 3: OAuth API<br/><i>api.anthropic.com/api/oauth/usage</i><br/>(with SWR caching + backoff)"]
    CCUSAGE["ccusage blocks --json<br/><i>Token counts + cost</i>"]
    STATUS["status.claude.com API<br/><i>Service health</i>"]
    RENDER["Render components<br/><i>15 renderers, adaptive width</i>"]

    INPUT --> P1
    P1 -->|not available| P2
    P2 -->|stale or missing| P3
    P1 -->|available| RENDER
    P2 -->|fresh| RENDER
    P3 --> RENDER
    CCUSAGE --> RENDER
    STATUS --> RENDER
```

The OAuth API cache uses production-grade patterns:
- **30-second TTL** for fresh cache
- **Atomic mkdir-based locking** to prevent thundering herd across concurrent sessions
- **Decorrelated jitter backoff** (30s-300s) on API failures
- **Stale-while-error**: serves last known good value when the API is down

The service status cache (status.claude.com) uses a separate SWR pattern: 5-minute fresh TTL, 15-minute max stale, background refresh via disowned subshell.

## MCP key management

The `mcp-key-rotate` script manages pools of API keys for MCP servers. This solves the problem of free-tier quota exhaustion — when one key's credits are used up, rotate to the next.

The system auto-detects the secrets backend:

1. **Doppler** (enterprise): if the Doppler CLI is installed and configured for the project, uses Doppler secrets management.
2. **Envfile** (default): reads/writes API keys from `~/.claude/mcp-keys.env`. After rotation, syncs the active key to the envfile.

Key rotation is atomic: find the current key's index in the pool, advance to the next, and write the new active key. Quota checking calls the provider's API (Brave: response headers, Tavily: `/usage` endpoint) with a 5-minute cache to avoid redundant API calls.

## The setup system

The setup script is modular: `setup.sh` sources 8 modules from `lib/setup/`. Each module handles one concern (TUI widgets, MCP registration, settings manipulation, etc.). This keeps the main script orchestration-only.

The interactive TUI uses raw terminal input (`tui_readkey`) to build arrow-key menus, multi-select checkboxes, and yes/no toggles — all without external dependencies beyond bash. The statusline preview renders a live sample with your chosen settings before confirming.

The setup is idempotent: running it again detects existing symlinks and skips them, updates settings non-destructively (merge mode), and handles repo-move scenarios by detecting changed symlink targets.

## Cross-cutting design principles

- **No hardcoded values**: API keys use `${VAR}` expansion, profile names are discovered at runtime, tool paths use `$CLAUDE_PROJECT_DIR`
- **Graceful degradation**: missing optional tools (fd, fzf, ccusage) are skipped, not required. Stale cache data is served rather than failing.
- **POSIX portability**: all scripts target bash 3.2+ (macOS default). Millisecond timestamps use `python3` instead of GNU-only `date +%s%3N`. Atomic locking uses `mkdir` instead of `flock`.
- **Testability**: BATS test suite (11 files) covers hooks, statusline, proxy, MCP rotation, and setup CLI parsing.

## See also

- [Design Decisions](design-decisions.md): ADRs for each architectural choice (symlinks, agent+skill separation, conditional loading, etc.)
- [Project Structure](project-structure.md): complete file listing with module responsibilities
- [Configuration](configuration.md): full reference for all settings and environment variables
- [Getting Started](getting-started.md): tutorial for first-time setup
