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
- **sql-guardrail**: unified database guardrail with 3 safety levels — STRICT (Databricks: blocks all mutations including CREATE/ALTER/GRANT/REVOKE), STANDARD (SQL CLIs: blocks catastrophic ops like DROP DATABASE, TRUNCATE, DELETE without WHERE), MONGO (mongosh: blocks dropDatabase, drop, deleteMany with empty filter). Configured at the agent level (databricks-expert, sql-expert, mongodb-expert frontmatter), not project level. Fails open on empty stdin, missing jq, or invalid JSON.
- **refresh-usage-cache**: fires a background Haiku API call to cache rate limit utilization data. Runs on every tool call and on agent stop.

## The statusline data pipeline

The statusline renders real-time metrics in Claude Code's status bar. Its usage figures come from the plan behind the session's model: Claude's for Claude models, the ChatGPT plan's for GPT models and the Muse Code plan's for Muse models, which Claude Code can run through a model router. A `/model` switch changes the plan shown at the next render.

```mermaid
flowchart TD
    INPUT["Claude Code stdin<br/><i>model.id, rate_limits, cost</i>"]
    PICK{"Plan behind<br/>model.id"}
    P1["1: stdin rate_limits<br/><i>five_hour, seven_day</i><br/>(when Claude Code sends them)"]
    P2["2: OAuth API<br/><i>api.anthropic.com/api/oauth/usage</i><br/>(the weekly source until stdin has it)"]
    P3["3: Hook cache<br/><i>~/.claude/cache/claude-usage.json</i><br/>(5-hour only)"]
    GPT["ChatGPT plan<br/><i>chatgpt.com/backend-api/wham/usage</i><br/>Codex login"]
    MUSE["Muse Code plan<br/><i>api.meta.ai/muse-code/key</i><br/>Muse device login"]
    SESSION["The session's own figures<br/><i>context_window, cost.total_cost_usd</i>"]
    STATUS["status.claude.com API<br/><i>Service health</i>"]
    RENDER["Render components<br/><i>15 renderers, adaptive width</i>"]

    INPUT --> PICK
    PICK -->|claude-*| P1
    PICK -->|gpt-*, o*| GPT
    PICK -->|muse-*| MUSE
    P1 -->|absent| P2
    P2 -->|no reading| P3
    P1 --> RENDER
    P2 --> RENDER
    P3 --> RENDER
    GPT --> RENDER
    MUSE --> RENDER
    INPUT --> SESSION
    SESSION --> RENDER
    STATUS --> RENDER
```

Claude's usage is one reading per account, not per session. Claude Code sends each session the `rate_limits` of its own last response, so a quiet session would fall behind while others spend the same account. Every render merges what it sees, its stdin and the shared OAuth reading, into `claude-<account>` in the state directory and shows that file. A later reset is a newer window; within one window the latest reading wins, since a plan change moves the percentage either way. A stdin reading counts as seen when the session's transcript was last written, because Claude Code repeats a quiet session's last `rate_limits` on every render. While every window was seen in the last three minutes the OAuth API is not asked at all, and a 429 waits at least its `Retry-After`. With `refreshInterval` set (setup sets 60 seconds), an idle session redraws and picks up what another session spent.

Every network reading shares one cache design:
- **A TTL per source**: 180 seconds for Claude's OAuth API, which throttles hard, and 120 seconds for the ChatGPT and Muse plans. One reading serves every session on the host.
- **Keyed by login**: Claude's by `CLAUDE_CONFIG_DIR`, the others by login file, so two accounts never show each other's usage.
- **Persistent readings**: every reading lives in `${XDG_STATE_HOME:-~/.local/state}/claude-code/statusline`, so a weekly window outlives a reboot: Claude's survives a failed first fetch, and Muse's survives an idle window. Locks and backoff stay in the temp directory; a state directory that cannot be written falls back to it.
- **Atomic mkdir-based locking** to prevent thundering herd across concurrent sessions
- **Decorrelated jitter backoff** (30s-300s) on API failures
- **Stale-while-error**: serves last known good value when the API is down, marked with `~` once it is older than 15 minutes. Each window is judged by its own reading: a weekly window carried through an idle stretch is marked even when the fetch serving it is new.

The readers never refresh a login: each login has exactly one refresher (Claude Code, Codex, the Muse CLI or a router), and a refresh token spent elsewhere signs that refresher out. Bearer tokens reach curl on stdin, never in its arguments, so they do not show in the process list. `STATUSLINE_HTTPS_PROXY` overrides the proxy inherited from Claude Code, for a router that intercepts Claude Code's traffic. Windows a plan does not have are hidden: a ChatGPT plan with only a weekly limit shows one figure, not `--`.

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
- **Graceful degradation**: missing optional tools (fd, fzf) are skipped, not required. Stale cache data is served rather than failing.
- **POSIX portability**: all scripts target bash 3.2+ (macOS default). Millisecond timestamps use `python3` instead of GNU-only `date +%s%3N`. Atomic locking uses `mkdir` instead of `flock`.
- **Testability**: BATS test suite (11 files) covers hooks, statusline, proxy, MCP rotation, and setup CLI parsing.

## See also

- [Design Decisions](design-decisions.md): ADRs for each architectural choice (symlinks, agent+skill separation, conditional loading, etc.)
- [Project Structure](project-structure.md): complete file listing with module responsibilities
- [Configuration](configuration.md): full reference for all settings and environment variables
- [Getting Started](getting-started.md): tutorial for first-time setup
