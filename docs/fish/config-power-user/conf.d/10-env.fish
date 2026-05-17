# Environment variables. SSH_AUTH_SOCK is resolved first-match-wins
# across Bitwarden, 1Password (macOS), gnome-keyring, and systemd
# ssh-agent — only the agent the user actually runs exposes a socket,
# so detection stays bulletproof on macOS/Linux/server without per-host
# config. Refs: fish-shell/fish-shell#12138

set -gx GOPATH $HOME/go
fish_add_path -ga $GOPATH/bin

if test -x /usr/libexec/java_home
    set -gx JAVA_HOME (/usr/libexec/java_home 2>/dev/null)
else if not set -q JAVA_HOME; and command -q javac
    set -gx JAVA_HOME (path resolve (command -s javac)/../..)
end

set -gx BUN_INSTALL $HOME/.bun

for __ssh_sock in \
    $HOME/.bitwarden-ssh-agent.sock \
    $HOME/.1password/agent.sock \
    "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" \
    $XDG_RUNTIME_DIR/gcr/ssh \
    $XDG_RUNTIME_DIR/ssh-agent.socket
    if test -S "$__ssh_sock"
        set -gx SSH_AUTH_SOCK "$__ssh_sock"
        break
    end
end
set -e __ssh_sock
