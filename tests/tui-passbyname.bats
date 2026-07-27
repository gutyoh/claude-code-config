#!/usr/bin/env bats
# tui-passbyname.bats
# Path: tests/tui-passbyname.bats
#
# The TUI helpers return values by writing to a variable the caller names. That
# was done with bash 4.3 namerefs (`local -n`), which fail at RUNTIME on the
# bash 3.2 macOS ships — and `bash -n` does not catch it, so the scripts parsed
# cleanly and died at the first prompt. They now use `printf -v` for scalars and
# eval for arrays, both of which work on 3.2.
#
# These functions read keystrokes from /dev/tty, so they cannot be driven by a
# pipe; the tests run them under a pty via script(1). Nothing else in the suite
# covers them, which is how the nameref dependency went unnoticed.
#
# Run: bats tests/tui-passbyname.bats

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

# Exercise both helpers and print what the caller's variables ended up holding.
write_driver() {
    cat >"${BATS_TEST_TMPDIR}/driver.sh" <<'DRIVER'
set -euo pipefail
cd "$1"
source lib/setup/tui.sh

choice=""
tui_select choice "Pick:" "alpha" "beta" "gamma" >/dev/null 2>&1
printf 'SELECT=[%s]\n' "$choice"

sel=(0 2); opts=(one two three); descs=(d1 d2 d3); out=()
tui_multiselect out "Choose:" sel opts descs >/dev/null 2>&1
printf 'MULTI=[%s] COUNT=%s\n' "${out[*]:-}" "${#out[@]}"
DRIVER
}

# Enter twice: accept the highlighted option, then confirm the preselection.
run_under_pty() {
    local shell_bin="$1"
    printf '\n\n' | script -q /dev/null "$shell_bin" \
        "${BATS_TEST_TMPDIR}/driver.sh" "$REPO_ROOT" 2>&1
}

assert_results() {
    local output="$1"
    [[ "$output" == *"SELECT=[alpha]"* ]] || {
        echo "tui_select did not write the caller's variable:"
        echo "$output"
        false
    }
    [[ "$output" == *"MULTI=[0 2]"* ]] || {
        echo "tui_multiselect did not round-trip the arrays:"
        echo "$output"
        false
    }
    [[ "$output" == *"COUNT=2"* ]]
}

# bats test_tags=integration,portability
@test "tui helpers return values by name under stock bash 3.2" {
    [ -x /bin/bash ] || skip "no /bin/bash on this platform"
    require_cmd script
    write_driver
    local out
    out="$(run_under_pty /bin/bash)"
    assert_results "$out"
}

# bats test_tags=integration,portability
@test "tui helpers behave identically under the default bash" {
    require_cmd script
    write_driver
    local out
    out="$(run_under_pty "$(command -v bash)")"
    assert_results "$out"
}
