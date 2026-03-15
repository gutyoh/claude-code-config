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
| `usage` | Session utilization | Progress bar | `21%` |
| `weekly` | Weekly utilization | `weekly: 63%` | `63%` |
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
| Shows `--` for usage | `ccusage` not installed | `npm install -g ccusage` |
| Shows `--` for cost | No active billing block | Start a new conversation to begin a billing block |
| No colors | `NO_COLOR` env var is set | Unset it: `unset NO_COLOR` |
| Stale usage data (prefixed with `~`) | Hook cache older than 5 minutes | Normal — data refreshes on next tool call |
| Config changes not taking effect | Old session running | Start a new Claude Code session |

## See also

- [Configuration](configuration.md): full reference for all 12 statusline.conf keys
- [Architecture](architecture.md): how the 3-tier usage data pipeline works
- [Project Structure](project-structure.md): statusline module file listing
