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

Every `~/.claude` path above moves to `$CLAUDE_CONFIG_DIR` when that variable is
set, and `~/.claude.json` becomes `$CLAUDE_CONFIG_DIR/.claude.json`, which is
what Claude Code itself does. See [A second profile](#a-second-profile).

## settings.json

### hooks

The hooks this repository's `.claude/settings.json` registers. Setup adds only
some of them to your user settings; [Hooks](hooks.md) says which, and what
each one does.

| Event | Matcher | Hook Script | Purpose |
|-------|---------|-------------|---------|
| `PreToolUse` | `Bash` | `enforce-git-pull-rebase.sh` | Add `--rebase` to git pull |
| `PreToolUse` | `mcp__ide__getDiagnostics` | `open-file-in-ide.sh` | Open file in IDE before diagnostics |
| `PreToolUse` | `.*` | `refresh-usage-cache.sh` | Refresh usage cache on every tool call |
| `PreToolUse` | `mcp__(tavily\|brave-search)__.*` | `guard-mcp-key.sh` | Block a search call whose API key is missing |
| `PreToolUse` | `mcp__brave-search__.*` | `rate-limit-brave-search.sh` | Rate limit Brave Search calls |
| `PostToolUse` | `mcp__(tavily\|brave-search)__.*` | `auto-rotate-mcp-key.sh` | Rotate to the next key when one runs out of quota |
| `Stop` | `""` | `refresh-usage-cache.sh` | Refresh usage cache when agent stops |
| `SessionStart` | `startup` | `session-name.sh` | Record when a session started (see [Session names](#session-names)) |
| `UserPromptSubmit` | `""` | `session-name.sh` | Name the session once, at its first prompt |
| `SessionStart` | `""` | `session-account.sh` | Record the session's account; warn when a resume changes it (see [Session accounts](hooks.md#session-accounts)) |

#### Plugin hooks

Some hooks ship as a plugin instead, `.claude/skills/config-hooks`. Claude Code
loads any folder in `~/.claude/skills/` that holds a `.claude-plugin/plugin.json`
as a plugin in every session, in place, so an update to the repository reaches
every session without touching `settings.json`. `setup.sh` links it with the
other skills; check it with `claude plugin list` (`config-hooks@skills-dir`).

| Event | Hook Script | Purpose |
|-------|-------------|---------|
| `Stop` | `stop-nudge.sh` | Nudge a listed model (`STOP_NUDGE_MODELS`, default `muse-*`) that ends its turn announcing a step it never took; `STOP_NUDGE=off` disables |

A hook registered both in `settings.json` and in the plugin runs twice, so
`setup.sh` and `setup.ps1` remove a `stop-nudge.sh` entry from `settings.json`.

#### Session links in commits

This repository is public, so its `.claude/settings.json` sets
`attribution.sessionUrl` to `false`: commits and pull requests made from a
Remote Control or cloud session here carry no `Claude-Session` link. The link
grants no access by itself; it only says which session made the change.
`setup.sh` and `setup.ps1` set the same value in your user `settings.json`, so
every repository gets it, and keep a value you set yourself.

#### Session names

Each session is named once, at its first prompt, for example
`claude-20261012T1412Z-btree-page-splits-0ed0b890`, and never renamed. The name is the
session's address: `claude --resume <name>`, `/resume`, the Remote Control list
and messages between sessions all find it by that name, so it must not move.

- **Provider**: the first part of the model id at the first prompt
  (`claude-opus-5-5` gives `claude`, `gpt-6.1-sol` gives `gpt`). A later
  `/model` switch keeps the name.
- **Time**: when the session started, to the minute. UTC by default, written
  with a `Z`; set `CLAUDE_SESSION_NAME_TZ` to an IANA zone to use local time
  with its offset, for example `claude-20261012T0430+0900-…` for `Asia/Tokyo`.
- **Topic**: a small model (`haiku`, `CLAUDE_SESSION_NAME_MODEL`) names the
  topic from the first prompt, so that prompt waits up to 8 seconds once. An
  answer longer than four words, or none in time, gives way to the prompt's
  first words. The run uses no hooks, tools, MCP servers or saved transcript,
  and no prompt text is stored. `CLAUDE_SESSION_NAME_TOPIC=off` names without
  a topic.
- **Id**: the first 8 characters of the session id. They keep two sessions
  started in the same minute on the same topic apart, and find the transcript:
  `ls ~/.claude/projects/*/0ed0b890*.jsonl`.
- **herdr tab**: inside herdr, the session's tab is named `<icon> <topic>`,
  with the plan's `icon_claude`, `icon_openai` or `icon_muse` from
  `statusline.conf` (Nerd Font icons work), else the provider's name. Only a
  numbered tab, holding one pane, is renamed.
- **Your names win**: a session that already has a name, from `/rename`,
  `claude --name`, the Claude app or this hook, is never renamed.
- **Interactive sessions only**: `claude -p` and SDK runs keep no name, so
  an agent that starts one inside a session never renames that session.
- **Opt out**: `CLAUDE_SESSION_NAME=off`.

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

Replaces Claude Code's `@` file search with `fd` piped to `fzf`: it respects
`.gitignore`, includes hidden files, follows symlinks and returns the 15 best
fuzzy matches, which keeps `@` fast in large repositories. Setup adds it only
when both `fd` and `fzf` are installed (`brew install fd fzf`,
`sudo apt-get install fd-find fzf`, or `winget install sharkdp.fd junegunn.fzf`);
on Windows the command is `~/.claude/scripts/file-suggestion.ps1`.

### env

| Variable | Value | Description |
|----------|-------|-------------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` | Enable experimental agent teams |

## statusline.conf

Keys for `~/.claude/statusline.conf`. The same keys in `statusline.d/*.conf`,
read in name order, then in `statusline.local.conf`, override it: the first for
files another tool owns, the second for that profile alone. `claude-as` shares
`statusline.conf` and `statusline.d` across accounts but never the local file.

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `theme` | `dark`, `light`, `colorblind`, `none` | `dark` | Color theme |
| `components` | Comma-separated list | `model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email` | Which components to show |
| `bar_style` | `text`, `block`, `smooth`, `gradient`, `thin`, `spark` | `text` | Progress bar visual style |
| `bar_pct_inside` | `true`, `false` | `false` | Show percentage inside bar |
| `compact` | `true`, `false` | `true` | No labels, merged tokens |
| `color_scope` | `percentage`, `full` | `percentage` | Color usage only or entire line |
| `icon` | Unicode string or empty | `""` | Prefix icon |
| `host_icon` | Unicode string or empty | `""` | Printed before the `host` component, with one space, in the host's style: for example U+F179 (`nf-fa-apple`), U+F315 (`nf-linux-raspberry_pi`) or U+F313 (`nf-linux-nixos`), which need a Nerd Font. Set it per machine in `statusline.d/` |
| `icon_claude`, `icon_openai`, `icon_muse` | Unicode string or empty | `""` (use `icon`) | Prefix icon while the session's model is on that plan, for example `A\` for Claude, U+EC81 (`nf-cod-openai`) for OpenAI and U+F06E4 (`nf-md-infinity`) for Muse. Those two need a Nerd Font in the terminal; `֍` and `∞` do not |
| `icon_style` | `plain`, `bold`, `bracketed`, `rounded`, `reverse`, `bold-color`, `angle`, `double-bracket` | `plain` | Icon styling |
| `weekly_show_reset` | `true`, `false` | `false` | Show weekly reset countdown |
| `cc_status_position` | `inline`, `newline` | `inline` | Status placement |
| `cc_status_visibility` | `always`, `problem_only` | `always` | When to show status |
| `cc_status_color` | `none`, `full`, `status_only` | `full` | Status coloring |
| `router_health` | `on`, `off` | `on` | Show a router's prompt-cache warning ([details](how-to-configure-statusline.md#usage-for-gpt-and-muse-models)) |
| `style.<component>` | Style string, for example `bold fg:#1E1E2E bg:#F38BA8` or `bold gradient:#F38BA8-#F5C2E7-#F38BA8` | none | Colors one component, such as `style.email` ([details](how-to-configure-statusline.md#style-one-component)) |

## .mcp.json

| Server | Package | Environment Variable |
|--------|---------|---------------------|
| `brave-search` | `@brave/brave-search-mcp-server` | `BRAVE_API_KEY` |
| `tavily` | `tavily-mcp@0.2.17` | `TAVILY_API_KEY` |

Both use `${VAR}` syntax for runtime environment variable expansion.

## Environment variables

### Search keys

All optional: without them the search servers stay off, `/web-search` uses the built-in search, and
`/full-search` uses keyless tiers. Each also takes a comma-separated `*_POOL` that rotates.

| Variable | Used by | Where to get it |
|----------|---------|----------------|
| `BRAVE_API_KEY` | Brave Search MCP server, `/full-search` | https://api-dashboard.search.brave.com/ |
| `TAVILY_API_KEY` | Tavily MCP server, `/full-search` | https://tavily.com |
| `FIRECRAWL_API_KEY` | `/full-search` | https://firecrawl.dev |
| `BRIGHTDATA_API_TOKEN` | `/full-search` | https://brightdata.com |

### Optional

| Variable | Default | Purpose |
|----------|---------|---------|
| `BRAVE_API_RATE_LIMIT_MS` | `1100` | Rate limit between Brave Search calls (ms). Set to `50` for paid plans. |
| `CLAUDE_IDE` | Auto-detected | Force a specific IDE for diagnostics hook |
| `CLAUDE_LEAK_GUARD` | — | Scanner command for the [public text guard](hooks.md#public-text-guard); unset, the guard does nothing |
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
| `FULL_SEARCH_FNOX` | `1` | `0` stops `/full-search` from asking fnox for keys |
| `FULL_SEARCH_STATE` | `${XDG_STATE_HOME:-~/.local/state}/full-search` | Where `/full-search` keeps its key cooldowns |
| `FULL_SEARCH_TIMEOUT` | `60` | Seconds one `/full-search` provider call may take |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude Code's config dir; setup, the statusline, the hooks and the MCP key tools follow it |
| `CLAUDE_SESSION_NAME_TZ` | `UTC` | IANA time zone for [session names](#session-names) |
| `CLAUDE_SESSION_NAME` | — | `off` disables [session names](#session-names) |
| `CLAUDE_SESSION_NAME_TOPIC` | — | `off` names sessions without a topic |
| `CLAUDE_SESSION_NAME_MODEL` | `haiku` | Model that names the topic |
| `MCP_KEYS_ENV_FILE` | `<config dir>/mcp-keys.env` | Where `mcp-env-inject` and `mcp-key-rotate` read MCP keys |

### A second profile

Claude Code reads everything from `CLAUDE_CONFIG_DIR` when it is set, so one
machine can keep two independent profiles (for example, two accounts). Install
into each one by running setup with that variable exported:

```bash
CLAUDE_CONFIG_DIR=~/.claude-work ./setup.sh
```

Commands in that profile's `settings.json` then read `~/.claude-work/...`.
Without the variable they keep the literal `~/.claude/...`, exactly as before.

## setup.sh CLI flags

| Flag | Argument | Effect |
|------|----------|--------|
| `-y`, `--yes` | — | Accept all defaults, skip interactive prompts |
| `--mcp` | Comma-separated list | Servers to install: `brave-search`, `tavily` |
| `--no-mcp` | — | Skip MCP server installation |
| `--no-agents` | — | Skip agents and skills symlinks |
| `--agent-teams` | — | Enable experimental agent teams |
| `--no-agent-teams` | — | Disable agent teams |
| `--minimal` | — | Core only: no agents, skills, MCP, agent teams, proxy PATH or OpenCode |
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
| `--proxy-path` | — | Add `bin/` to shell PATH and install the `claude` / `clp` shortcuts |
| `--no-proxy-path` | — | Skip proxy PATH setup |
| `--with-opencode` | — | Install for OpenCode even when `opencode` is not on PATH |
| `--no-opencode` | — | Skip OpenCode |
| `--shell` | Path to a shell | Install the shortcuts for this login shell instead of the detected one |
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
