# How to Sync Across Machines

The configuration is a Git repository: every machine clones it, and `setup.sh`
links it into `~/.claude`. Sessions themselves do not sync; Remote Control
reaches a running session from another device instead.

## Set up the first machine

1. Fork this repository, so your changes have somewhere to go.
2. Clone your fork and install it as in [Getting started](getting-started.md).
3. Change agents, skills and hooks as you like, then commit and push.

## Add another machine

```bash
git clone https://github.com/<you>/claude-code-config.git
cd claude-code-config
./setup.sh          # macOS, Linux, WSL
.\setup.ps1         # Windows
```

API keys stay on each machine: add them to that machine's
`~/.claude/mcp-keys.env` ([Getting started, step 3](getting-started.md#step-3-set-your-api-keys)).

## Pull updates

```bash
git -C <clone> pull
<clone>/setup.sh --yes      # or .\setup.ps1
```

Changes to files the repository already had reach every session at once,
since `~/.claude` links to them. Run setup again after a pull that adds or
removes an agent, skill, hook or script: it links the new entries and prunes
the links of removed ones. On Windows without Developer Mode, files are copies
rather than links, so run `setup.ps1` after every pull.

## Reach a session from another device

Use Claude Code's native [Remote Control](https://code.claude.com/docs/en/remote-control) instead of synchronizing the live `~/.claude/` data directory. Remote Control keeps the session and tools on the originating machine while Claude's web and mobile clients provide a synchronized interface over TLS.

```bash
# Start one local session that can also be controlled from web or mobile
claude --remote-control "My Project"

# Or enable an existing interactive session
/remote-control My Project

# Scalable server mode: isolate concurrent sessions in Git worktrees
claude remote-control --spawn worktree --capacity 8
```

Claude Code 2.1.51 or later is required. Pro, Max, Team, and Enterprise plans are supported; a Team or Enterprise Owner must enable Remote Control in Claude Code admin settings. See the official documentation for authentication and policy requirements.

Use the direct `claude` launcher for Remote Control, not the `clp` model-proxy shortcut. Remote Control requires a claude.ai subscription login and the official Anthropic API endpoint; API-key, Bedrock, Vertex, Foundry, and custom `ANTHROPIC_BASE_URL` sessions are not supported.

### Why automatic file sync is retired

This repository deliberately does **not** install SessionStart/SessionEnd hooks that pull or push `~/.claude/`:

- `history.jsonl` and `projects/**/*.jsonl` are live, append-oriented journals, not merge-safe configuration files.
- Simultaneous or interrupted writers can create repeated `.conflict.*` snapshots, overwrite a fuller transcript with a shorter copy, or lose prompt history through last-writer-wins behavior. These are known upstream failure modes: [false prefix conflicts](https://github.com/tawanorg/claude-sync/issues/69), [truncated transcript overwrite](https://github.com/tawanorg/claude-sync/issues/70), and [history loss](https://github.com/tawanorg/claude-sync/issues/72).
- Hook-triggered background transfers have no safe transaction boundary with Claude Code processes that are actively mutating the same files.

Git remains the source of truth for declarative configuration in this repository: hooks, skills, agents, scripts, and documented settings. Runtime histories stay local. Re-running `./setup.sh` removes legacy `cc-sync-pull.sh` and `cc-sync-push.sh` entries from `~/.claude/settings.json` while preserving unrelated hooks.

The historical `--no-claude-sync` option is accepted as a compatibility no-op. `--with-claude-sync` now exits with migration guidance rather than reinstalling unsafe automatic hooks. This migration does not delete existing conflicts, backups, cloud data, or credentials.

## Sharing `~/.claude` with other installers

`~/.claude` is not ours alone. Other tools install into it — a remote-session
manager may add `skills/`, a terminal integration may add a `hooks/` script and
register it in `settings.json`. So `setup.sh` installs **one symlink per repo
entry**, never one symlink for a whole directory:

```
~/.claude/hooks/refresh-usage-cache.sh -> <repo>/.claude/hooks/refresh-usage-cache.sh
~/.claude/hooks/their-hook.sh              (real file, untouched)
```

Entries this repo does not ship are left exactly as they are. An entry that
collides with one of ours is moved aside to a timestamped `.bak.<date>` and
never deleted. Removing an entry from the repo prunes its link on the next run;
foreign entries are never pruned.

**Why not one symlink for the directory.** It hides every foreign entry at once,
and it welds live Claude behaviour to a git working tree: once `~/.claude/hooks`
*is* the repo directory, another installer's file lands inside the checkout as
an untracked file, and the next `git switch` deletes it — the hook silently
stops running, with only a `SessionStart hook error` to show for it.

`setup.sh` migrates that older layout automatically: the directory symlink
becomes a real directory of per-entry links, and any untracked file found inside
the repo's `.claude/` tree is moved back out to `~/.claude/` where it belongs.

**Running under a remote session manager.** If one is launching Claude for you,
it owns its own flags and lifecycle hooks — this repo does not try to reproduce
them. Install the repo for its agents, skills, hooks, MCP registration, status
line, and shell tooling; let the session manager keep its own settings entries
and its own permission mode. Both survive `setup.sh`.

## See also

- [How to use multiple accounts](how-to-use-multiple-accounts.md): several Claude accounts on one machine
- [Architecture](architecture.md#the-setup-system): how setup links the repository
