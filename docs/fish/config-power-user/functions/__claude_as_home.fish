function __claude_as_home --description 'The home a resumed session last ran in'
    # setup.sh installs this natively for a fish login shell; this copy is the
    # reference for a manual/copy install. Keep the two in sync.
    # Prints the home `claude-as --where` names for these claude arguments, or
    # nothing: a session not resumed, one that last ran in ~/.claude, or a
    # CLAUDE_CONFIG_DIR already set. A claude function routes with:
    #   set -l home (__claude_as_home $argv)
    #   test -n "$home"; and set -lx CLAUDE_CONFIG_DIR $home
    set -q CLAUDE_CONFIG_DIR; and return 0
    command -q claude-as; or return 0
    set -l home (command claude-as --where $argv 2>/dev/null)
    or begin
        printf 'claude: claude-as --where failed; running as the default account\n' >&2
        return 0
    end
    test -n "$home"; or return 0
    printf 'claude: as the session last ran, in %s\n' $home >&2
    printf '%s\n' $home
end
