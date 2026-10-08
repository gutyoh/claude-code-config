#!/usr/bin/env bats
# setup-parity.bats
# Path: tests/setup-parity.bats
#
# setup.sh and setup.ps1 are two front doors to one installer. Every option one
# accepts the other must accept too, or a documented flag silently does nothing
# on half the platforms. Compares the parsers themselves, not the help text.
#
# Run: bats tests/setup-parity.bats

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# Options as setup.sh's parser spells them, normalized to lowercase, no dashes.
bash_options() {
    grep -oE '^[[:space:]]+(-[a-z][[:space:]]*\|[[:space:]]*)?--[a-z][a-z-]*\)' "$REPO_ROOT/lib/setup/cli.sh" |
        grep -oE -- '--[a-z][a-z-]*' | sed 's/^--//' |
        # Unix-only by nature (picks the login shell's rc file), and retired
        # switches kept only so old invocations fail loudly.
        grep -vxE 'shell|with-claude-sync|no-claude-sync' |
        tr -d '-' | sort -u
}

# Parameters setup.ps1 declares, from its AST so common parameters stay out.
ps_options() {
    pwsh -NoProfile -NonInteractive -Command "
        \$ast = [System.Management.Automation.Language.Parser]::ParseFile('$REPO_ROOT/setup.ps1', [ref]\$null, [ref]\$null)
        \$ast.ParamBlock.Parameters | ForEach-Object { \$_.Name.VariablePath.UserPath }
    " | tr -d '\r' | tr '[:upper:]' '[:lower:]' | sort -u
}

# bats test_tags=unit,portability
@test "setup.sh and setup.ps1 accept the same options" {
    require_cmd pwsh
    local diff_out
    diff_out="$(diff <(bash_options) <(ps_options) || true)"
    [ -z "$diff_out" ] || {
        echo "< only setup.sh, > only setup.ps1:"
        echo "$diff_out"
        false
    }
}

# bats test_tags=smoke
@test "setup.ps1 -Help exits 0 under pwsh on this platform" {
    require_cmd pwsh
    run pwsh -NoProfile -NonInteractive -File "$REPO_ROOT/setup.ps1" -Help
    [ "$status" -eq 0 ]
    [[ "$output" == *"setup.ps1"* ]]
}
