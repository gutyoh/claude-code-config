function __claude_launch_mode --description 'The permission flag a claude launch adds'
    # setup.sh installs this natively for a fish login shell; this copy is the
    # reference for a manual/copy install. Keep the two in sync.
    # Bypass from the start, or only on Shift+Tab when the arguments before
    # any `--` choose a mode, which --dangerously-skip-permissions would override.
    for arg in $argv
        switch $arg
            case --
                break
            case --permission-mode '--permission-mode=*' --allow-dangerously-skip-permissions --dangerously-skip-permissions
                echo --allow-dangerously-skip-permissions
                return 0
        end
    end
    echo --dangerously-skip-permissions
end
