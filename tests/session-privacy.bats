#!/usr/bin/env bats
# session-privacy.bats
# Path: tests/session-privacy.bats
#
# The installer keeps claude.ai session links out of commits and pull requests
# unless the user chose otherwise, and removes a hand-registered stop-nudge
# hook, which the config-hooks plugin now runs.

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

field() {
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(eval(sys.argv[2], {"d": d})))' "$SETTINGS_JSON" "$1"
}

# bats test_tags=unit
@test "a settings file without a choice names no session link" {
    printf '{"model": "opus"}\n' >"$SETTINGS_JSON"
    run configure_session_privacy
    [ "$status" -eq 0 ]
    [ "$(field 'd["attribution"]["sessionUrl"]')" = "false" ]
    [ "$(field 'd["model"]')" = '"opus"' ]
}

# bats test_tags=unit
@test "a choice the user made stays, and other attribution keys too" {
    printf '{"attribution": {"sessionUrl": true, "commit": "x"}}\n' >"$SETTINGS_JSON"
    run configure_session_privacy
    [ "$status" -eq 0 ]
    [ "$(field 'd["attribution"]')" = '{"sessionUrl": true, "commit": "x"}' ]
}

# bats test_tags=unit
@test "a hand-registered stop-nudge hook goes; other Stop hooks stay" {
    cat >"$SETTINGS_JSON" <<'JSON'
{"hooks": {"Stop": [
  {"matcher": "", "hooks": [{"type": "command", "command": "~/.claude/hooks/stop-nudge.sh", "timeout": 10},
                            {"type": "command", "command": "~/bin/notify"}]},
  {"matcher": "", "hooks": [{"type": "command", "command": "/home/example/.claude/hooks/stop-nudge.sh"}]}
], "SessionStart": [{"hooks": [{"type": "command", "command": "x"}]}]}}
JSON
    run configure_session_privacy
    [ "$status" -eq 0 ]
    [[ ${output} == *"Removed a hand-registered stop-nudge hook"* ]]
    [ "$(field '[h["command"] for g in d["hooks"]["Stop"] for h in g["hooks"]]')" = '["~/bin/notify"]' ]
    [ "$(field 'len(d["hooks"]["SessionStart"])')" = "1" ]
}

# bats test_tags=unit
@test "only stop-nudge hooks: the Stop key goes" {
    printf '{"hooks": {"Stop": [{"hooks": [{"command": "~/.claude/hooks/stop-nudge.sh"}]}]}}\n' >"$SETTINGS_JSON"
    configure_session_privacy
    [ "$(field '"Stop" in d["hooks"]')" = "false" ]
}

# bats test_tags=unit
@test "a second run changes nothing" {
    printf '{}\n' >"$SETTINGS_JSON"
    configure_session_privacy
    cp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
    run configure_session_privacy
    cmp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
}

# bats test_tags=unit
@test "setup.sh and setup.ps1 both run it in merge mode" {
    grep -q '^        configure_session_privacy$' "$REPO_DIR/setup.sh"
    grep -q '^    Update-SessionPrivacy$' "$REPO_DIR/setup.ps1"
}
