# Fish Shell Configuration

Modular Fish configuration presets, mirroring the structure of `docs/ghostty/`.

## Available Presets

| Preset | Layout | Best for |
|--------|--------|----------|
| `config-minimal/`        | single `config.fish` | Servers, throwaway boxes |
| `config-recommended/`    | modular `conf.d/` + `functions/` | Most users |
| `config-power-user/`     | full modular layout with all integrations | Daily driver — Claude Code, mise, bun, dbt, etc. |

## Layout Conventions (Modular Presets)

```
<preset>/
├── config.fish              minimal entrypoint (just a header comment)
├── conf.d/                  auto-loaded in numeric/alphabetic order on every shell
│   ├── 00-paths.fish        PATH additions
│   ├── 10-env.fish          env vars
│   ├── 15-mise.fish         mise (runtime version manager)
│   ├── 20-tools.fish        zoxide / atuin / direnv init (interactive)
│   ├── 30-abbreviations.fish   abbreviations
│   └── 40-bun.fish          bun completions (interactive)
├── functions/               auto-loaded ON FIRST CALL (lazy)
│   ├── claude.fish
│   └── clp.fish
└── setup-tide-*.fish        one-shot prompt + color theme installers
                              (Tide vars persist as universal vars,
                               so these run ONCE — not on every shell)
```

### Why this layout

- **`conf.d/`** instead of one fat `config.fish` — easier to add/remove features, easier to diff.
- **Numeric prefixes** (`00-`, `10-`, …) — explicit load order.
- **`functions/`** for shell functions — fish autoloads them on first call, so they cost nothing on startup.
- **`fish_add_path`** instead of `set -gx PATH` — official fish 4.6 recommendation, dedupes automatically.
- **Abbreviations** (`abbr -a`) instead of aliases — expand inline so history stores the real command.
- **`type -q` guards** — config doesn't break if a tool isn't installed yet.
- **Tide setup outside `conf.d/`** — Tide colors and layout are universal vars (persistent), so they only need to be applied once. Re-running on every shell would waste startup time.

## Available Color Themes

`config-power-user/` ships with two pre-built theme installers. Pick one — they each set both Tide prompt colors AND fish syntax-highlighting colors as universal variables.

| Theme | Script | Pairs with Ghostty theme |
|---|---|---|
| **Catppuccin Mocha** | `setup-tide-catppuccin-rainbow.fish` | `theme = Catppuccin Mocha` |
| **Rose Pine Moon**   | `setup-tide-rose-pine-moon.fish`     | `theme = rose-pine-moon` |

Both use the same Tide layout (Rainbow style, Slanted separators, Sharp powerline heads, 2-line, sparse, Many icons, transient prompt). Only the colors differ.

## Deployment

### Step 1 — install companion tools (Homebrew)

```bash
brew install fish eza bat zoxide atuin git-delta btop dust duf procs \
             zellij yazi lazygit lazydocker hyperfine gping jaq jless \
             xh sd just tealdeer tokei
```

### Step 2 — make fish your default shell (optional)

```bash
echo '/opt/homebrew/bin/fish' | sudo tee -a /etc/shells
sudo dscl . -create /Users/$(whoami) UserShell /opt/homebrew/bin/fish
```

> **Ghostty caveat:** Ghostty doesn't auto-detect default shell from `chsh`/`dscl` — it caches `$SHELL` from launchd at app start. Add `command = /opt/homebrew/bin/fish` to `~/.config/ghostty/config` so new windows reliably launch fish.

### Step 3 — copy the preset

```fish
cp -r docs/fish/config-power-user/config.fish      ~/.config/fish/
cp -r docs/fish/config-power-user/conf.d/*.fish    ~/.config/fish/conf.d/
cp -r docs/fish/config-power-user/functions/*.fish ~/.config/fish/functions/
```

### Step 4 — install Fisher + Tide inside fish

```fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
fisher install IlanCosman/tide@v6
```

### Step 5 — apply ONE theme (run once)

Pick one:

```fish
fish docs/fish/config-power-user/setup-tide-catppuccin-rainbow.fish   # Catppuccin Mocha
# or
fish docs/fish/config-power-user/setup-tide-rose-pine-moon.fish       # Rose Pine Moon
```

Open a new terminal tab — done.

### Future: symlink approach

Symlinks would auto-sync the live config to whatever is checked out in this repo (great for `git pull` updates, no manual re-copy). Deferred for now to keep parity with the `docs/ghostty/` copy-pattern.

To migrate later:

```fish
# Remove the copies first
rm ~/.config/fish/config.fish
rm ~/.config/fish/conf.d/{00-paths,10-env,15-mise,20-tools,30-abbreviations,40-bun}.fish
rm ~/.config/fish/functions/{claude,clp}.fish

# Symlink instead
set repo /Users/guty/Documents/dev/claude-code-config
ln -sf $repo/docs/fish/config-power-user/config.fish ~/.config/fish/config.fish
for f in $repo/docs/fish/config-power-user/conf.d/*.fish
    ln -sf $f ~/.config/fish/conf.d/(basename $f)
end
for f in $repo/docs/fish/config-power-user/functions/*.fish
    ln -sf $f ~/.config/fish/functions/(basename $f)
end
```

## Companion Tools

Used by the configs above:

- `fish` 4.6+ (the shell)
- `eza` `bat` `zoxide` `atuin` `git-delta` `btop` `dust` `duf` `procs`
- `zellij` `yazi` `lazygit` `lazydocker`
- `hyperfine` `gping` `jaq` `jless` `xh` `sd` `just` `tealdeer` `tokei`
- `fisher` (plugin manager, installed inside fish)
- `tide` (prompt, installed via fisher)

## References / Upstream Sources

These setup scripts hardcode color values for self-containment and offline use, but the values come from these upstream projects. Update the scripts when these projects release new palettes.

### Fish shell

- [fishshell.com/docs/current](https://fishshell.com/docs/current/) — official fish 4.x documentation
- [fish_add_path](https://fishshell.com/docs/current/cmds/fish_add_path.html) — recommended PATH manipulation
- [abbr](https://fishshell.com/docs/current/cmds/abbr.html) — abbreviations vs aliases
- [Configuration files](https://fishshell.com/docs/current/language.html#configuration) — `config.fish` and `conf.d/` loading order

### Tide prompt

- [IlanCosman/tide](https://github.com/IlanCosman/tide) — main repo
- [Tide Configuration Wiki](https://github.com/IlanCosman/tide/wiki/Configuration) — all `tide_*` variables
- [Custom prompt items](https://github.com/IlanCosman/tide/wiki/Custom-items-(prompt-segments))

### Fisher (plugin manager)

- [jorgebucaran/fisher](https://github.com/jorgebucaran/fisher)

### Catppuccin Mocha theme

- [Catppuccin official site + palette](https://catppuccin.com/palette/) — Mocha variant hex values
- [catppuccin/fish](https://github.com/catppuccin/fish) — official fish syntax theme (built into fish 4.4+)
- [catppuccin/catppuccin discussion #2217](https://github.com/catppuccin/catppuccin/discussions/2217) — community Tide color recipes
- [catppuccin/ghostty](https://github.com/catppuccin/ghostty) — matching Ghostty theme

### Rose Pine Moon theme

- [Rose Pine palette](https://rosepinetheme.com/palette/) — Moon variant hex values
- [rose-pine/fish](https://github.com/rose-pine/fish) — official fish syntax theme
- [rose-pine/tide](https://github.com/rose-pine/tide) — official Tide port
- [rose-pine/ghostty](https://github.com/rose-pine) — matching Ghostty theme (search for `ghostty` in the org)

### Reference dotfiles (real-world examples)

- [craftzdog/dotfiles-public](https://github.com/craftzdog/dotfiles-public) — popular Lean Tide config
- [edheltzel/dotfiles](https://github.com/edheltzel/dotfiles) — fish + macOS reference
- [caarlos0/dotfiles.fish](https://github.com/caarlos0/dotfiles.fish) — minimal fish config
- [jorgebucaran/awsm.fish](https://github.com/jorgebucaran/awsm.fish) — curated fish ecosystem list

### Comparison + background reading

- [Tide vs Starship 2026 — Akmatori](https://akmatori.com/blog/tide-vs-starship-shell-prompt)
- [Bitdoze: Fish Shell Themes](https://www.bitdoze.com/fish-shell-themes-prompts/)
- [Modular Fish-Shell Configuration gist](https://gist.github.com/dfrommi/453f4e2c6635d2965802ac84b88519f5)

## Reverting

To go back to your previous shell:

```bash
sudo dscl . -create /Users/$(whoami) UserShell /bin/zsh
```

Your `~/.zshrc` and `~/.oh-my-zsh` remain intact — switch is instant.
