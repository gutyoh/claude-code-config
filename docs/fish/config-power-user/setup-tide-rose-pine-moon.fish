#!/usr/bin/env fish
#
# setup-tide-rose-pine-moon.fish
# ──────────────────────────────────────────────────────────────────────
# One-shot setup for Tide v6 prompt + fish syntax highlighting,
# Rose Pine Moon palette, Rainbow style with Slanted separators.
#
# This is the alternative to setup-tide-catppuccin-rainbow.fish — pick
# one palette to match your terminal theme. If you switch to this, also
# update Ghostty: theme = rose-pine-moon
#
# Run ONCE after copying the power-user preset. All settings are stored
# as fish universal variables (set -U), so they persist across every
# fish shell — no need to source on every startup.
#
# Re-run any time you want to reset to this preset's defaults.
#
# Usage:
#   fish setup-tide-rose-pine-moon.fish
#
# Prerequisites:
#   - fish 4.x
#   - fisher (https://github.com/jorgebucaran/fisher)
#   - tide v6  (fisher install IlanCosman/tide@v6)
#   - a Nerd Font in your terminal
#
# Upstream sources (for verifying / updating colors):
#   - Palette:    https://rosepinetheme.com/palette/
#   - Tide port:  https://github.com/rose-pine/tide
#   - Fish port:  https://github.com/rose-pine/fish
# ──────────────────────────────────────────────────────────────────────

# Rose Pine Moon palette
# https://rosepinetheme.com/palette/ → Moon variant
set -l rp_base       232136
set -l rp_surface    2a273f
set -l rp_overlay    393552
set -l rp_muted      6e6a86
set -l rp_subtle     908caa
set -l rp_text       e0def4
set -l rp_love       eb6f92
set -l rp_gold       f6c177
set -l rp_rose       ea9a97
set -l rp_pine       3e8fb0
set -l rp_foam       9ccfd8
set -l rp_iris       c4a7e7
set -l rp_hl_low     2a283e
set -l rp_hl_med     44415a
set -l rp_hl_high    56526e

# ──────────────────────────────────────────────────────────────────────
# 1. Tide layout — Rainbow + Slanted (same as Catppuccin variant)
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
# 2. Tide prompt items — pwd→git on left, status/duration/time on right
# ──────────────────────────────────────────────────────────────────────
echo "▸ Setting prompt items..."
set -U tide_left_prompt_items pwd git newline character
set -U tide_right_prompt_items status cmd_duration time

# ──────────────────────────────────────────────────────────────────────
# 3. Tide Rose Pine Moon palette
# ──────────────────────────────────────────────────────────────────────
echo "▸ Applying Rose Pine Moon colors to Tide..."

# pwd segment (foam/cyan background, dark text)
set -U tide_pwd_bg_color $rp_foam
set -U tide_pwd_color_dirs $rp_base
set -U tide_pwd_color_anchors $rp_base
set -U tide_pwd_color_truncated_dirs $rp_overlay
set -U tide_pwd_icon ''
set -U tide_pwd_icon_home ''
set -U tide_pwd_icon_unwritable ''

# git segment (pine/blue clean, gold dirty, love/red conflicted)
set -U tide_git_bg_color $rp_pine
set -U tide_git_bg_color_unstable $rp_gold
set -U tide_git_bg_color_urgent $rp_love
set -U tide_git_color_branch $rp_text
set -U tide_git_truncation_length 100

# status (✓ pine, ✗ love)
set -U tide_status_bg_color $rp_pine
set -U tide_status_bg_color_failure $rp_love
set -U tide_status_color $rp_text
set -U tide_status_color_failure $rp_text

# cmd_duration (gold, only > 3 seconds)
set -U tide_cmd_duration_bg_color $rp_gold
set -U tide_cmd_duration_color $rp_base
set -U tide_cmd_duration_threshold 3000

# time (24-hour, muted to blend in)
set -U tide_time_format '%H:%M:%S'
set -U tide_time_color $rp_subtle

# context (iris/purple when shown)
set -U tide_context_color $rp_iris

# ──────────────────────────────────────────────────────────────────────
# 4. Fish syntax highlighting — Rose Pine Moon
# ──────────────────────────────────────────────────────────────────────
echo "▸ Applying Rose Pine Moon syntax colors..."

set -U fish_color_normal $rp_text
set -U fish_color_command $rp_foam
set -U fish_color_param $rp_rose
set -U fish_color_keyword $rp_iris
set -U fish_color_quote $rp_gold
set -U fish_color_redirection $rp_pine
set -U fish_color_end $rp_iris
set -U fish_color_comment $rp_muted
set -U fish_color_error $rp_love
set -U fish_color_gray $rp_subtle
set -U fish_color_selection --background=$rp_hl_med
set -U fish_color_search_match --background=$rp_hl_med
set -U fish_color_option $rp_gold
set -U fish_color_operator $rp_pine
set -U fish_color_escape $rp_love
set -U fish_color_autosuggestion $rp_muted
set -U fish_color_cancel $rp_love
set -U fish_color_cwd $rp_gold
set -U fish_color_user $rp_iris
set -U fish_color_host $rp_foam
set -U fish_color_host_remote $rp_pine
set -U fish_color_status $rp_love
set -U fish_pager_color_progress $rp_muted
set -U fish_pager_color_prefix $rp_pine
set -U fish_pager_color_completion $rp_text
set -U fish_pager_color_description $rp_muted

echo ""
echo "✅ Done."
echo ""
echo "Open a new terminal tab to see the result."
echo "If switching from Catppuccin, also update Ghostty:"
echo "    sed -i '' 's/Catppuccin Mocha/rose-pine-moon/' ~/.config/ghostty/config"
