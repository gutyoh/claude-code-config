#!/usr/bin/env bats
# smoke.bats
# Path: tests/smoke.bats
#
# End-to-end checks that the installer actually runs on a clean machine.
# The unit lane mocks aggressively and can stay green while the real entry
# point is broken; these drive setup.sh itself against a throwaway HOME.
#
# Deliberately narrow: no MCP servers, no network, no agents. The question is
# "does the installer run to completion and leave a usable config", not "is
# every feature correct" — the unit and integration lanes answer that.
#
# Run: bats tests/smoke.bats
#      just smoke

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    SETUP="${REPO_DIR}/setup.sh"
}

# setup.sh is a few hundred lines of install logic; a bare status check tells
# you the assertion failed and nothing about why. Surface the output so a CI
# failure is diagnosable from the log alone.
assert_setup_ok() {
    if [ "$status" -ne 0 ]; then
        echo "setup.sh exited ${status}"
        echo "--- output ---"
        echo "$output"
        false
    fi
}

# bats test_tags=smoke
@test "setup.sh --help exits 0 and prints usage" {
    run "$SETUP" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: setup.sh"* ]]
}

# bats test_tags=smoke
@test "setup.sh rejects an unknown flag" {
    run "$SETUP" --definitely-not-a-flag
    [ "$status" -ne 0 ]
}

# bats test_tags=smoke
@test "setup.sh --minimal completes against an empty HOME" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-opencode
    assert_setup_ok
    [[ "$output" == *"Setup complete!"* ]]
}

# bats test_tags=smoke
@test "setup.sh --minimal produces valid settings.json" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-opencode
    assert_setup_ok

    local settings="${HOME}/.claude/settings.json"
    [ -f "$settings" ]
    jq -e '.' "$settings" >/dev/null
}

# bats test_tags=smoke
@test "setup.sh --minimal installs no automatic session-sync hooks" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-opencode
    assert_setup_ok

    local settings="${HOME}/.claude/settings.json"
    local hooks
    hooks=$(jq -r '[.hooks.SessionStart // [], .hooks.SessionEnd // []] | flatten | length' "$settings")
    [ "$hooks" -eq 0 ]
}

# bats test_tags=smoke
@test "setup.sh is idempotent across two runs" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --minimal --no-opencode
    assert_setup_ok
    run "$SETUP" -y --minimal --no-opencode
    assert_setup_ok

    jq -e '.' "${HOME}/.claude/settings.json" >/dev/null
}

# bats test_tags=smoke
# bats test_tags=smoke
@test "the shipped settings.json template is valid JSON" {
    require_cmd jq
    jq -e '.' "${REPO_DIR}/.claude/settings.json" >/dev/null
}

# bats test_tags=smoke
@test "every shipped hook script is syntactically valid bash" {
    local f
    for f in "${REPO_DIR}"/.claude/hooks/*.sh; do
        [ -f "$f" ] || continue
        run bash -n "$f"
        [ "$status" -eq 0 ] || {
            echo "syntax error in $f"
            false
        }
    done
}

# --- Optional prerequisites must not abort the install ----------------------

# bats test_tags=smoke
@test "check_prerequisite: a missing OPTIONAL tool returns success" {
    # Regression: the function returned 1 for an absent optional tool. setup.sh
    # runs under `set -e` and every call site is a bare statement, so the whole
    # install aborted the moment fd/fzf/ccusage were missing — the normal state
    # on a machine that never installed the extras. It failed silently right
    # after "Checking prerequisites..." with no error of its own.
    run bash -c "
        source '${REPO_DIR}/lib/setup/filesystem.sh'
        check_prerequisite 'definitely-not-a-real-binary' 'fake' 'false' 'optional: for tests'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

# bats test_tags=smoke
@test "check_prerequisite: a missing REQUIRED tool still aborts" {
    run bash -c "
        source '${REPO_DIR}/lib/setup/filesystem.sh'
        check_prerequisite 'definitely-not-a-real-binary' 'fake' 'true' ''
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot continue"* ]]
}

# bats test_tags=smoke
@test "setup.sh --minimal completes with only core tools on PATH" {
    # The clean-machine case: no fd, no fzf, no ccusage, no brew tools.
    require_cmd python3
    require_cmd jq
    run env HOME="${BATS_TEST_TMPDIR}/barehome" PATH="/usr/bin:/bin" \
        bash "$SETUP" -y --minimal --no-claude-sync --no-opencode
    assert_setup_ok
    [[ "$output" == *"Setup complete!"* ]]
}
