# Hooks

Every hook this configuration ships: when it runs, what it does, and how to
change it. The scripts live in `.claude/hooks/` and are linked into
`~/.claude/hooks/`. Where each one is registered decides where it runs:

- **User**: `setup.sh` and `setup.ps1` add it to your user `settings.json`, so
  it runs in every project.
- **Repo**: this repository's `.claude/settings.json` registers it, so it runs
  in this checkout; `./setup.sh --overwrite-settings` makes these your user
  defaults as well.
- **Plugin** and **agent**: see the hook's section.

| Hook | Event (matcher) | Registered | What it does |
|------|-----------------|------------|--------------|
| [`enforce-git-pull-rebase.sh`](#git-pull-rebase) | `PreToolUse` (`Bash`) | Repo | Adds `--rebase` to `git pull` |
| [`open-file-in-ide.sh`](#ide-diagnostics) | `PreToolUse` (`mcp__ide__getDiagnostics`) | User | Opens the file in your IDE before diagnostics |
| [`refresh-usage-cache.sh`](#usage-cache) | `PreToolUse` (`.*`), `Stop` | Repo | Keeps the status line's usage reading fresh |
| [`guard-mcp-key.sh`](#mcp-key-guard) | `PreToolUse` (`mcp__(tavily\|brave-search)__.*`) | Repo | Blocks a search call whose API key is missing |
| [`rate-limit-brave-search.sh`](#brave-search-rate-limit) | `PreToolUse` (`mcp__brave-search__.*`) | Repo | Spaces Brave Search calls to the plan's rate |
| [`auto-rotate-mcp-key.sh`](#mcp-key-rotation) | `PostToolUse` (`mcp__(tavily\|brave-search)__.*`) | Repo | Moves to the next key when one runs out of quota |
| [`guard-public-text.sh`](#public-text-guard) | `PreToolUse` (`Bash`) | User | Blocks text bound for a public repository that your scanner flags |
| [`session-name.sh`](#session-names) | `SessionStart` (`startup`), `UserPromptSubmit` | User | Names each session once, at its first prompt |
| [`stop-nudge.sh`](#stop-nudge) | `Stop` | Plugin | Nudges a routed model that announces a step and stops |
| [`sql-guardrail.sh`](#database-guardrail) | `PreToolUse` (`Bash`) | Agent | Blocks destructive database commands |

Hooks read the event as JSON on stdin and need `jq`. On Windows they run under
[Git for Windows](https://gitforwindows.org/)' bash.

## Git pull rebase

Adds `--rebase` to every `git pull` Claude runs, for a linear history:

```bash
git pull origin main            # what Claude asked for
git pull --rebase origin main   # what runs
```

## Public text guard

GitHub keeps every revision of a pull request or issue description and has no
API to delete one, so private text has to be stopped before it is published.
Before a Bash command publishes to a **public** GitHub repository, this hook
hands what it would publish to your scanner and blocks the call when the
scanner exits non-zero:

| Command | What is checked |
|---------|-----------------|
| `gh pr`/`gh issue` `create`, `edit`, `comment`, `review`; `gh release create`/`edit`; `gh gist create` | The command's text, and every `--body-file`/`-F` file |
| `gh api` | The command's text, `--input` files, and `-F field=@file` files |
| `git commit` | The message, inline or from `-F`/`--file` |
| `git push` | The message of every commit the remotes do not have yet |

The scanner is yours, so the list of what is private never enters a public
repository. `CLAUDE_LEAK_GUARD` holds its command; the hook appends the file
paths, and `~/` at the start of a word is expanded. For example, a fleet tool
whose needles come from a private repository:

```json
{ "env": { "CLAUDE_LEAK_GUARD": "workstation --fleet ~/fleet leak-guard" } }
```

- **Opt-in:** with `CLAUDE_LEAK_GUARD` unset the hook does nothing.
- **Public only:** the repository comes from `-R`/`--repo`, a leading
  `cd <dir> &&`, `git -C <dir>`, or the working directory's `origin`. `gh repo
  view` gives its visibility, cached for a day. Private and internal
  repositories, and remotes outside GitHub, pass unchecked; an unknown
  visibility is checked as public.
- **Fails closed:** a scanner that cannot run, or a body file the hook cannot
  read, blocks the call. A body file named through a variable (`--body-file
  "$F"`) is refused: write the literal path.
- Local paths in the command, the files it reads and the `cd`/`-C`
  directory, are not part of what gets published and are left out of the scan.

## IDE diagnostics

Opens the file in your IDE before Claude calls `mcp__ide__getDiagnostics`.
JetBrains IDEs time out on diagnostics for a file that is not the active tab
([anthropics/claude-code#3085](https://github.com/anthropics/claude-code/issues/3085)).
Every agent that reads diagnostics benefits, `sonarqube-fixer` most.

The IDE is chosen in this order:

1. `CLAUDE_IDE`, when set: `export CLAUDE_IDE="cursor"`.
2. The IDE that is running, found with `pgrep`.
3. The first installed command, in the order `code-insiders`, `cursor`,
   `windsurf`, `code`, `pycharm`, `idea`.

Supported commands: `code`, `code-insiders`, `cursor`, `windsurf`,
`antigravity`, `pycharm`, `idea`, `webstorm`, `phpstorm`, `goland`, `rider`,
`clion`, `rubymine`.

## Usage cache

Runs on every tool call and when a turn ends. When the cached usage reading is
older than `USAGE_CACHE_TTL` (60 seconds), it makes one small background request
and writes the plan's rate-limit headers from the response to
`~/.claude/cache/claude-usage.json`. The status line falls back to that file
when Claude Code has not passed a reading yet. A fresh cache exits at once.

## MCP key guard

Blocks a Brave Search or Tavily call when its API key is not configured, and
suggests `/web-search`, which needs no key. Without it the MCP server fails
with a less useful error.

## Brave Search rate limit

Serializes Brave Search calls and keeps them apart by at least
`BRAVE_API_RATE_LIMIT_MS` (default `1100`, the free plan's one request per
second with a margin; `50` suits paid plans). Without it parallel searches get
HTTP 429.

## MCP key rotation

After a Brave Search (HTTP 429) or Tavily (HTTP 432) call reports an exhausted
quota, runs `mcp-key-rotate <service>` to move to the next key in the pool and
tells you to restart the session, since the running MCP server keeps the old
key. It waits `AUTO_ROTATE_COOLDOWN_SEC` (default 300) before rotating again.
See [How to add an MCP server](how-to-add-mcp-server.md#set-up-key-rotation-optional).

## Session names

Names each interactive session once, at its first prompt, as
`<provider>-<start>-<topic>-<id>`, for example
`claude-20261012T1412Z-btree-page-splits-0ed0b890`, and never renames it: the
name is how `--resume` and other sessions find it. Details and switches in
[Configuration: session names](configuration.md#session-names).

## Stop nudge

Some models routed into Claude Code end a turn by announcing a step ("writing
the summary now") without calling a tool. For models matching
`STOP_NUDGE_MODELS` (default `muse-*`), this hook sends one nudge to take that
step, at most `STOP_NUDGE_MAX` (default 6) per session. Claude models are never
nudged. `STOP_NUDGE=off` disables it.

It ships as a plugin, `.claude/skills/config-hooks`, which Claude Code loads in
place from `~/.claude/skills/`; see
[Configuration: plugin hooks](configuration.md#plugin-hooks).

## Database guardrail

One hook for every database CLI, registered in the frontmatter of the
`databricks-expert`, `sql-expert` and `mongodb-expert` agents rather than in
`settings.json`, so it applies only while they run.

| Level | CLIs | Blocks | Allows |
|-------|------|--------|--------|
| **STRICT** | `databricks` | Every mutation: `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `MERGE`, `DROP`, `CREATE`, `ALTER`, `GRANT`, `REVOKE` | `SELECT`, `DESCRIBE`, `SHOW`, `EXPLAIN` |
| **STANDARD** | `psql`, `mysql`, `sqlcmd`, `sqlite3`, `duckdb`, `sqlplus`, `clickhouse-client` | `DROP DATABASE`, `TRUNCATE TABLE`, `DELETE` without `WHERE` | `INSERT`, `UPDATE`, `CREATE`, `DELETE` with `WHERE` |
| **MONGO** | `mongosh` | `db.dropDatabase()`, `collection.drop()`, `deleteMany({})` and `remove({})` with an empty filter | CRUD with filters, aggregation, indexes |

Matching is case-insensitive. A blocked command exits `2` and Claude sees why.
The hook fails open on empty input, a missing `jq` or invalid JSON, and never
blocks a command that is not a database CLI.

## See also

- [Configuration](configuration.md): the `settings.json` entries and every environment variable
- [Architecture](architecture.md#the-hook-system): how hooks fit with the rest of the setup
- [How to add an agent](how-to-add-agent.md#4-add-agent-scoped-hooks-optional): hooks that run only for one agent
