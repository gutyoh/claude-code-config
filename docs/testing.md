# Testing and Portability

> **Platform scope.** Both installers are gated in CI. `setup.sh` runs on macOS and Linux;
> `setup.ps1` runs its analyzer and tests under Windows PowerShell 5.1 and PowerShell 7 on
> Windows x64 and arm64, macOS and Linux, and a test fails if the two accept different options.
> fish support and login-shell detection are Unix-only by nature. The hooks and the statusline
> are bash scripts, so on Windows they need [Git for Windows](https://gitforwindows.org/).

This repo installs onto other people's machines, so nothing shipped may depend on one developer's paths, shell, package manager, or OS version. Two things enforce that: a cross-platform CI matrix, and a set of static portability guards in the test suite.

## Test lanes

| Command | What it runs | Typical time |
|---|---|---|
| `just unit` | Fast, hermetic — stubbed boundaries, no network | ~20s |
| `just integration` | Drives real scripts end to end, still offline | ~35s |
| `just smoke` | Runs `setup.sh` itself against a throwaway `HOME` | ~5s |
| `just test` | Every bats lane | ~45s |
| `just secrets` | betterleaks over the tree and every commit on every ref | ~60s |
| `just ps-check` | PSScriptAnalyzer + Pester for `setup.ps1` (skips without `pwsh`) | ~30s |
| `just check` | The merge gate: `lint` + `lint-workflows` + `format-check` + `secrets` + `test` + `ps-check` | ~3m |
| `just verify-clean-machine` | The whole suite as CI sees it | ~60s |

**Run `just verify-clean-machine` before pushing.** A developer machine lies in
two ways CI does not: `~/.claude` is already installed, so tests that read it
pass for the wrong reason; and Homebrew bash sits ahead of `/bin/bash` on
`PATH`, so `env bash` finds 5.x while the macOS runner finds 3.2.57. That
target removes both — empty `HOME`, system bash first — and is the difference
between catching a portability break locally and finding it in CI.

Lanes are bats tag filters (`--filter-tags`), so a test belongs to a lane by its `# bats test_tags=` or file-level `# bats file_tags=` directive.

Tests run in parallel via `bats --jobs` when GNU parallel is installed (`just install-tools` gets it). Without it the suite still runs, just serially — the justfile probes and degrades rather than failing.

## Hermetic by default

`tests/helpers.bash` provides the harness:

- `isolate_home` — points `HOME` and the `XDG_*` variables at the per-test tmpdir. Without it a test reads the developer's real `~/.claude`, so results depend on personal state and anything that scans it pays for gigabytes of real session history.
- `stub_bin <name> [body]` — puts a fake executable ahead of the real one on `PATH`.
- `stub_slow_bin <name> <seconds>` — a stub that hangs, for exercising timeout paths.
- `require_cmd <cmd>` — skip when a prerequisite is missing.

Call `isolate_home` first in `setup()`. A test that shells out to a real binary should stub it unless the point of the test is that binary.

## Portability guards

`tests/portability.bats` fails the build on machine-specific assumptions:

- hardcoded `/Users/...` or `/home/...` paths
- a brew prefix named without its alternatives (`/opt/homebrew` is Apple-Silicon-only)
- `$HOME/.config` written without an `XDG_CONFIG_HOME` fallback
- `[^\n]` inside a `sed` expression — BSD sed reads it as "not backslash and not the letter n", GNU sed as "not newline", so it silently behaves differently per platform
- GNU-only flags (`stat -c`, `date -d`) with neither a platform branch nor a BSD fallback
- shebangs that hardcode an interpreter path instead of using `env`
- an active absolute `command =` in a shipped Ghostty preset
- `stat -f … || stat -c …`, which reads as a BSD-then-GNU fallback but is not: on GNU coreutils `-f` means `--file-system`, so the first call *succeeds* and the `||` never fires
- `date -r <epoch>`, which formats that epoch on BSD but reads a *file's* mtime on GNU
- a personal directory convention (`~/Documents/dev`, `~/src`) used as a default rather than inside a probe list
- `PLATFORM` pinned to a literal in a test, which forces the wrong `stat`/`date` branch on every other OS
- a GitHub Action referenced by tag instead of a full commit SHA
- a shipped script that runs embedded Python without UTF-8 mode, which before Python 3.15 reads and prints in the system code page (cp1252 under Git Bash)
- a bats test name outside ASCII, which bats on Windows cannot find again to run

## Which shell gets configured

`setup.sh` installs the `claude` / `clp` shortcuts into the rc file your login shell actually reads. Getting that wrong fails silently — the install reports success and you never get a `claude` function — so the detection is deliberate.

**It does not use `$SHELL`.** That variable is inherited from whatever spawned the process and no shell corrects it on startup:

```bash
$ SHELL=/bin/made-up fish -c 'echo $SHELL'
/bin/made-up
```

A fish user whose terminal was launched with `SHELL=zsh` would get the block written to `~/.zshrc`, which fish never reads. The password database is authoritative, so `detect_login_shell` consults it in this order:

| Order | Source | Why |
|---|---|---|
| 1 | `CLAUDE_CONFIG_SHELL` / `--shell` | Explicit override |
| 2 | `dscl` | macOS uses OpenDirectory; `/etc/passwd` can be stale |
| 3 | `getent passwd` | NSS-aware, so it works with LDAP/AD |
| 4 | `/etc/passwd` | Flat-file fallback |
| 5 | `$SHELL` | Last resort only |

The resolved shell is printed during install. Override it when detection is wrong or you want to target a different shell:

```bash
./setup.sh --shell "$(command -v fish)"
```

**Where each shell gets its config:**

| Login shell | Destination |
|---|---|
| fish | `$XDG_CONFIG_HOME/fish/functions/{claude,clp,__claude_as_home,__claude_launch_mode}.fish` + `conf.d/` for PATH |
| zsh | `~/.zshrc` |
| bash | `~/.bashrc`, plus a bridge in `~/.bash_profile` |
| anything else | `~/.profile` |

The bash bridge matters: bash reads `~/.bashrc` for non-login interactive shells and `~/.bash_profile` for login shells. Linux terminals open the former, **macOS Terminal.app and iTerm2 open the latter** — so a block written only to `~/.bashrc` never loads on macOS. `setup.sh` appends the conventional `[ -f ~/.bashrc ] && . ~/.bashrc` line, once, and skips it if your `~/.bash_profile` already sources `~/.bashrc`.

fish gets native files rather than a profile because fish is not POSIX — `export VAR=x` and POSIX function syntax are both syntax errors there. The snippet written for every other shell is checked with `shellcheck -s sh` and executed under each installed POSIX shell in CI.

## bash version

macOS ships bash 3.2.57 as `/bin/bash` and cannot ship newer for licensing reasons, so `#!/usr/bin/env bash` lands on 3.2 whenever no newer bash is ahead of it on `PATH` — the default state on a clean Mac, and what GitHub's macOS runners provide.

Everything here therefore targets **bash 3.2**. That rules out namerefs (`local -n`, 4.3), associative arrays (`declare -A`, 4.0), `mapfile`/`readarray`, and `${var,,}` case conversion. Assign by name with `printf -v` (3.1+) or `eval` instead:

```bash
# 4.3+ only — fails at runtime on macOS, and `bash -n` will not catch it
local -n out="$1"; out="value"

# works everywhere
local out_name="$1"; printf -v "$out_name" '%s' "value"
```

Two guards enforce this, and `just verify-clean-machine` exercises `setup.sh` under the system bash directly.

## CI

`.github/workflows/ci.yml` runs these jobs:

| Job | Runners | Runs |
|-----|---------|------|
| `lint + format` | Ubuntu arm64 | `just lint`, `just format-check`, `just lint-workflows` |
| `secret scan` | Ubuntu arm64 | `just secrets` |
| `tests` | Ubuntu arm64, macOS | The unit, integration and smoke lanes |
| `powershell` | Windows x64 and arm64, macOS, Linux | PSScriptAnalyzer and Pester, under PowerShell 7 and Windows PowerShell 5.1 |
| `git bash` | Windows x64 and arm64 | The status line tests under Git for Windows' bash, which Claude Code uses there |
| `ci-status` | Ubuntu arm64 | Passes only when every other job passed or was skipped; the one check to require |

A pull request runs only the lanes its files can affect, decided by
`.github/scripts/ci-lanes.sh`: macOS when shell code changes, the Windows lanes
when PowerShell or the status line changes. Pushes to `main` run every lane.
`fail-fast: false` keeps a macOS- or Windows-only failure from being hidden by
the Linux result.

Every action is pinned to a full commit SHA. A tag is mutable: when `tj-actions/changed-files` was compromised in 2025, the attacker moved 350+ tags to a malicious commit and every repository pinned by tag executed it with access to the runner.

Tests that shell out over the network (`npx -y …`) probe once per suite and **skip** when the registry is unreachable, rather than failing. A flaky gate is worse than no gate — people learn to re-run it instead of reading it.
