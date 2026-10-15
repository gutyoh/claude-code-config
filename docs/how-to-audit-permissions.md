# How to Audit Permission Rules

Find and remove allow rules that permit more than they appear to, with
`claude-permissions-audit` (in `bin/`, on your PATH after `setup.sh`).

## Why

Every "Yes, and don't ask again" answer saves the exact command as an allow rule in that repository's git-ignored `.claude/settings.local.json` ([Configure permissions](https://code.claude.com/docs/en/permissions)). Over time those files collect rules that allow more than they appear to:

- **Mid-command wildcards** such as `Bash(git * main)`. A `*` matches any text, including options inserted at that position, so this rule also allows `git -c core.fsmonitor=<script> diff main`. Since v2.1.246 Claude Code prints a startup warning for each one ("has a wildcard before the rest of the command"); a trailing `*` or `:*` is fine.
- **Embedded credentials.** A command approved with `PGPASSWORD=…`, `curl -u user:pass` or an `Authorization` header is saved verbatim, in plaintext.
- **Overly broad allows** such as `Bash`, `Bash(sudo *)` or `Bash(python3:*)`.
- **Exact duplicates.**

This matters even if you usually run with `--dangerously-skip-permissions`. Allow rules have no effect in `bypassPermissions` mode, but the files are still loaded at startup, which is where the warning comes from, and the credentials stay on disk. In auto mode, an action that matches an allow rule skips the classifier. Auto mode drops broad interpreter rules when it starts ([permission modes](https://code.claude.com/docs/en/permission-modes)), but it keeps mid-command wildcards.

## Run the audit

```bash
claude-permissions-audit                  # ~/.claude/settings.json + every project under $HOME
claude-permissions-audit ~/code ~/work    # narrower and faster: specific roots (or CLAUDE_PERMS_ROOTS=dir1:dir2)
claude-permissions-audit --verbose        # list each finding; secrets are always masked
claude-permissions-audit --json           # machine-readable
claude-permissions-audit --dry-run        # show what --fix would remove
claude-permissions-audit --fix            # back up, then remove
claude-permissions-audit --fix --include-tracked   # also rewrite settings files git tracks
```

## What `--fix` changes

`--fix` removes mid-wildcard, secret-like and duplicate rules and leaves every other key untouched. Broad rules are reported but never removed, because removing one changes how you work. Before rewriting a file, `--fix` copies it to `~/.claude/backups/permissions/<UTC-timestamp>/` (directory mode `700`, file mode `600`). A settings file that git tracks is left unchanged and reported, because rewriting it would leave a diff in that repository; `--include-tracked` rewrites it too. Removing a rule does not revoke the credential it contained.

## Limits

Secret detection is a heuristic. It flags literal values after password, token and key names, URL userinfo, `curl -u`, auth headers, `mysql -p…`, and common token prefixes. Values written as `$VAR` or `$(…)` are not flagged. The scan skips `node_modules`, `.git`, `.worktrees`, virtualenvs and caches. When `$HOME` is the root, it also skips `~/Library` and the dot-directories directly under `$HOME`. It does not read managed settings. Exit codes: `0` clean, `1` findings (after `--fix`, broad rules remain), `2` usage or I/O error. Requires `jq`; on Windows it runs under Git Bash.

## See also

- [Configure permissions](https://code.claude.com/docs/en/permissions): how allow rules match
- [Permission modes](https://code.claude.com/docs/en/permission-modes): what each mode does with them
