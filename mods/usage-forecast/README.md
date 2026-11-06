# usage-forecast

A Claude Code mod that forecasts when the 5-hour and weekly plan limits run out.

- **Statusline**: writes `~/.claude/cache/usage-forecast.tsv`; `statusline.sh` shows
  `52%⇥1h12m/25% (160h39m)` when a window will run out before it resets, colored by
  the worse of its percentage and its forecast. Without the file the statusline falls
  back to the window's average pace.
- **Band above the prompt**: only when red: a window runs out within 30 min (5h) or 12 h (7d), or is spent.
- **`/usage-forecast`**: a pane charting both windows (used so far, projection after),
  and last window at the same point.

The 5-hour forecast takes the slower of the last 15 and 45 minutes, so a burst that
stopped does not warn; the weekly one takes the window's average, nights included.
Readings come from `session.measure` and are kept in `$.store`, shared by every
session on the machine.

## Load it

```bash
claude --plugin-dir <this repo>/mods/usage-forecast
```

or for every session, in `~/.claude/settings.json`:

```json
{ "env": { "CLAUDE_CODE_PLUGIN_DIRS": "<this repo>/mods/usage-forecast" } }
```

Needs Claude Code 2.1.287 or later. Tested on 2.1.319.

## Check it

```bash
claude plugin validate mods/usage-forecast
claude plugin test mods/usage-forecast
```
