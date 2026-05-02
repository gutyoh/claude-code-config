function clp --description 'Claude proxy with model'
    # Mirrors the zsh `clp` function in ~/.zshrc.

    set -l model 'gpt-5.5(high)'
    test -n "$CLAUDE_PROXY_MODEL"; and set model $CLAUDE_PROXY_MODEL

    set -l first ""
    test (count $argv) -gt 0; and set first $argv[1]

    switch $first
        case -a --unsafe --bypass -adskp
            set -l rest
            test (count $argv) -gt 1; and set rest $argv[2..-1]
            claude-proxy --no-validate -m $model -- --dangerously-skip-permissions $rest
        case '*'
            claude-proxy --no-validate -m $model -- --allow-dangerously-skip-permissions $argv
    end
end
