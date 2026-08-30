#!/usr/bin/env bats
# bash-tool-shell.bats
# Path: tests/bash-tool-shell.bats
#
# Claude Code's Bash tool runs the system shell, not the login shell, and zsh
# does not word-split unquoted parameters the way bash does — so a bash-shaped
# command collapses into one argument silently instead of erroring. The
# installer pins CLAUDE_CODE_SHELL so the exec shell is the same everywhere,
# whatever the user logs in with.

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd python3
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    SETTINGS_JSON="${BATS_TEST_TMPDIR}/settings.json"
    export SETTINGS_JSON
    # shellcheck source=../lib/setup/settings.sh
    source "${REPO_DIR}/lib/setup/settings.sh"
}

pinned_shell() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("env",{}).get("CLAUDE_CODE_SHELL",""))' "$1"
}

write_settings() {
    printf '%s\n' "$1" >"$SETTINGS_JSON"
}

# --- Resolution ------------------------------------------------------------

# bats test_tags=unit,shell
@test "pins CLAUDE_CODE_SHELL to an executable bash" {
    write_settings '{}'
    run configure_bash_shell
    [ "$status" -eq 0 ]

    local shell
    shell="$(pinned_shell "$SETTINGS_JSON")"
    [ -n "$shell" ]
    [ -x "$shell" ]
    run "$shell" -c 'echo "$BASH_VERSION"'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# bats test_tags=unit,shell
@test "prefers the newest bash among the candidates present" {
    # macOS ships /bin/bash 3.2 for licensing reasons and Homebrew installs a
    # 5.x beside it. Picking the first match instead of the newest would hand
    # the Bash tool the 3.2 and silently lose every post-3.2 builtin.
    write_settings '{}'
    run configure_bash_shell
    [ "$status" -eq 0 ]

    local chosen chosen_major other_major
    chosen="$(pinned_shell "$SETTINGS_JSON")"
    chosen_major="$("$chosen" -c 'echo "${BASH_VERSINFO[0]}"')"

    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash; do
        [ -x "$candidate" ] || continue
        other_major="$("$candidate" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)"
        [ "$chosen_major" -ge "$other_major" ]
    done
}

# bats test_tags=unit,shell
@test "the resolved shell actually word-splits, which zsh does not" {
    # This is the whole point of the pin, so assert the behaviour and not just
    # the path: an unquoted parameter must expand to four arguments.
    write_settings '{}'
    run configure_bash_shell
    [ "$status" -eq 0 ]

    local shell
    shell="$(pinned_shell "$SETTINGS_JSON")"
    run "$shell" -c 'V="-o A=1 -o B=2"; set -- $V; echo "$#"'
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

# --- Idempotence and preservation ------------------------------------------

# bats test_tags=unit,shell
@test "running twice is idempotent" {
    write_settings '{}'
    run configure_bash_shell
    [ "$status" -eq 0 ]
    local first
    first="$(pinned_shell "$SETTINGS_JSON")"

    run configure_bash_shell
    [ "$status" -eq 0 ]
    [[ "$output" == *"already pinned"* ]]
    [ "$(pinned_shell "$SETTINGS_JSON")" = "$first" ]
}

# bats test_tags=unit,shell
@test "preserves unrelated env keys and top-level settings" {
    write_settings '{"model":"opus","env":{"KEEP_ME":"yes"},"theme":"dark"}'
    run configure_bash_shell
    [ "$status" -eq 0 ]

    run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["model"], d["theme"], d["env"]["KEEP_ME"])' "$SETTINGS_JSON"
    [ "$status" -eq 0 ]
    [ "$output" = "opus dark yes" ]
}

# bats test_tags=unit,shell
@test "creates the env block when the file has none" {
    write_settings '{"model":"opus"}'
    run configure_bash_shell
    [ "$status" -eq 0 ]
    [ -n "$(pinned_shell "$SETTINGS_JSON")" ]
}

# bats test_tags=unit,shell
@test "overwrites a stale pin pointing at a shell that is gone" {
    write_settings '{"env":{"CLAUDE_CODE_SHELL":"/nonexistent/bin/bash"}}'
    run configure_bash_shell
    [ "$status" -eq 0 ]

    local shell
    shell="$(pinned_shell "$SETTINGS_JSON")"
    [ "$shell" != "/nonexistent/bin/bash" ]
    [ -x "$shell" ]
}

# bats test_tags=unit,shell
@test "leaves the file valid JSON" {
    write_settings '{"model":"opus","env":{"KEEP_ME":"yes"}}'
    run configure_bash_shell
    [ "$status" -eq 0 ]
    run python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS_JSON"
    [ "$status" -eq 0 ]
}

# --- Wiring ----------------------------------------------------------------

# bats test_tags=unit,shell
@test "setup.sh pins the shell on both the merge and overwrite paths" {
    # An overwrite resets env to the shipped template, so it needs the pin just
    # as much as a merge does.
    local calls
    calls="$(grep -c '^ *configure_bash_shell$' "${REPO_DIR}/setup.sh")"
    [ "$calls" -eq 2 ]
}

# bats test_tags=unit,shell,portability
@test "the candidate list offers a non-Apple-Silicon prefix" {
    # /opt/homebrew is Apple-Silicon-only; a list naming it alone would resolve
    # to nothing on Intel macOS and on Linux.
    grep -q '/opt/homebrew/bin/bash' "${REPO_DIR}/lib/setup/settings.sh"
    grep -q '/usr/local/bin/bash' "${REPO_DIR}/lib/setup/settings.sh"
    grep -q '/usr/bin/bash' "${REPO_DIR}/lib/setup/settings.sh"
}

# bats test_tags=unit,shell
@test "pinning survives a settings file that already pins the same shell" {
    write_settings '{}'
    run configure_bash_shell
    local shell
    shell="$(pinned_shell "$SETTINGS_JSON")"

    write_settings "{\"env\":{\"CLAUDE_CODE_SHELL\":\"${shell}\"}}"
    run configure_bash_shell
    [ "$status" -eq 0 ]
    [ "$(pinned_shell "$SETTINGS_JSON")" = "$shell" ]
}
