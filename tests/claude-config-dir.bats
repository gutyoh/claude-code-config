#!/usr/bin/env bats
# claude-config-dir.bats
# Path: tests/claude-config-dir.bats
#
# Claude Code moves its whole home, .claude.json included, to CLAUDE_CONFIG_DIR.
# These pin that the installer and the runtime scripts follow it, and that a
# machine without it sees byte-for-byte the same settings as before.
#
# Run: bats tests/claude-config-dir.bats

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SETUP="${REPO_ROOT}/setup.sh"
}

assert_setup_ok() {
    if [ "$status" -ne 0 ]; then
        echo "setup.sh exited ${status}"
        echo "$output"
        false
    fi
}

# Every hook and statusline command in a settings file, one per line.
settings_commands() {
    jq -r '[.. | objects | .command? // empty] | .[]' "$1"
}

# bats file_tags=unit

@test "unset: config dir is ~/.claude and .claude.json sits beside it" {
    source "$SETUP"
    [ "$CLAUDE_DIR" = "${HOME}/.claude" ]
    [ "$CLAUDE_JSON" = "${HOME}/.claude.json" ]
    [ "$CLAUDE_DIR_REF" = "~/.claude" ]
}

@test "set under HOME: config dir, .claude.json and the ~ spelling follow it" {
    export CLAUDE_CONFIG_DIR="${HOME}/.claude-work/"
    source "$SETUP"
    [ "$CLAUDE_DIR" = "${HOME}/.claude-work" ]
    [ "$CLAUDE_JSON" = "${HOME}/.claude-work/.claude.json" ]
    [ "$CLAUDE_DIR_REF" = "~/.claude-work" ]
}

@test "set with repeated trailing slashes: all are trimmed, as setup.ps1 does" {
    export CLAUDE_CONFIG_DIR="${HOME}/.claude-work//"
    source "$SETUP"
    [ "$CLAUDE_DIR" = "${HOME}/.claude-work" ]
    [ "$CLAUDE_DIR_REF" = "~/.claude-work" ]
}

@test "set to HOME itself: commands use the absolute path" {
    export CLAUDE_CONFIG_DIR="${HOME}"
    source "$SETUP"
    [ "$CLAUDE_DIR_REF" = "${HOME}" ]
}

@test "set outside HOME: commands use the absolute path" {
    export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/elsewhere/cfg"
    source "$SETUP"
    [ "$CLAUDE_DIR_REF" = "${BATS_TEST_TMPDIR}/elsewhere/cfg" ]
}

@test "overwrite keeps the repo settings byte-identical when unset" {
    source "$SETUP"
    local dest="${BATS_TEST_TMPDIR}/settings.json"
    write_repo_settings "${REPO_ROOT}/.claude/settings.json" "$dest"
    cmp "${REPO_ROOT}/.claude/settings.json" "$dest"
}

@test "overwrite rewrites only command paths when set" {
    require_cmd jq
    export CLAUDE_CONFIG_DIR="${HOME}/.claude-work"
    source "$SETUP"
    local dest="${BATS_TEST_TMPDIR}/settings.json"
    write_repo_settings "${REPO_ROOT}/.claude/settings.json" "$dest"

    run settings_commands "$dest"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    ! grep -q '^~/\.claude/' <<<"$output"
    while IFS= read -r cmd; do
        [[ "$cmd" == "~/.claude-work/"* ]] || [[ "$cmd" != "~/"* ]]
    done <<<"$output"

    # Everything except the command strings is unchanged.
    diff <(jq 'del(.. | .command? // empty)' "${REPO_ROOT}/.claude/settings.json") \
        <(jq 'del(.. | .command? // empty)' "$dest")
}

@test "mcp-env-inject reads keys from the config dir" {
    export CLAUDE_CONFIG_DIR="${HOME}/.claude-work"
    mkdir -p "$CLAUDE_CONFIG_DIR"
    printf 'PROBE_FROM_CONFIG_DIR=yes\n' >"${CLAUDE_CONFIG_DIR}/mcp-keys.env"
    run "${REPO_ROOT}/bin/mcp-env-inject" sh -c 'printf "%s" "${PROBE_FROM_CONFIG_DIR:-missing}"'
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]
}

@test "a symlinked shell rc file stays a symlink across reruns" {
    mkdir -p "${HOME}/dotfiles"
    printf '# mine\nexport KEEP=1\n' >"${HOME}/dotfiles/bashrc"
    ln -s "${HOME}/dotfiles/bashrc" "${HOME}/.bashrc"
    export CLAUDE_CONFIG_SHELL=/bin/bash
    source "$SETUP"

    configure_proxy_path >/dev/null
    configure_proxy_path >/dev/null

    [ -L "${HOME}/.bashrc" ]
    grep -q '^export KEEP=1$' "${HOME}/dotfiles/bashrc"
    [ "$(grep -c '^# claude-code-config: claude launch shortcuts$' "${HOME}/dotfiles/bashrc")" -eq 1 ]
}

# bats test_tags=smoke
@test "install under CLAUDE_CONFIG_DIR never touches ~/.claude" {
    require_cmd python3
    require_cmd jq
    export CLAUDE_CONFIG_DIR="${HOME}/.claude-work"

    run "$SETUP" -y --no-mcp --no-opencode --no-proxy-path
    assert_setup_ok

    [ ! -e "${HOME}/.claude" ]
    [ ! -e "${HOME}/.claude.json" ]
    [ -L "${CLAUDE_CONFIG_DIR}/scripts/statusline.sh" ]
    [ "$(readlink "${CLAUDE_CONFIG_DIR}/scripts/statusline.sh")" = "${REPO_ROOT}/.claude/scripts/statusline.sh" ]
    [ "$(jq -r '.statusLine.command' "${CLAUDE_CONFIG_DIR}/settings.json")" = "~/.claude-work/scripts/statusline.sh" ]
    run settings_commands "${CLAUDE_CONFIG_DIR}/settings.json"
    ! grep -q '^~/\.claude/' <<<"$output"
}

# bats test_tags=smoke
@test "install without CLAUDE_CONFIG_DIR keeps the ~/.claude spelling" {
    require_cmd python3
    require_cmd jq

    run "$SETUP" -y --no-mcp --no-opencode --no-proxy-path
    assert_setup_ok

    [ "$(jq -r '.statusLine.command' "${HOME}/.claude/settings.json")" = "~/.claude/scripts/statusline.sh" ]
}
