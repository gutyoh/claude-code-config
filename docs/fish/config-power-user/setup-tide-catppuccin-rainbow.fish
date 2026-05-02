#!/usr/bin/env fish
#
# setup-tide-catppuccin-rainbow.fish
# ──────────────────────────────────────────────────────────────────────
# One-shot setup for Tide v6 prompt + fish syntax highlighting,
# Catppuccin Mocha palette, Rainbow style with Slanted separators.
#
# Run ONCE after copying the power-user preset. All settings are
# stored as fish universal variables (set -U), so they persist across
# every fish shell — no need to source this on every startup.
#
# Re-run any time you want to reset to this preset's defaults.
#
# Usage:
#   fish setup-tide-catppuccin-rainbow.fish
#
# Prerequisites:
#   - fish 4.x
#   - fisher (https://github.com/jorgebucaran/fisher)
#   - tide v6  (fisher install IlanCosman/tide@v6)
#   - a Nerd Font in your terminal (JetBrainsMono Nerd Font, MesloLGS NF, etc.)
#
# Upstream sources (for verifying / updating colors):
#   - Palette:    https://catppuccin.com/palette/   (Mocha variant)
#   - Fish port:  https://github.com/catppuccin/fish
#                 (built into fish 4.4+ — `fish_config theme list`)
#   - Tide port:  no official one; colors here come from community
#                 discussion https://github.com/catppuccin/catppuccin/discussions/2217
# ──────────────────────────────────────────────────────────────────────

set -l mocha_base    1e1e2e
set -l mocha_surface 313244
set -l mocha_text    cdd6f4
set -l mocha_subtext 7f849c
set -l mocha_blue    89b4fa
set -l mocha_green   a6e3a1
set -l mocha_yellow  f9e2af
set -l mocha_red     f38ba8
set -l mocha_mauve   cba6f7
set -l mocha_peach   fab387
set -l mocha_sky     89dceb
set -l mocha_lavender b4befe
set -l mocha_pink    f5c2e7
set -l mocha_teal    94e2d5

# ──────────────────────────────────────────────────────────────────────
# 1. Tide layout — Rainbow style, Slanted separators, Sharp powerline
#    head, Flat tail, 2 lines, sparse spacing, Many icons, transient.
# ──────────────────────────────────────────────────────────────────────
echo "▸ Applying Tide layout (Rainbow + Slanted)..."
tide configure --auto \
    --style=Rainbow \
    --prompt_colors='True color' \
    --show_time='No' \
    --rainbow_prompt_separators=Slanted \
    --powerline_prompt_heads=Sharp \
    --powerline_prompt_tails=Flat \
    --powerline_prompt_style='Two lines, character' \
    --prompt_connection=Disconnected \
    --powerline_right_prompt_frame=No \
    --prompt_spacing=Sparse \
    --icons='Many icons' \
    --transient=Yes >/dev/null

# ──────────────────────────────────────────────────────────────────────
# 2. Tide prompt items — minimal pwd→git on left, status/duration/time on right
# ──────────────────────────────────────────────────────────────────────
echo "▸ Setting prompt items..."
set -U tide_left_prompt_items pwd git newline character
set -U tide_right_prompt_items status cmd_duration time

# ──────────────────────────────────────────────────────────────────────
# 3. Tide Catppuccin Mocha palette
# ──────────────────────────────────────────────────────────────────────
echo "▸ Applying Catppuccin Mocha colors to Tide..."

# pwd segment (blue background, dark text)
set -U tide_pwd_bg_color $mocha_blue
set -U tide_pwd_color_dirs $mocha_base
set -U tide_pwd_color_anchors $mocha_base
set -U tide_pwd_color_truncated_dirs $mocha_surface
set -U tide_pwd_icon ''
set -U tide_pwd_icon_home ''
set -U tide_pwd_icon_unwritable ''

# git segment (green when clean, yellow when dirty, red when conflicted)
set -U tide_git_bg_color $mocha_green
set -U tide_git_bg_color_unstable $mocha_yellow
set -U tide_git_bg_color_urgent $mocha_red
set -U tide_git_color_branch $mocha_base
set -U tide_git_truncation_length 100   # show full branch names

# status (✓ green, ✗ red)
set -U tide_status_bg_color $mocha_green
set -U tide_status_bg_color_failure $mocha_red
set -U tide_status_color $mocha_base
set -U tide_status_color_failure $mocha_base

# cmd_duration (yellow, only shown if command took > 3 seconds)
set -U tide_cmd_duration_bg_color $mocha_yellow
set -U tide_cmd_duration_color $mocha_base
set -U tide_cmd_duration_threshold 3000

# time (24-hour, muted gray to blend in)
set -U tide_time_format '%H:%M:%S'
set -U tide_time_color $mocha_subtext

# context (mauve when shown — only on SSH by default)
set -U tide_context_color $mocha_mauve

# ──────────────────────────────────────────────────────────────────────
# 4. Fish syntax highlighting — Catppuccin Mocha (dark variant)
# ──────────────────────────────────────────────────────────────────────
echo "▸ Applying Catppuccin Mocha syntax colors..."

set -U fish_color_normal $mocha_text
set -U fish_color_command $mocha_blue
set -U fish_color_param f2cdcd
set -U fish_color_keyword $mocha_mauve
set -U fish_color_quote $mocha_green
set -U fish_color_redirection $mocha_pink
set -U fish_color_end $mocha_peach
set -U fish_color_comment $mocha_subtext
set -U fish_color_error $mocha_red
set -U fish_color_gray 6c7086
set -U fish_color_selection --background=$mocha_surface
set -U fish_color_search_match --background=$mocha_surface
set -U fish_color_option $mocha_green
set -U fish_color_operator $mocha_pink
set -U fish_color_escape eba0ac
set -U fish_color_autosuggestion 6c7086
set -U fish_color_cancel $mocha_red
set -U fish_color_cwd $mocha_yellow
set -U fish_color_user $mocha_teal
set -U fish_color_host $mocha_blue
set -U fish_color_host_remote $mocha_green
set -U fish_color_status $mocha_red
set -U fish_pager_color_progress 6c7086
set -U fish_pager_color_prefix $mocha_pink
set -U fish_pager_color_completion $mocha_text
set -U fish_pager_color_description 6c7086

echo ""
echo "✅ Done."
echo ""
echo "Open a new terminal tab to see the result. To revert:"
echo "    set -e tide_left_prompt_items tide_right_prompt_items ..."
echo "Or re-run this script after changing variables to reset to preset."
