# 35-zellij-autostart.fish — auto-attach to a persistent zellij session
# on SSH login, so moving between machines (laptop, home server, or a phone
# SSH client) always lands in the same persistent workspace.
#
# Conditions (all must be true to auto-attach):
#   1. status is-interactive   — only in interactive shells, never scripts
#   2. SSH_CONNECTION set      — only when SSH'd in (skip local terminals)
#   3. not already in zellij   — avoid recursive nesting on inner fish
#   4. zellij is installed     — silently no-op on machines without it
#
# Detach with Ctrl+p, d. The session keeps running on the host and you
# reattach next time you SSH in. The session name "claude" is shared so
# every device that SSHes to the same host lands in the same workspace.
#
# Refs:
#   https://github.com/zellij-org/zellij/discussions/1721
#   https://zellij.dev/documentation/integration

if status is-interactive
    and set -q SSH_CONNECTION
    and not set -q ZELLIJ
    and command -q zellij
    exec zellij attach -c claude
end
