function clp --description 'Claude proxy with model'
    # setup.sh installs this natively for a fish login shell; this copy is the
    # reference for a manual/copy install. Keep the two in sync.
    # Starts in bypass permissions like claude; needs __claude_launch_mode.fish.

    set -l model 'gpt-6.1-sol(high)'
    test -n "$CLAUDE_PROXY_MODEL"; and set model $CLAUDE_PROXY_MODEL

    set -l rest $argv
    if contains -- "$argv[1]" -a --yolo --unsafe --bypass -adskp
        set -e rest[1]
    end
    claude-proxy --no-validate -m $model -- (__claude_launch_mode $rest) $rest
end
