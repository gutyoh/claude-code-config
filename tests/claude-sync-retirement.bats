#!/usr/bin/env bats
# claude-sync-retirement.bats
# Path: tests/claude-sync-retirement.bats
#
# Regression coverage for retiring automatic ~/.claude file synchronization.
# Live session journals are not safe multi-writer sync inputs. The installer
# must never recreate the old hooks and must remove entries from older installs.

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd jq
    isolate_home
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    SETUP="${REPO_DIR}/setup.sh"
}

sync_hook_count() {
    jq '[
        .hooks.SessionStart[]?.hooks[]?,
        .hooks.SessionEnd[]?.hooks[]?
        | select(.command == "~/.claude/hooks/cc-sync-pull.sh"
            or .command == "~/.claude/hooks/cc-sync-push.sh")
    ] | length' "$1"
}

# bats test_tags=unit,sync
@test "the shipped settings template contains no claude-sync hooks" {
    [ "$(sync_hook_count "${REPO_DIR}/.claude/settings.json")" -eq 0 ]
}

# bats test_tags=unit,sync
@test "automatic claude-sync hook scripts are no longer shipped" {
    [ ! -e "${REPO_DIR}/.claude/hooks/cc-sync-pull.sh" ]
    [ ! -e "${REPO_DIR}/.claude/hooks/cc-sync-push.sh" ]
}

# bats test_tags=unit,sync
@test "the interactive installer offers native Remote Control, not file sync" {
    grep -q 'Claude Remote Control (native)' "${REPO_DIR}/lib/setup/menu.sh"
	run ! grep -q 'Install claude-sync session hooks' "${REPO_DIR}/lib/setup/menu.sh"
	[ "$status" -ne 0 ]
}

# bats test_tags=unit,sync
@test "the retired opt-in flag fails with migration guidance" {
    run "$SETUP" --with-claude-sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"was retired"* ]]
    [[ "$output" == *"claude --remote-control"* ]]
}

# bats test_tags=integration,sync
@test "default setup does not enable sync even when claude-sync is installed" {
    require_cmd python3
    stub_bin claude-sync 'exit 0'

    run "$SETUP" -y --minimal --no-opencode
    [ "$status" -eq 0 ] || {
        echo "$output"
        false
    }

    [ "$(sync_hook_count "${HOME}/.claude/settings.json")" -eq 0 ]
}

# bats test_tags=integration,sync
@test "setup removes legacy entries while preserving neighboring hooks" {
    require_cmd python3
    mkdir -p "${HOME}/.claude"
    cp "${REPO_DIR}/.claude/settings.json" "${HOME}/.claude/settings.json"
    python3 - "${HOME}/.claude/settings.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    data = json.load(handle)

hooks = data.setdefault("hooks", {})
hooks["SessionStart"] = [{
    "hooks": [
        {"type": "command", "command": "~/.claude/hooks/cc-sync-pull.sh"},
        {"type": "command", "command": "~/.claude/hooks/keep-start.sh"},
    ]
}]
hooks["SessionEnd"] = [{
    "hooks": [
        {"type": "command", "command": "~/.claude/hooks/cc-sync-push.sh"},
        {"type": "command", "command": "~/.claude/hooks/keep-end.sh"},
    ]
}]

with open(path, "w") as handle:
    json.dump(data, handle, indent=2)
PY

    run "$SETUP" -y --minimal --no-opencode
    [ "$status" -eq 0 ] || {
        echo "$output"
        false
    }

    local settings="${HOME}/.claude/settings.json"
    [ "$(sync_hook_count "$settings")" -eq 0 ]
    [ "$(jq '[.hooks.SessionStart[]?.hooks[]? | select(.command == "~/.claude/hooks/keep-start.sh")] | length' "$settings")" -eq 1 ]
    [ "$(jq '[.hooks.SessionEnd[]?.hooks[]? | select(.command == "~/.claude/hooks/keep-end.sh")] | length' "$settings")" -eq 1 ]
}

# bats test_tags=integration,sync
@test "the historical no-sync flag remains a compatible no-op" {
    require_cmd python3

    run "$SETUP" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ] || {
        echo "$output"
        false
    }
    [ "$(sync_hook_count "${HOME}/.claude/settings.json")" -eq 0 ]
}
