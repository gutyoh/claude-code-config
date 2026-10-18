function claude --description 'Claude Code with proxy launcher defaults'
    # setup.sh installs this natively for a fish login shell; this copy is the
    # reference for a manual/copy install. Keep the two in sync.
    # Defaults to --allow-dangerously-skip-permissions; opt-in to
    # --dangerously-skip-permissions via the -a / --unsafe / --bypass / -adskp flags.
    # A resumed session runs as the account it last ran as (__claude_as_home),
    # also when herdr resumes it after a restart, and keeps its own name in
    # Remote Control (claude-as --rc-name).

    set -l home (__claude_as_home $argv)
    # Outside any block: a variable set in one ends with it.
    test -n "$home"; and set -lx CLAUDE_CONFIG_DIR $home

    set -l mode --allow-dangerously-skip-permissions
    set -l rest $argv
    if contains -- "$argv[1]" -a --unsafe --bypass -adskp
        set mode --dangerously-skip-permissions
        set -e rest[1]
    end

    set -l rc_name
    set -l host_alias
    if command -q claude-as
        set rc_name (command claude-as --rc-name $rest 2>/dev/null)
        set host_alias (command claude-as --host-alias 2>/dev/null)
    end
    # In front: an option after a `--` or a prompt would not be read as one.
    test -n "$rc_name"; and set rest --remote-control $rc_name $rest
    # Outside any block, as CLAUDE_CONFIG_DIR above.
    test -z "$CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX"; and test -n "$host_alias"
    and set -lx CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX claude-$host_alias
    command claude $mode $rest
end
