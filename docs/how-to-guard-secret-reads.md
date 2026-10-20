# How to Guard Secret Reads

Keep Claude's file tools away from credential files with `claude-secret-guard`
(in `bin/`, on your PATH after `setup.sh`). It is off by default.

## Why

An agent that reads a web page, an issue or a README can be told by text hidden
there to open a key file and paste it somewhere. A `Read` deny rule makes that
fail at the first step. The guard holds one fixed list of such rules, so every
machine can switch them on or off the same way.

## Turn it on or off

```bash
claude-secret-guard            # on, off, or partial (n/13)
claude-secret-guard on         # back up settings.json, add the missing rules
claude-secret-guard off        # back up settings.json, remove exactly these rules
claude-secret-guard list       # the rules
```

It edits `${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json` and nothing else.
`on` adds only the rules that are missing, and `off` removes only these rules,
so your own allow and deny rules, `defaultMode` and every other key stay as
they were. When `off` leaves an empty `permissions` block, it removes it, so
`on` then `off` returns the file to what it was, except that a `permissions`
block that was already empty is gone too. Without a settings file, `off` and
`status` write nothing. Before each change it
copies the file to `~/.claude/backups/permissions/<UTC-time>/` (mode `600`). A
symlinked `settings.json` is updated at its target. Start a new session for the
change to apply.

Each Claude home has its own settings, so run it once per home you use, for
example `CLAUDE_CONFIG_DIR=~/.claude-personal claude-secret-guard on`. `status`
in one home says nothing about another. `setup.sh --overwrite-settings`
replaces `settings.json` with the repository's defaults, which drops the rules;
run `claude-secret-guard on` again afterwards.

## What the rules cover

The rules name private keys under `~/.ssh` (`id_*`, `*.pem*` and a few known
names), `~/.oci`, `~/.azure`, `~/.doppler`, the fnox age key, Docker's and
`gh`'s credential files, `~/.claude/mcp-keys.env` and the Bitwarden SSH agent
socket. Paths that don't exist on a machine are harmless.

Measured on Claude Code v2.1.304, with canary files:

| Blocked | Still works |
|---|---|
| Read, Write and Edit on those paths | `ssh -i ~/.ssh/<key>`, `rsync -e 'ssh -i …'` |
| A symlink pointing at them, a path through `..`, upper-case letters on macOS | `gh`, `git`, `docker`, `az`, `fnox` |
| Bash commands that name the path: `cat`, `grep -r`, `rg`, `ls`, `cp` | Reading `~/.ssh/config`, `known_hosts`, `*.pub` other than `id_*.pub` |
| A subagent started with the Task tool | Every file outside the list |

## Limits

- The rules don't stop a program that opens the file itself, such as
  `python3 -c "open(...)"`, or a command whose path is built at run time, such
  as `cat $(echo ~/.oc)i/key`. The [official permissions
  docs](https://code.claude.com/docs/en/permissions) say the same. For
  operating-system enforcement, see [sandboxing](https://code.claude.com/docs/en/sandboxing);
  it also limits network access and writes outside the working directory.
- `Read(~/.ssh/id_*)` also covers `id_*.pub`. `ssh-keygen -lf` still reads
  them.
- Exit codes: `0` done, `2` usage error or a settings file that isn't a JSON
  object (nothing is written). Requires `jq`; on Windows it runs under Git Bash.

## See also

- [How to audit permission rules](how-to-audit-permissions.md): risky allow rules
- [Configure permissions](https://code.claude.com/docs/en/permissions): how deny rules match
