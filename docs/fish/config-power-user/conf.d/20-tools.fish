# 20-tools.fish — Modern CLI tool init (interactive only)
#
# Each tool guarded with `type -q` so config doesn't break if a tool is
# uninstalled. All inits are designed for interactive shells.

status is-interactive; or exit 0

# zoxide — `cd` replacement with frecency-ranked jumps (z foo)
type -q zoxide; and zoxide init fish | source

# atuin — searchable shell history backed by SQLite
type -q atuin; and atuin init fish | source

# direnv — per-directory env vars via .envrc
type -q direnv; and direnv hook fish | source
