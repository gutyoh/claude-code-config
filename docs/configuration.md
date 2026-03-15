# Configuration

All configuration surfaces, settings, environment variables, and CLI flags.

## Configuration files

| File | Scope | Purpose |
|------|-------|---------|
| `~/.claude/settings.json` | User (all projects) | Hooks, statusLine, fileSuggestion, env vars |
| `.claude/settings.json` | Project | Project-specific hooks and settings |
| `.claude/settings.local.json` | Local (gitignored) | Machine-specific overrides, permissions |
| `~/.claude/statusline.conf` | User | Statusline rendering configuration |
| `~/.claude.json` | User | MCP server registrations (managed by `claude mcp add`) |
| `.mcp.json` | Project | Project-scoped MCP servers |
| `~/.claude/mcp-keys.env` | User (gitignored) | MCP API keys for envfile backend |

## settings.json

### hooks

| Event | Matcher | Hook Script | Purpose |
|-------|---------|-------------|---------|
| `PreToolUse` | `Bash` | `enforce-git-pull-rebase.sh` | Add `--rebase` to git pull |
| `PreToolUse` | `mcp__ide__getDiagnostics` | `open-file-in-ide.sh` | Open file in IDE before diagnostics |
| `PreToolUse` | `.*` | `refresh-usage-cache.sh` | Refresh usage cache on every tool call |
| `PreToolUse` | `mcp__brave-search__.*` | `rate-limit-brave-search.sh` | Rate limit Brave Search calls |
| `Stop` | `""` | `refresh-usage-cache.sh` | Refresh usage cache when agent stops |

### statusLine

| Field | Value | Description |
|-------|-------|-------------|
| `type` | `"command"` | Runs a shell command |
| `command` | `"~/.claude/scripts/statusline.sh"` | Path to statusline script |
| `padding` | `0` | No padding |

### fileSuggestion

| Field | Value | Description |
|-------|-------|-------------|
| `type` | `"command"` | Runs a shell command |
| `command` | `"~/.claude/scripts/file-suggestion.sh"` | Path to file suggestion script |

### env

| Variable | Value | Description |
|----------|-------|-------------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` | Enable experimental agent teams |

## statusline.conf

12 configuration keys for `~/.claude/statusline.conf`:

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `theme` | `dark`, `light`, `colorblind`, `none` | `dark` | Color theme |
| `components` | Comma-separated list | `model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email` | Which components to show |
| `bar_style` | `text`, `block`, `smooth`, `gradient`, `thin`, `spark` | `text` | Progress bar visual style |
| `bar_pct_inside` | `true`, `false` | `false` | Show percentage inside bar |
| `compact` | `true`, `false` | `true` | No labels, merged tokens |
| `color_scope` | `percentage`, `full` | `percentage` | Color usage only or entire line |
| `icon` | Unicode string or empty | `""` | Prefix icon |
| `icon_style` | `plain`, `bold`, `bracketed`, `rounded`, `reverse`, `bold-color`, `angle`, `double-bracket` | `plain` | Icon styling |
| `weekly_show_reset` | `true`, `false` | `false` | Show weekly reset countdown |
| `cc_status_position` | `inline`, `newline` | `inline` | Status placement |
| `cc_status_visibility` | `always`, `problem_only` | `always` | When to show status |
| `cc_status_color` | `none`, `full`, `status_only` | `full` | Status coloring |

## .mcp.json

| Server | Package | Environment Variable |
|--------|---------|---------------------|
| `brave-search` | `@brave/brave-search-mcp-server` | `BRAVE_API_KEY` |
| `tavily` | `tavily-mcp@0.2.17` | `TAVILY_API_KEY` |

Both use `${VAR}` syntax for runtime environment variable expansion.

## Environment variables

### Required

| Variable | Purpose | Where to get it |
|----------|---------|----------------|
| `BRAVE_API_KEY` | Brave Search MCP server | https://api-dashboard.search.brave.com/ |
| `TAVILY_API_KEY` | Tavily MCP server | https://tavily.com |

### Optional

| Variable | Default | Purpose |
|----------|---------|---------|
| `BRAVE_API_RATE_LIMIT_MS` | `1100` | Rate limit between Brave Search calls (ms). Set to `50` for paid plans. |
| `CLAUDE_IDE` | Auto-detected | Force a specific IDE for diagnostics hook |
| `LANGFUSE_PUBLIC_KEY` | — | Langfuse observability (self-hosted or cloud) |
| `LANGFUSE_SECRET_KEY` | — | Langfuse observability |
| `LANGFUSE_HOST` | — | Langfuse host URL |
| `SONARQUBE_TOKEN` | — | SonarQube server authentication |
| `SONARQUBE_URL` | — | SonarQube server URL |
| `KEY_ROTATE_BACKEND` | Auto-detected | Force `doppler` or `dotenv` for key rotation |
| `KEY_ROTATE_DOTENV` | `$REPO_ROOT/.env` | Path to .env file for key rotation |
| `MCP_KEY_ROTATE_CACHE_DIR` | `/tmp/mcp-key-rotate-cache` | Cache directory for quota checks |
| `MCP_KEY_ROTATE_CACHE_TTL` | `300` | Cache TTL in seconds for quota checks |
| `CODEX_TOKEN_MAX_AGE_HOURS` | `48` | Max age for Codex auth token before warning |
| `HOOK_STALE_THRESHOLD` | `300` | Seconds before hook cache data is marked stale |

## setup.sh CLI flags

| Flag | Argument | Effect |
|------|----------|--------|
| `-y`, `--yes` | — | Accept all defaults, skip interactive prompts |
| `--mcp` | Comma-separated list | Servers to install: `brave-search`, `tavily` |
| `--no-mcp` | — | Skip MCP server installation |
| `--no-agents` | — | Skip agents and skills symlinks |
| `--agent-teams` | — | Enable experimental agent teams |
| `--no-agent-teams` | — | Disable agent teams |
| `--minimal` | — | Disable agents, MCP, agent teams, and proxy PATH |
| `--overwrite-settings` | — | Overwrite existing settings.json |
| `--skip-settings` | — | Do not modify settings.json |
| `--theme` | `dark`, `light`, `colorblind`, `none` | Statusline color theme |
| `--components` | Comma-separated list | Statusline components |
| `--bar-style` | `text`, `block`, `smooth`, `gradient`, `thin`, `spark` | Progress bar style |
| `--bar-pct-inside` | — | Show percentage inside bar |
| `--compact` | — | Enable compact mode |
| `--no-compact` | — | Disable compact mode |
| `--color-scope` | `percentage`, `full` | Color scope |
| `--icon` | `none`, `spark`, `anthropic`, `sparkle`, `star`, or custom | Prefix icon |
| `--icon-style` | `plain`, `bold`, `bracketed`, `rounded`, `reverse`, `bold-color`, `angle`, `double-bracket` | Icon styling |
| `--weekly-show-reset` | — | Show weekly reset countdown |
| `--no-weekly-show-reset` | — | Hide weekly reset countdown |
| `--proxy-path` | — | Add `bin/` to shell PATH |
| `--no-proxy-path` | — | Skip proxy PATH setup |
| `-h`, `--help` | — | Show usage and exit |

## Branch protection rule schemas

### Trunk-based (main-branch-protection.json)

| Rule | Setting |
|------|---------|
| `deletion` | Blocked |
| `non_fast_forward` | Blocked |
| `required_approving_review_count` | `0` (solo dev default) |
| `dismiss_stale_reviews_on_push` | `true` |
| `required_review_thread_resolution` | `true` |
| `allowed_merge_methods` | `["squash", "merge"]` |

### GitFlow main

Same as trunk-based except: `required_approving_review_count: 1`, `allowed_merge_methods: ["merge"]`.

### GitFlow develop

Same as trunk-based: `required_approving_review_count: 0`, `allowed_merge_methods: ["squash", "merge"]`.

## See also

- [Project Structure](project-structure.md): where each configuration file lives in the repo
- [How to Configure the Statusline](how-to-configure-statusline.md): walkthrough for statusline.conf options
- [How to Add an MCP Server](how-to-add-mcp-server.md): walkthrough for .mcp.json and key setup
- [Design Decisions](design-decisions.md): why these configuration patterns were chosen
