#!/usr/bin/env bats
# fish-config-syntax.bats
# Path: tests/fish-config-syntax.bats
#
# Syntax-checks every fish file shipped under docs/fish/config-power-user/.
# Uses `fish --no-execute` which parses without running — catches typos,
# missing `end`, bad option flags. Skips when fish isn't installed (the
# repo is bash-centric; fish is only relevant on machines that adopt the
# preset).
#
# Run: bats tests/fish-config-syntax.bats
#      make test

FISH_DIR="$BATS_TEST_DIRNAME/../docs/fish/config-power-user"

setup() {
    command -v fish >/dev/null 2>&1 || skip "fish not installed"
}

@test "config.fish parses without errors" {
    fish --no-execute "$FISH_DIR/config.fish"
}

@test "all conf.d/*.fish files parse without errors" {
    for f in "$FISH_DIR"/conf.d/*.fish; do
        run fish --no-execute "$f"
        [ "$status" -eq 0 ] || {
            echo "Syntax error in $f:"
            echo "$output"
            return 1
        }
    done
}

@test "all functions/*.fish files parse without errors" {
    for f in "$FISH_DIR"/functions/*.fish; do
        run fish --no-execute "$f"
        [ "$status" -eq 0 ] || {
            echo "Syntax error in $f:"
            echo "$output"
            return 1
        }
    done
}

@test "tide-setup scripts parse without errors" {
    for f in "$FISH_DIR"/setup-tide-*.fish; do
        run fish --no-execute "$f"
        [ "$status" -eq 0 ] || {
            echo "Syntax error in $f:"
            echo "$output"
            return 1
        }
    done
}
