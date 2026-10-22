# How to Use Multiple Claude Accounts

Keep several Claude accounts signed in at once (for example, a work Team seat
and a personal Pro or Max plan) and pick one by email when you start Claude
Code. A session started as one account can be continued as another.

## How it works

Claude Code keeps one login per configuration directory, and its
[authentication docs](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts)
recommend one directory per account through `CLAUDE_CONFIG_DIR`. `claude-as`
builds on that:

- `~/.claude` stays the main home. Each extra account gets `~/.claude-<email>`.
- An extra home links back to `~/.claude` for what every account shares:
  settings, hooks, skills, agents, rules, plugins, statusline, plans, file
  history and the session history in `projects/`. That is why `--resume`
  and `--continue` find any session, whichever account started it.
- It keeps its own login, `.claude.json`, prompt history (`history.jsonl`; Claude Code refuses a linked one), the organization's
  managed settings, caches, and anything a later Claude Code release adds.
- Accounts are found, not configured: `claude-as` reads the email, plan and
  organization each home signed in with. Folder names do not matter.

## Add an account

```bash
claude-as --add you@example.com
```

This creates the home and opens Claude Code's own sign-in for that email. On a
machine without a browser, open the printed link elsewhere and paste the code
back. Use a private browser window when the browser is signed in to another
Claude account. Arguments after the email go to `claude auth login`, for
example `--sso` for an Enterprise login.

Each account signs in once per machine. Never copy a credentials file between
machines: Claude Code rotates the token, so both copies stop working.

## Use an account

```bash
claude-as                              # list accounts: email, plan, organization, home
claude-as you@example.com              # start Claude Code as that account
claude-as you@example.com --continue   # claude's own arguments follow the email
claude-as you@example.com -a           # bypass permissions on from the start
CLAUDE_AS=you@example.com claude-as -p "hi"   # a default, per shell or per folder
```

An account starts as plain `claude` does with the shell function `setup.sh`
installs: bypass permissions is one of the modes `Shift+Tab` cycles through,
and `-a`, `--unsafe`, `--bypass` or `-adskp` right after the email starts in it.

An account is named by its whole email, in any case. Part of an email runs
nothing and lists the emails it is part of: a part that names one account today
would name another once a similar one is added, and a script would then run
the wrong account or none, so only whole names are accepted.

When one email belongs to two organizations, such as a personal plan and a team,
add one of them whole: the plan (`claude-as you@example.com/team`, or
`/team/max_5x`), the organization's name, or its id, which never changes.
Ambiguous names list every match and run nothing. `--add` prints the shortest
name that is whole. A home's path names it directly: `claude-as ~/.claude-work`.
One account signed in to two homes runs from `~/.claude`, or else the first.

Plain `claude` keeps using `~/.claude`.

## Resume a session as its account

Each session is recorded with the account it last ran as
([`session-account.sh`](hooks.md#session-accounts)), so a resume keeps it:

```bash
claude-as -r <session id>          # as the account it last ran as
claude-as -c                       # this folder's newest session, the same way
claude --resume <session id>       # the same, through the claude shell function
```

A session name made by [`session-name.sh`](hooks.md#session-names) works in
place of the id. herdr resumes its panes after a restart with
`claude --resume <id>`, so they come back as their own accounts too. Sessions
from before the record are found from each account's prompt history. The
`claude` functions for bash, zsh, POSIX shells, fish and PowerShell all do this.
`--continue` takes the folder's newest session, as Claude Code does. Set
`CLAUDE_CONFIG_DIR` to choose the home yourself. When `claude-as --where`
fails, the function says so and runs as `~/.claude`.

A `claude.fish` you wrote yourself is left alone by `setup.sh`, which then
prints the two lines that route a resume. Add them at the top of the
function, outside any `if` or `switch`:

```fish
set -l home (__claude_as_home $argv)
test -n "$home"; and set -lx CLAUDE_CONFIG_DIR $home
```

`setup.sh` installs `__claude_as_home` beside it, in
`$XDG_CONFIG_HOME/fish/functions/`.

Remote Control's list belongs to each account, so a session resumed as
another account is registered there anew. The resume passes the session's
own name with `--remote-control`, which keeps the phone showing the name the
session has everywhere else ([Session names](configuration.md#session-names)).

## Continue a session as another account

When one account reaches its usage limit:

```bash
/exit
claude-as other@example.com --continue
claude-as other@example.com -r <session id>
```

Naming another account than a session last ran as asks first, on a terminal:

```text
claude-as: session <id> last ran as you@work.example
Continue it as other@example.com? [y/N]
```

Two emails that start alike are easy to mix up, and a shell's suggestion from
history fills in the last one typed. Resumed inside Claude Code with `/resume`,
the session shows the same warning once it starts.

Accounts on Free, Pro and Max plans fall under Anthropic's consumer terms; Team
and Enterprise fall under the commercial terms. Continuing a work session as a
personal account sends that work to the personal account. Check its
[privacy settings](https://claude.ai/settings/data-privacy-controls) first.

Do not open the same session in two accounts at the same time: both would write
to one transcript.

## Move every session in herdr to one account

When sessions run in [herdr](https://herdr.dev) panes, `--move` does the
`/exit` and resume above in each pane on this machine:

```bash
claude-as --move other@example.com --dry-run   # what would move, and what it would end
claude-as --move other@example.com             # move them
claude-as --move other@example.com --pane w1:p3 --force
```

- Each session resumes in its own pane, from the folder it was launched in,
  under its own Remote Control name, and in the permission mode it is in now
  (`Shift+Tab` changes it after launch), with the `--model`, `--fallback-model`
  and `--add-dir` it was started with. `--settings` and `--mcp-config` stay
  behind: a wrapper that adds them per account adds the new account's again.
  One already on that account stays.
- The session is the one Claude Code itself records for the pane's process.
  When herdr names another, as after a `claude -p` run from that pane, when
  there is no such record, or when the session has no transcript to resume,
  it is left alone.
- It waits for an agent to go idle, at most `--wait` seconds (default 600), and
  leaves a busy one alone.
- A session whose Bash tool still runs background jobs, such as a dev server,
  is left alone and its jobs listed: they end when the session exits. Stop
  them, or move it anyway with `--pane <id> --force`. So is one whose claude
  process herdr cannot show, since its jobs cannot be checked.
- The pane is resumed by this `claude-as` itself, by its full path, so an older
  copy on `PATH` never answers. Each run writes a session's resume command to
  `~/.local/state/claude-as/move-<time>-<pid>.resume` before `/exit` and
  drops it once the session runs again. A session the run leaves exited is
  listed at the end with its command: run that in its pane.
- Run from inside a herdr pane, the whole run goes on in the background and
  that pane's session moves last, once its agent finishes the turn. It prints
  where its log is and the `kill` that stops it.
- `Ctrl+C`, or `kill` for a background run, stops after the session in
  flight: a session already sent `/exit` is resumed first.
- The question above is answered for each session `--move` restarts, and for
  no other.

On another machine, run it there: `ssh <host> claude-as --move other@example.com`.

## Check every account

```bash
claude-as --check    # signed in, links in place, sees the shared history
claude-as --relink   # link what a home is missing; anything else is left alone
```

`--check` makes no model request. It writes a small canary session to the
shared history and asks each home to find it, so a Claude Code release that
stops reading linked history shows up as a failure. The probes run outside the
herdr pane `--check` runs in, so the pane keeps its own session.

## Notes

- Remote Control, claude.ai connectors and usage limits belong to each account.
  On your phone, switch the Claude app to the account whose sessions you want.
- `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`,
  `ANTHROPIC_PROFILE` and the cloud provider switches outrank every login.
  `claude-as` warns when one is set.
- On a machine whose managed settings set `forceLoginOrgUUID`, homes of other
  organizations refuse to start. `--check` notes such a policy.
- On macOS the login is in the Keychain, one entry per home. The statusline
  reads the entry of the home in use.
- Settings are shared, so changing the model in one account changes it in all.
