# PATH wiring across Apple Silicon, Intel Mac, and Linux brew. We probe
# the four common brew prefixes and let the first match drive shellenv;
# the explicit `fish` arg avoids the shell-autodetect bug in early-2026
# brew releases (Homebrew/brew#21382, #21388). fish_add_path silently skips
# missing dirs, so user-local entries are safe on machines that lack them.

fish_add_path -gp $HOME/bin

for __brew_prefix in /opt/homebrew /home/linuxbrew/.linuxbrew $HOME/.linuxbrew /usr/local
    if test -x $__brew_prefix/bin/brew
        $__brew_prefix/bin/brew shellenv fish | source
        break
    end
end
set -e __brew_prefix

if set -q HOMEBREW_PREFIX
    test -d $HOMEBREW_PREFIX/opt/postgresql@17/bin; and fish_add_path -ga $HOMEBREW_PREFIX/opt/postgresql@17/bin
    test -d $HOMEBREW_PREFIX/opt/openjdk/bin; and fish_add_path -ga $HOMEBREW_PREFIX/opt/openjdk/bin
end

fish_add_path -ga /usr/local/bin
fish_add_path -ga $HOME/.cargo/bin
fish_add_path -ga $HOME/.local/bin
fish_add_path -ga $HOME/.bun/bin
fish_add_path -ga $HOME/.codeium/windsurf/bin
fish_add_path -ga $HOME/.lmstudio/bin
fish_add_path -ga $HOME/.opencode/bin
fish_add_path -ga $HOME/.antigravity/antigravity/bin

# Self-locate the repo when symlink-installed (path resolve follows the
# link); otherwise honor $CLAUDE_CONFIG_REPO for copy-installed setups.
set -l __this (status filename)
if test -L $__this
    set -l __repo (path resolve (path dirname $__this)/../../..)
    test -d $__repo/bin; and fish_add_path -ga $__repo/bin
else if set -q CLAUDE_CONFIG_REPO
    test -d $CLAUDE_CONFIG_REPO/bin; and fish_add_path -ga $CLAUDE_CONFIG_REPO/bin
end
set -e __this
