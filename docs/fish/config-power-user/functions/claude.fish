function claude --description 'Claude Code with proxy launcher defaults'
    # Mirrors the zsh `claude` function in ~/.zshrc.
    # Defaults to --allow-dangerously-skip-permissions; opt-in to
    # --dangerously-skip-permissions via the -a / --unsafe / --bypass / -adskp flags.

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
