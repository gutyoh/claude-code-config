# Ghostty Terminal Configuration Guide (2026)

Comprehensive reference for configuring Ghostty on macOS. Based on official docs, community configs, and 2026 best practices.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Config Files](#config-files)
3. [Font Settings](#font-settings)
4. [Themes](#themes)
5. [Cursor Settings](#cursor-settings)
6. [macOS-Specific Settings](#macos-specific-settings)
7. [Window and UI](#window-and-ui)
8. [Transparency and Blur](#transparency-and-blur)
9. [Shell Integration](#shell-integration)
10. [Clipboard and Mouse](#clipboard-and-mouse)
11. [Scrollback and Performance](#scrollback-and-performance)
12. [Keybindings](#keybindings)
13. [Quick Terminal (Dropdown)](#quick-terminal-dropdown)
14. [Split Panes](#split-panes)
15. [Notable Features (1.2.x and Upcoming 1.3.0)](#notable-features)
16. [Ready-to-Use Configs](#ready-to-use-configs)
17. [Useful Commands](#useful-commands)
18. [Sources](#sources)

---

## Quick Start

Ghostty config lives at:

```
~/.config/ghostty/config
```

Or on macOS:

```
~/Library/Application Support/com.mitchellh.ghostty/config
```

Format is simple `key = value` (INI-style). Lines starting with `#` are comments.

To reload config at runtime: **Cmd+Shift+,** (default keybinding).

---

## Config Files

This repository includes ready-to-use config presets in [`docs/ghostty/`](./ghostty/):

| File | Description | Use Case |
|------|-------------|----------|
| [`config-recommended.ini`](./ghostty/config-recommended.ini) | Opinionated SOTA recommendation | Daily driver, best engineering default |
| [`config-minimal.ini`](./ghostty/config-minimal.ini) | Clean, native macOS feel | Want minimal overrides |
| [`config-aesthetic.ini`](./ghostty/config-aesthetic.ini) | Transparent, blurred, riced | Want it to look beautiful |
| [`config-power-user.ini`](./ghostty/config-power-user.ini) | Optimized for tmux + Neovim | Live in tmux, want zero chrome |
| [`config-maximalist.ini`](./ghostty/config-maximalist.ini) | Every popular option enabled | Want everything, will trim later |

To use one: copy it to your Ghostty config path:

```bash
cp docs/ghostty/config-recommended.ini ~/.config/ghostty/config
```

---

## Font Settings

Ghostty embeds **JetBrains Mono** as its default and has **built-in Nerd Font symbols** (so you don't strictly need a patched Nerd Font). However, most users prefer an explicit font.

### Recommended Fonts (2026)

| Font | Notes |
|------|-------|
| **JetBrains Mono** | Default, excellent readability, good ligatures |
| **JetBrainsMono Nerd Font Mono** | Patched version with full icon support |
| **Fira Code** | Very popular, excellent ligatures |
| **MonoLisa** | Premium, beautiful variable font (needs `font-thicken`) |
| **Berkeley Mono** | Premium, clean and modern |
| **Victor Mono** | Distinctive cursive italics |
| **MesloLGS Nerd Font Mono** | Popular with Powerlevel10k users |
| **Monaspace** (by GitHub) | Cutting-edge features, multiple styles |
| **0xProto Nerd Font** | Clean and modern, growing popularity |
| **CaskaydiaCove Nerd Font Mono** | Microsoft's Cascadia Code with Nerd Font icons |

### Font Options Reference

```ini
# Basic font setup
font-family = "JetBrainsMono Nerd Font Mono"
font-size = 14

# Thicken fonts on macOS (great for Retina and thin/variable fonts)
font-thicken = true
font-thicken-strength = 200

# Explicit bold/italic variants
font-family-bold = "JetBrainsMono Nerd Font Mono Bold"
font-family-italic = "JetBrainsMono Nerd Font Mono Italic"
font-family-bold-italic = "JetBrainsMono Nerd Font Mono Bold Italic"

# Font style/weight
font-style = medium

# Cell height adjustment (vertical line spacing)
adjust-cell-height = 35%    # Percentage
adjust-cell-height = 1      # Absolute pixels

# Ligatures
font-feature = +liga         # Standard ligatures
font-feature = +calt         # Contextual alternates (on by default)
font-feature = +dlig         # Discretionary ligatures (off by default since 1.2.0)

# Disable ALL ligatures
font-feature = -calt
font-feature = -liga
font-feature = -dlig

# Bold text renders as bright colors
bold-is-bright = true
```

### Font Discovery

```bash
ghostty +list-fonts          # List all available fonts
```

---

## Themes

Ghostty ships with **300+ built-in themes** (sourced from iTerm2 color scheme repository). Since 1.2.0, theme names use **Title Case with spaces**.

### Popular Themes (2026)

| Theme | Style | Config Value |
|-------|-------|-------------|
| **Catppuccin Mocha** | Modern pastel dark | `Catppuccin Mocha` |
| **Catppuccin Frappe** | Medium contrast pastel | `Catppuccin Frappe` |
| **Catppuccin Macchiato** | Warm pastel dark | `Catppuccin Macchiato` |
| **Catppuccin Latte** | Pastel light theme | `Catppuccin Latte` |
| **Tokyo Night** | Vibrant city-inspired dark | `TokyoNight` |
| **Tokyo Night Storm** | Darker Tokyo Night variant | `TokyoNight Storm` |
| **Dracula** | Classic dark purple | `Dracula` |
| **Dracula+** | Enhanced Dracula | `Dracula+` |
| **Gruvbox Dark** | Retro warm dark colors | `Gruvbox Dark` |
| **Nord** | Arctic blue palette | `Nord` |
| **Rose Pine** | Elegant dark | `rose-pine` |
| **Rose Pine Dawn** | Elegant light | `rose-pine-dawn` |
| **GitHub Dark Default** | GitHub's dark palette | `GitHub Dark Default` |
| **GitHub Light Default** | GitHub's light palette | `GitHub Light Default` |
| **Vesper** | Warm, low-contrast dark | `vesper` |

### Theme Configuration

```ini
# Single theme
theme = Catppuccin Mocha

# Auto light/dark switching (follows macOS system appearance)
theme = light:Catppuccin Latte,dark:Catppuccin Mocha
theme = light:rose-pine-dawn,dark:rose-pine
theme = light:GitHub Light Default,dark:GitHub Dark Default
```

### Custom Colors (manual palette override)

```ini
background = #1e1e2e
foreground = #cdd6f4
cursor-color = #f5e0dc
selection-background = #353749
selection-foreground = #cdd6f4

# Full 16-color ANSI palette
palette = 0=#45475a
palette = 1=#f38ba8
palette = 2=#a6e3a1
palette = 3=#f9e2af
palette = 4=#89b4fa
palette = 5=#f5c2e7
palette = 6=#94e2d5
palette = 7=#bac2de
palette = 8=#585b70
palette = 9=#f38ba8
palette = 10=#a6e3a1
palette = 11=#f9e2af
palette = 12=#89b4fa
palette = 13=#f5c2e7
palette = 14=#94e2d5
palette = 15=#a6adc8
```

### Custom Theme Files

Create custom themes at `~/.config/ghostty/themes/<theme-name>` and reference by name.

### Theme Discovery

```bash
ghostty +list-themes                # Interactive theme browser
# Web: https://terminalcolors.com/ghostty/
# Web: https://ghostty.zerebos.com/
```

---

## Cursor Settings

```ini
# Style: block, bar, underline
cursor-style = block

# Disable blinking (popular preference, reduces distraction)
cursor-style-blink = false

# Cursor color
cursor-color = #f5e0dc

# Invert foreground/background for cursor (alternative to explicit color)
cursor-invert-fg-bg = true

# Cursor opacity (0.0-1.0)
cursor-opacity = 0.9

# Thickness for bar/underline styles
adjust-cursor-thickness = 2

# Click-to-move cursor at prompts (Option+click on macOS)
cursor-click-to-move = true
```

### Custom Cursor Shaders (1.2.0+)

Ghostty supports cursor shaders for effects like trails and animations:

```ini
custom-shader = ./shaders/cursor_blaze.glsl
custom-shader-animation = true
```

---

## macOS-Specific Settings

```ini
# Treat Option key as Alt (essential for terminal workflows)
macos-option-as-alt = true
# Or only left Option:
macos-option-as-alt = left

# Titlebar style
macos-titlebar-style = tabs          # Tabs in titlebar (most popular)
macos-titlebar-style = transparent   # Blends with terminal background
macos-titlebar-style = hidden        # No titlebar (keeps rounded corners)
macos-titlebar-style = native        # Default macOS titlebar

# Auto-update
auto-update = download
auto-update-channel = stable

# Color space (P3 for wider gamut on Mac displays)
window-colorspace = display-p3

# Secure input (prevents keylogging by other apps)
macos-auto-secure-input = true
macos-secure-input-indication = true

# Hide from dock and app switcher
macos-hidden = true

# Hide traffic light buttons
macos-window-buttons = hidden

# Titlebar proxy icon
macos-titlebar-proxy-icon = hidden

# Fullscreen below notch
padded-notch = true
```

### Custom Dock Icon

```ini
macos-icon = custom-style
macos-icon-frame = plastic
macos-icon-ghost-color = #FFFFFF
macos-icon-screen-color = #000000

# Or holographic:
macos-icon = holographic
```

---

## Window and UI

```ini
# Window padding (pixels)
window-padding-x = 10
window-padding-y = 10

# Auto-balance padding for centered content
window-padding-balance = true

# Extend background color into padding area
window-padding-color = extend
window-padding-color = background

# Save and restore window state (position, size, tabs, splits)
window-save-state = always

# Window theme
window-theme = auto
window-theme = dark

# Confirm before closing terminal with running process
confirm-close-surface = false

# Quit when last window closes
quit-after-last-window-closed = true

# Start maximized
maximize = true

# Resize overlay
resize-overlay = never
resize-overlay = after-first
```

---

## Transparency and Blur

```ini
# Background opacity (0.0 = fully transparent, 1.0 = opaque)
background-opacity = 0.85
# Popular choices: 0.75, 0.85, 0.9, 0.95

# Background blur radius (only works with opacity < 1.0)
background-blur-radius = 20
# Or shorthand:
background-blur = 16
# Popular range: 10-40

# macOS 26 (Tahoe) glass effect (tip/1.3+ only):
background-blur = macos-glass-regular

# Black background for best transparency look
background = #000000

# Minimum contrast ratio (improves readability with transparent backgrounds)
minimum-contrast = 1.3
```

### Caveats

- `macos-titlebar-style = tabs` with `background-opacity < 1.0` has known visual quirks. Use `transparent` or `hidden` titlebar style with transparency.
- Transparency adds GPU compositing cost. Keep at 1.0 for maximum performance.

---

## Shell Integration

Ghostty's shell integration is one of its killer features. It auto-injects for zsh, bash, fish, and elvish.

```ini
# Auto-detect shell and inject integration (default)
shell-integration = detect

# Features to enable
shell-integration-features = cursor,sudo,title

# Full feature set including SSH helpers (recommended for 2026):
shell-integration-features = cursor,sudo,title,ssh-env,ssh-terminfo

# If you don't want shell integration to change your cursor:
shell-integration-features = no-cursor,sudo,title
```

### Feature Descriptions

| Feature | What It Does |
|---------|-------------|
| `cursor` | Changes cursor to bar at prompts, block in running commands |
| `sudo` | Preserves Ghostty terminfo through sudo |
| `title` | Sets terminal title to current working directory/command |
| `ssh-env` | Sets TERM=xterm-256color for SSH sessions (opt-in, 1.2.0+) |
| `ssh-terminfo` | Copies Ghostty's terminfo to remote machines (opt-in, 1.2.0+) |

### macOS Bash Note

macOS ships with bash 3.2 which is too old for automatic injection. Source manually in `~/.bashrc`:

```bash
if [ -n "${GHOSTTY_RESOURCES_DIR}" ]; then
    builtin source "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash"
fi
```

---

## Clipboard and Mouse

### Clipboard

```ini
# Auto-copy selected text to clipboard
copy-on-select = clipboard

# Trim trailing whitespace from copied text
clipboard-trim-trailing-spaces = true

# Allow programs to read/write clipboard
clipboard-read = allow
clipboard-write = allow

# Paste protection (warns about dangerous content like newlines)
clipboard-paste-protection = true
clipboard-paste-protection = false
```

### Mouse

```ini
# Hide cursor while typing
mouse-hide-while-typing = true

# Scroll speed multiplier
mouse-scroll-multiplier = 2

# URL detection and clickability
link-url = true
```

---

## Scrollback and Performance

```ini
# Scrollback buffer (default: 10,000 lines)
scrollback-limit = 1_000_000     # 1M lines (~50MB RAM, good balance)
scrollback-limit = 10_000_000    # 10M lines (heavy log work)
scrollback-limit = 100_000_000   # 100M lines (~5GB RAM, extreme)

# Image storage limit (bytes, for Kitty image protocol)
image-storage-limit = 320000000

# Window vsync (helps with tearing on external monitors)
window-vsync = true
```

### Performance Tips

- Ghostty uses **Metal** on macOS by default. No manual GPU config needed.
- Reducing `background-opacity` below 1.0 adds compositing cost.
- `background-blur` adds GPU load. Use 10-25 for a good balance.
- Keep `scrollback-limit` reasonable (1M is enough for most workflows).

---

## Keybindings

### Navigation

```ini
# Jump between prompts (requires shell integration)
keybind = cmd+up=jump_to_prompt:-1
keybind = cmd+down=jump_to_prompt:1

# Word navigation with Option key
keybind = cmd+right=text:\x05       # End of line
keybind = cmd+left=text:\x01        # Beginning of line
keybind = opt+left=esc:b            # Back one word
keybind = opt+right=esc:f           # Forward one word

# Send literal newline (multi-line commands)
keybind = shift+enter=text:\n

# Clear screen
keybind = cmd+k=clear_screen

# Scroll to top/bottom
keybind = cmd+home=scroll_to_top
keybind = cmd+end=scroll_to_bottom
```

### Utility

```ini
# Reload config
keybind = cmd+shift+,=reload_config

# Command palette (1.2.0+)
keybind = cmd+shift+p=toggle_command_palette

# Toggle fullscreen
keybind = cmd+shift+f=toggle_fullscreen

# Reset font size
keybind = cmd+0=reset_font_size

# Toggle window floating above all others (1.2.0+)
keybind = cmd+shift+t=toggle_window_float_on_top
```

### Tab Management

```ini
keybind = cmd+t=new_tab
keybind = cmd+shift+]=next_tab
keybind = cmd+shift+[=previous_tab
keybind = cmd+w=close_surface
```

### tmux Integration

```ini
# Send tmux prefix (Ctrl+a) then key
keybind = cmd+s=text:\x01\x73       # tmux save
keybind = cmd+b=text:\x01\x7a       # tmux zoom toggle
```

### Key Sequences (Leader Key Pattern)

```ini
# Ghostty supports key sequences with > separator
keybind = ctrl+x>2=new_split:down
keybind = ctrl+x>3=new_split:right

# Leader key pattern
keybind = cmd+s>r=reload_config
keybind = cmd+s>x=close_surface
keybind = cmd+s>n=new_window
keybind = cmd+s>c=new_tab
```

---

## Quick Terminal (Dropdown)

System-wide dropdown terminal activated by a global hotkey:

```ini
# Global hotkey (works even when Ghostty is not focused)
keybind = global:cmd+grave_accent=toggle_quick_terminal

# Position: top, bottom, left, right, center
quick-terminal-position = top

# Which screen to appear on
quick-terminal-screen = mouse     # Follows mouse across monitors
quick-terminal-screen = main      # Always on primary display

# Animation speed
quick-terminal-animation-duration = 0.1
quick-terminal-animation-duration = 0     # Instant

# Auto-hide when losing focus
quick-terminal-autohide = true

# Size (for center position)
quick-terminal-size = 80%,80%
```

---

## Split Panes

```ini
# Create splits (iTerm2-like)
keybind = cmd+d=new_split:right
keybind = cmd+shift+d=new_split:down

# Navigate between splits
keybind = cmd+opt+left=goto_split:left
keybind = cmd+opt+right=goto_split:right
keybind = cmd+opt+up=goto_split:up
keybind = cmd+opt+down=goto_split:down

# Equalize split sizes
keybind = cmd+shift+==equalize_splits

# Zoom/toggle a split
keybind = cmd+shift+enter=toggle_split_zoom

# Dim unfocused splits
unfocused-split-opacity = 0.5

# Focus split by hovering mouse
focus-follows-mouse = true
```

---

## Notable Features

### Available Now (1.2.x stable)

| Feature | Description |
|---------|-------------|
| Command Palette | Cmd+Shift+P to search and execute any action |
| Background Images | Set terminal background images with opacity/fit controls |
| SSH Integration | `ssh-env` and `ssh-terminfo` for better remote sessions |
| Custom Cursor Shaders | Cursor trails and animated effects via GLSL |
| Undo/Redo Close | Recover accidentally closed terminals on macOS |
| Apple Shortcuts | Automate Ghostty via macOS Shortcuts.app |
| Link Previews | URL preview overlays on hover |
| Window Float | Toggle window above all others |

### Coming in 1.3.0 (March/April 2026)

| Feature | Description |
|---------|-------------|
| Scrollback Search | Cmd+F to search terminal history (most requested feature) |
| Scrollbars | Native scrollbar support |
| macOS 26 Liquid Glass | Native Tahoe glass styling support |

---

## Ready-to-Use Configs

See [`docs/ghostty/`](./ghostty/) for complete config presets:

| Preset | Philosophy |
|--------|-----------|
| **Recommended** | Minimal overrides, productivity-focused, no visual noise |
| **Minimal** | Clean macOS-native feel, fewest settings possible |
| **Aesthetic** | Transparency, blur, beautiful but with readability trade-offs |
| **Power User** | Zero chrome, tmux-optimized, hidden titlebar |
| **Maximalist** | Every popular option, good starting point to trim from |

---

## Useful Commands

```bash
ghostty +list-themes              # Interactive theme browser
ghostty +list-fonts               # List available fonts
ghostty +show-config --default --docs   # Show all options with docs
ghostty +list-keybinds --default  # Show default keybindings
```

---

## Sources

1. [Ghostty Official Documentation](https://ghostty.org/docs)
2. [Ghostty Config Reference](https://ghostty.org/docs/config/reference)
3. [Ghostty 1.2.0 Release Notes](https://ghostty.org/docs/install/release-notes/1-2-0)
4. [Ghostty 1.3.0 Milestone](https://github.com/ghostty-org/ghostty/milestone/7)
5. [Ghostty Config Generator](https://ghostty.zerebos.com/)
6. [Terminal Colors - Ghostty Themes](https://terminalcolors.com/ghostty/)
7. [Catppuccin for Ghostty](https://github.com/catppuccin/ghostty)
8. [Reddit r/Ghostty](https://www.reddit.com/r/Ghostty/)
9. [Ghostty GitHub Discussions](https://github.com/ghostty-org/ghostty/discussions)
10. [Mike Bommarito - Ghostty Configuration](https://michaelbommarito.com/wiki/programming/tools/ghostty-configuration/)
11. [Samuel Lawrentz - Minimal Ghostty Config](https://samuellawrentz.com/blog/minimal-ghostty-config/)
12. [respawn.io - Ghostty Is Awesome](https://respawn.io/posts/ghostty-is-awesome)
13. [perrotta.dev - Ghostty Splits](https://perrotta.dev/2026/01/ghostty-splits/)

---

*Last updated: February 2026*
