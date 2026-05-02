# Fish Shell Configuration Guide

Comprehensive reference for configuring the [Fish shell](https://fishshell.com/) on macOS as a daily driver. Mirrors the structure of `how-to-configure-ghostty.md`.

## Table of Contents

1. [Why Fish](#why-fish)
2. [Installation](#installation)
3. [Make Fish Your Default Shell](#make-fish-your-default-shell)
4. [Config Layout](#config-layout)
5. [PATH Management](#path-management)
6. [Environment Variables](#environment-variables)
7. [Abbreviations vs Aliases](#abbreviations-vs-aliases)
8. [Functions](#functions)
9. [Plugin Manager (Fisher)](#plugin-manager-fisher)
10. [Prompt (Tide)](#prompt-tide)
11. [Modern CLI Tool Integration](#modern-cli-tool-integration)
12. [Companion Tools](#companion-tools)
13. [Reverting to Zsh](#reverting-to-zsh)
14. [Ready-to-Use Configs](#ready-to-use-configs)
15. [Troubleshooting](#troubleshooting)
16. [Sources](#sources)

---

## Why Fish

Fish 4.x (released February 2025, fully Rust-rewritten) gives you:

- Sub-100ms startup
- Autosuggestions, syntax highlighting, smart completions out of the box (no plugins)
- Stable post-1.0 releases every ~2 months
- First-class Ghostty integration (prompt marking, click events, etc.)

Trade-off: **not POSIX-compliant**. Bash one-liners from Stack Overflow won't paste-and-run. Use `bash -c '...'` or shebang scripts when you need POSIX.

## Installation

```bash
brew install fish
```

Verify:

```bash
fish --version    # fish, version 4.6.0 or higher
which fish        # /opt/homebrew/bin/fish
```

## Make Fish Your Default Shell

```bash
# 1. Allow fish as a login shell
echo '/opt/homebrew/bin/fish' | sudo tee -a /etc/shells

# 2. Set it as your default
sudo dscl . -create /Users/$(whoami) UserShell /opt/homebrew/bin/fish

# 3. Verify
dscl . -read /Users/$(whoami) UserShell
# → UserShell: /opt/homebrew/bin/fish
```

Alternative (interactive `chsh`):

```bash
chsh -s /opt/homebrew/bin/fish
# (prompts for password)
```

> **Note**: This change is reversible — see [Reverting to Zsh](#reverting-to-zsh).

## Config Layout

Modern fish config uses **modular files**, not a monolithic `config.fish`:

```
~/.config/fish/
├── config.fish              minimal entrypoint
├── conf.d/                  auto-loaded in alphabetic/numeric order on shell start
│   ├── 00-paths.fish
│   ├── 10-env.fish
│   ├── 15-mise.fish
│   ├── 20-tools.fish
│   ├── 30-abbreviations.fish
│   └── 40-bun.fish
├── functions/               auto-loaded ON FIRST CALL (lazy, zero startup cost)
│   ├── claude.fish
│   └── clp.fish
└── completions/             tab-completion definitions per command
```

**Why modular?**

- Easier to add/remove features without touching one giant file
- Numeric prefixes give explicit load order
- `functions/` directory means functions cost nothing on startup — they only load when called

## PATH Management

Use `fish_add_path`, never `set -gx PATH` directly.

```fish
# Prepend (takes priority)
fish_add_path -gp $HOME/bin

# Append (lowest priority)
fish_add_path -ga /opt/homebrew/opt/postgresql@17/bin

# Idempotent — re-running doesn't duplicate entries
```

| Flag | Meaning |
|------|---------|
| `-g` | Global scope (lasts for this shell + children, NOT universal) |
| `-U` | Universal scope (persists across all fish shells, stored in `fish_variables`) |
| `-p` | Prepend |
| `-a` | Append |

**Why not `-U` for paths?** Universal vars are sticky — they survive even if you remove the line from config.fish, leading to confusing "PATH still contains X" issues. Use `-g` and treat config.fish as the source of truth.

## Environment Variables

```fish
set -gx GOPATH $HOME/go            # global, exported
set -gx JAVA_HOME (/usr/libexec/java_home 2>/dev/null)
```

`-x` exports to child processes (equivalent to `export` in bash).

## Abbreviations vs Aliases

Prefer **abbreviations** in 2026.

```fish
abbr -a ls eza               # typing `ls<space>` expands to `eza<space>`
alias dbtf=/Users/guty/.local/bin/dbt   # use only when expansion isn't enough
```

| | Abbreviation | Alias |
|---|---|---|
| Expansion | Inline (you see the real command) | Hidden (function wrap) |
| History | Stores expanded form | Stores shortcut |
| Editable before run | Yes | No |
| Lookup speed | O(1) hash | Function call |

## Functions

Put each function in its own file under `functions/`. Fish autoloads on first call.

```fish
# ~/.config/fish/functions/greet.fish
function greet --description 'Say hi'
    echo "Hi, $argv"
end
```

Calling `greet` will trigger autoload — no startup cost.

## Plugin Manager (Fisher)

[Fisher](https://github.com/jorgebucaran/fisher) is the recommended plugin manager. **Oh My Fish is dead** (unmaintained, broken packages — confirmed by its own GitHub warning).

```fish
# Install Fisher itself
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher

# Install a plugin
fisher install some/plugin
```

## Prompt (Tide)

[Tide](https://github.com/IlanCosman/tide) is the Fish-native prompt. Async rendering, faster than Starship in pure-Fish setups.

```fish
fisher install IlanCosman/tide@v6
tide configure                # interactive wizard
```

Pick **Lean** style + **2 lines** + **Nerd Font** for a clean, fast prompt.

Use **Starship** instead if you want one prompt config across fish + zsh + bash.

## Modern CLI Tool Integration

Initialize tools in `conf.d/20-tools.fish`. Always guard with `type -q` so the config doesn't break when a tool isn't installed:

```fish
status is-interactive; or exit 0

type -q zoxide; and zoxide init fish | source
type -q atuin;  and atuin init fish | source
type -q direnv; and direnv hook fish | source
```

## Companion Tools

Install with brew:

```bash
brew install fish eza bat zoxide atuin git-delta btop dust duf procs \
             zellij yazi lazygit lazydocker hyperfine gping jaq jless \
             xh sd just tealdeer tokei
```

| Tool | Replaces | Notes |
|------|----------|-------|
| `eza`        | `ls`        | Color, git status, tree mode |
| `bat`        | `cat`       | Syntax highlighting |
| `zoxide`     | `cd`        | Frecency-based jumps (`z foo`) |
| `atuin`      | history     | SQLite-backed, fuzzy search |
| `git-delta`  | git diff    | Side-by-side syntax-highlighted diffs |
| `btop`       | `top`       | Best resource monitor |
| `dust`       | `du`        | Visual disk usage |
| `duf`        | `df`        | Pretty disk free |
| `procs`      | `ps`        | Modern process list |
| `zellij`     | `tmux`      | Better defaults, less config |
| `yazi`       | `nnn`/`ranger` | Async file manager, native Ghostty image preview |
| `lazygit`    | git CLI     | TUI for complex git ops |
| `lazydocker` | docker CLI  | TUI for Docker |
| `hyperfine`  | `time`      | Statistical benchmarking |
| `gping`      | `ping`      | Real-time ping graph |
| `jaq`        | `jq`        | Faster Rust drop-in |
| `jless`      | viewing JSON | Interactive JSON viewer |
| `xh`         | `curl`      | Friendly HTTP client |
| `sd`         | `sed`       | Intuitive find-replace |
| `just`       | `make` (tasks) | Modern task runner |
| `tealdeer`   | `tldr`      | Faster Rust impl |
| `tokei`      | `wc -l` (code) | Per-language line counts |

## Reverting to Zsh

Fully reversible. `~/.zshrc` and oh-my-zsh remain installed.

```bash
sudo dscl . -create /Users/$(whoami) UserShell /bin/zsh
# Restart terminal
```

## Ready-to-Use Configs

See `docs/fish/`:

- `config-minimal/`     — single-file, server-friendly
- `config-recommended/` — modular, sensible defaults
- `config-power-user/`  — full integrations (Claude Code, mise, bun, dbt, etc.)

## Troubleshooting

**Tide prompt looks broken** → install a Nerd Font (e.g. JetBrainsMono Nerd Font, MesloLGS NF).

**`mise` activated twice** → harmless. The brew vendor autoload + `15-mise.fish` are both idempotent.

**SSH/scripts failing** → some scripts assume bash/zsh. Use `bash -c '...'` or add a `#!/bin/bash` shebang.

**Slow startup** → check `time fish -i -c exit`. Should be <100ms. If higher, comment out `conf.d/*.fish` files one at a time to find the culprit.

## Sources

- [Fish official docs (4.6.0)](https://fishshell.com/docs/current/)
- [fish_add_path docs](https://fishshell.com/docs/current/cmds/fish_add_path.html)
- [abbr docs](https://fishshell.com/docs/current/cmds/abbr.html)
- [Fisher GitHub](https://github.com/jorgebucaran/fisher)
- [Tide GitHub](https://github.com/IlanCosman/tide)
- [Modular Fish-Shell Configuration gist](https://gist.github.com/dfrommi/453f4e2c6635d2965802ac84b88519f5)
