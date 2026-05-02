# 10-env.fish — Environment variables

# Go
set -gx GOPATH $HOME/go
fish_add_path -ga $GOPATH/bin

# Java (only if java_home exists)
if test -x /usr/libexec/java_home
    set -gx JAVA_HOME (/usr/libexec/java_home 2>/dev/null)
end

# Bun
set -gx BUN_INSTALL $HOME/.bun

# Bitwarden SSH agent
set -gx SSH_AUTH_SOCK $HOME/.bitwarden-ssh-agent.sock
