# 00-paths.fish — PATH additions (loaded before everything else)
#
# Uses fish_add_path per fish 4.6 docs.
# -g = global scope (only this shell's children inherit, not universal)
# -p = prepend (takes priority)
# -a = append (lowest priority)

# Prepend essentials (these win over system PATH)
fish_add_path -gp $HOME/bin
fish_add_path -gp /opt/homebrew/bin
fish_add_path -gp /opt/homebrew/sbin

# Append everything else (idempotent — fish dedupes)
fish_add_path -ga /usr/local/bin
fish_add_path -ga /opt/homebrew/opt/postgresql@17/bin
fish_add_path -ga /opt/homebrew/opt/openjdk/bin
fish_add_path -ga $HOME/.cargo/bin
fish_add_path -ga $HOME/.local/bin
fish_add_path -ga $HOME/.bun/bin
fish_add_path -ga $HOME/.codeium/windsurf/bin
fish_add_path -ga $HOME/.lmstudio/bin
fish_add_path -ga $HOME/.opencode/bin
fish_add_path -ga $HOME/.antigravity/antigravity/bin
fish_add_path -ga /Users/guty/Documents/dev/claude-code-config/bin
