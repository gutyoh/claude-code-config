#!/usr/bin/env fish
#
# setup-tide-fitz-roy.fish
# ──────────────────────────────────────────────────────────────────────
# One-shot setup for the Tide v6 prompt in the Fitz Roy palette: navy,
# granite orange and peach, glacier sky, Rainbow style with Slanted
# separators. Pairs with the Ghostty theme in docs/ghostty/themes/fitz-roy.
#
# Fish's own syntax colors are left to its default theme, which uses the
# 16 ANSI colors, so the Ghostty palette drives them. Any syntax colors a
# previous preset stored as universal variables are erased.
#
# All settings are universal variables (set -U): run once, or again to
# reset to this preset.
#
# Usage:
#   fish setup-tide-fitz-roy.fish
#
# Prerequisites:
#   - fish 4.x
#   - fisher (https://github.com/jorgebucaran/fisher)
#   - tide v6  (fisher install IlanCosman/tide@v6)
#   - a Nerd Font in your terminal
#   - functions/_tide_item_os_badge.fish from this preset
# ──────────────────────────────────────────────────────────────────────

set -l navy     0F1F2E
set -l orange   FB6526
set -l peach    F9A971
set -l blue     0165A5
set -l sky      84BCEC
set -l lavender A68DEB
set -l yellow   F4D54F
set -l red      E5484D
set -l green    7FB77E
set -l snow     F2F2F2
set -l slate    1F3A52
set -l indigo   3B2089

# ──────────────────────────────────────────────────────────────────────
# 1. Tide layout: Rainbow, Slanted separators, Sharp heads, Flat tails,
#    two lines, sparse, many icons, transient, 24-hour time.
# ──────────────────────────────────────────────────────────────────────
echo "▸ Applying Tide layout (Rainbow + Slanted)..."
tide configure --auto \
    --style=Rainbow \
    --prompt_colors='True color' \
    --show_time='24-hour format' \
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
# 2. Prompt items: OS badge, pwd and git on the left; status, duration
#    and time on the right.
# ──────────────────────────────────────────────────────────────────────
echo "▸ Setting prompt items..."
set -U tide_left_prompt_items os_badge pwd git newline character
set -U tide_right_prompt_items status cmd_duration time

# ──────────────────────────────────────────────────────────────────────
# 3. Fitz Roy colors
# ──────────────────────────────────────────────────────────────────────
echo "▸ Applying Fitz Roy colors to Tide..."

# OS badge (yellow glyph on navy)
set -U tide_os_badge_bg_color $navy
set -U tide_os_badge_color $yellow

# pwd (orange background, navy text)
set -U tide_pwd_bg_color $orange
set -U tide_pwd_color_dirs $navy
set -U tide_pwd_color_anchors $navy
set -U tide_pwd_color_truncated_dirs $indigo

# git (lavender when clean, yellow when dirty, red when conflicted)
set -U tide_git_bg_color $lavender
set -U tide_git_bg_color_unstable $yellow
set -U tide_git_bg_color_urgent $red
set -U tide_git_color_branch $navy
set -U tide_git_truncation_length 100

# status (green on success, red on failure)
set -U tide_status_bg_color $green
set -U tide_status_bg_color_failure $red
set -U tide_status_color $navy
set -U tide_status_color_failure $snow

# cmd_duration (peach, shown after every command)
set -U tide_cmd_duration_bg_color $peach
set -U tide_cmd_duration_color $navy
set -U tide_cmd_duration_threshold 0
set -U tide_cmd_duration_decimals 0

# time (deep blue)
set -U tide_time_bg_color $blue
set -U tide_time_color $snow
set -U tide_time_format '%H:%M:%S'

# prompt character (sky, red after a failed command)
set -U tide_character_color $sky
set -U tide_character_color_failure $red

# context, shown over SSH and as root. Tide reads only the _ssh, _root and
# _default colors; tide_context_color is overwritten on every prompt.
set -U tide_context_bg_color $slate
set -U tide_context_color_ssh $peach
set -U tide_context_color_default $peach
set -U tide_context_color_root $red
set -eU tide_context_color

# ──────────────────────────────────────────────────────────────────────
# 4. Fish syntax colors: back to the default theme
# ──────────────────────────────────────────────────────────────────────
echo "▸ Clearing syntax colors left by other presets..."
for v in (set -U --names | string match -r '^fish_(?:pager_)?color_.*')
    set -eU $v
end

echo ""
echo "✅ Done. Open a new terminal tab to see the result."
