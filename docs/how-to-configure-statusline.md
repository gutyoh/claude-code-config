# How to Configure the Statusline

Customize the Claude Code statusline to show model info, usage percentage, token counts, cost tracking, and service status.

## Prerequisites

- This repo's global config installed via `setup.sh`
- Required: `jq`, `bc`
- Optional: `ccusage` (`npm install -g ccusage`) — needed for token/cost/burn-rate components

## Option A: Interactive TUI (recommended)

Re-run the setup script and select **Customize installation**:

```bash
cd ~/repos/claude-code-config
./setup.sh
```

Select **Customize installation** → the statusline section walks you through:

1. **Theme**: dark (blue/yellow/orange/red), light (same), colorblind (blue/yellow/cyan/magenta), none
2. **Compact mode**: no labels, merged tokens (matches the original format)
3. **Color scope**: percentage (usage only) or full (entire line)
4. **Components**: multi-select from 15 available components
5. **Bar style**: 6 visual styles with preview
6. **Icon**: optional prefix icon with 8 styling options
7. **Live preview**: see your configuration before confirming

## Option B: CLI flags

Pass flags directly to `setup.sh`:

```bash
./setup.sh --yes \
  --theme dark \
  --bar-style smooth \
  --compact \
  --color-scope full \
  --components "model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,email" \
  --icon spark \
  --icon-style bold
```

## Option C: Edit the config file directly

Edit `~/.claude/statusline.conf`:

```ini
theme=dark
components=model,usage,weekly,reset,tokens_in,tokens_out,tokens_cache,cost,burn_rate,email
bar_style=smooth
bar_pct_inside=false
compact=true
color_scope=percentage
icon=✻
icon_style=bold
weekly_show_reset=false
cc_status_position=inline
cc_status_visibility=always
cc_status_color=full
```

## Available components

| Key | Description | Wide mode | Narrow/compact mode |
|-----|-------------|-----------|---------------------|
| `model` | Model name | `opus-4.5` | `opus-4.5` |
| `usage` | 5-hour window of the model's plan | Progress bar | `21%` |
| `weekly` | Weekly window of the model's plan | `weekly: 63%` | `63%` |
| `reset` | Reset countdown | `resets: 2h15m` | `2h15m` |
| `tokens_in` | Input tokens | `in: 15.4k` | `15.4k` |
| `tokens_out` | Output tokens | `out: 2.1k` | `2.1k` |
| `tokens_cache` | Cache read tokens | `cache: 6.2M` | `6.2M` |
| `cost` | Session cost | `$5.21` | `$5.21` |
| `burn_rate` | Cost per hour | `($2.99/hr)` | Hidden |
| `email` | Account email | `user@email.com` | `user@email.com` |
| `cc_status` | Claude Code service status | `on` / `degraded` | Same |
| `version` | Claude Code version | `v2.0.37` | Same |
| `lines` | Lines added/removed | `+2109 -103` | `+2109/-103` |
| `session_time` | Session elapsed time | `37m` | `37m` |
| `cwd` | Working directory | Full path | Basename only |

## Usage for GPT and Muse models

When Claude Code runs a GPT or Muse model, through a model router for example, `usage`, `weekly` and `reset` show that plan instead of Claude's. The statusline reads the provider's login without ever refreshing it:

| Models | Plan | Login read |
|--------|------|------------|
| `claude-*` | Claude | stdin `rate_limits`, then Claude Code's own login |
| `gpt-*`, `o*`, `codex-*` | ChatGPT | `$CODEX_HOME/auth.json`, default `~/.codex/auth.json` |
| `muse-*` | Muse Code | `$MUSE_AUTH_PATH`, default `${XDG_CONFIG_HOME:-~/.config}/muse/auth.json` |

A router that keeps its own logins points the statusline at them. Glob patterns are allowed; the first match is used:

```bash
export STATUSLINE_OPENAI_AUTH="$HOME/.local/state/my-router/chatgpt/auth.json"
export STATUSLINE_MUSE_AUTH="$HOME/.local/state/my-router/muse/auth/meta-*.json"
```

The statusline inherits Claude Code's environment, proxy included. A router that intercepts Claude Code's traffic would break the statusline's own requests, so it sends them direct instead. `STATUSLINE_HTTPS_PROXY` sets the statusline's proxy, and set but empty means direct:

```bash
export STATUSLINE_HTTPS_PROXY=""
```

A window the plan does not have is hidden: a ChatGPT plan with only a weekly limit shows one figure. Other models show `--`.

A router that judges each plan's prompt cache from the turns it routes can name its file in `STATUSLINE_ROUTER_HEALTH`, a JSON object with `{"cache": {"<plan>": {"cache": "ok" | "missing"}}}`. While a plan's cache is `missing`, the line ends in a red `⚠ <plan> cache missing`, whatever the `components`: those turns re-read the whole conversation and use the plan faster. `router_health=off` in `statusline.conf` hides it.

## Available bar styles

| Style | Appearance (42% fill) |
|-------|----------------------|
| `text` | `session: 42% used` |
| `block` | `[████████............] 42%` |
| `smooth` | Sub-character precision with Unicode blocks |
| `gradient` | Transition zone with `▓▒░` |
| `thin` | `━━━━━━━━╌╌╌╌╌╌╌╌╌╌╌╌ 42%` |
| `spark` | 5-character sparkline |

## Available themes

| Theme | OK | Caution | Warning | Critical |
|-------|----|---------|---------|---------|
| `dark` | Blue | Yellow | Orange | Red |
| `light` | Blue | Yellow | Orange | Red |
| `colorblind` | Bold blue | Bold yellow | Bold cyan | Bold magenta |
| `none` | No colors | No colors | No colors | No colors |

## Verify the statusline

Start a new Claude Code session. The statusline appears at the bottom of the terminal:

```
opus-4.5 | 21%/15% | 2h15m | 15.4k/2.1k/6.2M | $5.21 | user@email.com
```

If the statusline does not appear, verify:

```bash
# Check settings.json has the statusLine entry
cat ~/.claude/settings.json | jq '.statusLine'

# Check the script is executable
ls -la ~/.claude/scripts/statusline.sh

# Check ccusage is installed
ccusage --version
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Statusline not visible | Missing `statusLine` in settings.json | Re-run `./setup.sh` or add manually |
| Shows `--` for usage | No reading yet, or no login for the model's plan | Check the login in [Usage for GPT and Muse models](#usage-for-gpt-and-muse-models); `STATUSLINE_DEBUG=1` shows the source tried |
| Shows `--` for cost | No active billing block | Start a new conversation to begin a billing block |
| No colors | `NO_COLOR` env var is set | Unset it: `unset NO_COLOR` |
| Usage stops moving in a quiet session | No `refreshInterval` in the `statusLine` settings: Claude Code redraws only on events | Re-run `./setup.sh`, which sets 60 seconds, or add `"refreshInterval": 60` |
| Stale usage data (prefixed with `~`) | The last reading is old: the API failed or throttled, or Muse reports no windows while its 5-hour one is idle | Normal; it refreshes once the API answers or the plan is used again |
| Config changes not taking effect | Old session running | Start a new Claude Code session |

## See also

- [Configuration](configuration.md): full reference for all 12 statusline.conf keys
- [Architecture](architecture.md): how the usage data pipeline works
- [Project Structure](project-structure.md): statusline module file listing
