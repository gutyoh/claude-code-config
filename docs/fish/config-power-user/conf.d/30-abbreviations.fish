# 30-abbreviations.fish — abbreviations expand inline on space/enter
#
# Why abbreviations over aliases:
#   - You see the real command before pressing Enter (editable)
#   - History stores the full command, not the shortcut
#   - O(1) hash lookup (faster than alias function-wrap)

status is-interactive; or exit 0

# ── ls family (eza) ──────────────────────────────────────────────────
abbr -a ls   eza
abbr -a ll   'eza -la --git --icons'
abbr -a la   'eza -la --git'
abbr -a lt   'eza --tree --level=2 --git --icons'

# ── core file/text tools ─────────────────────────────────────────────
abbr -a cat  bat
abbr -a find fd
abbr -a grep rg
abbr -a sed  sd
abbr -a help tldr

# ── system monitors ──────────────────────────────────────────────────
abbr -a top  btop
abbr -a du   dust
abbr -a df   duf
abbr -a ps   procs

# ── network/HTTP ─────────────────────────────────────────────────────
abbr -a curl xh

# ── git / docker ─────────────────────────────────────────────────────
abbr -a g    git
abbr -a lg   lazygit
abbr -a ld   lazydocker
abbr -a y    yazi

# ── dbt ──────────────────────────────────────────────────────────────
alias dbtf=/Users/guty/.local/bin/dbt
