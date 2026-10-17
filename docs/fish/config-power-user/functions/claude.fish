function claude --description 'Claude Code with proxy launcher defaults'
    # setup.sh installs this natively for a fish login shell; this copy is the
    # reference for a manual/copy install. Keep the two in sync.
    # Defaults to --allow-dangerously-skip-permissions; opt-in to
    # --dangerously-skip-permissions via the -a / --unsafe / --bypass / -adskp flags.
    # A resumed session runs as the account it last ran as (claude-as
    # --where), also when herdr resumes it after a restart.

    set -l home
    if not set -q CLAUDE_CONFIG_DIR; and command -q claude-as
        set home (command claude-as --where $argv 2>/dev/null)
    end
    # Outside any block: a variable set in one ends with it.
    test -n "$home"; and set -lx CLAUDE_CONFIG_DIR $home
    and printf 'claude: as the session last ran, in %s\n' $home >&2

    set -l first ""
    test (count $argv) -gt 0; and set first $argv[1]

    switch $first
        case -a --unsafe --bypass -adskp
            set -l rest
            test (count $argv) -gt 1; and set rest $argv[2..-1]
            command claude --dangerously-skip-permissions $rest
        case '*'
            command claude --allow-dangerously-skip-permissions $argv
    end
end
