#!/usr/bin/env bats
# permission-mode.bats
# Path: tests/permission-mode.bats
#
# Claude Code starts a session in auto mode when no settings file names a
# mode, and a resume never restores bypass. The installer sets user settings'
# permissions.defaultMode to bypassPermissions alongside the shortcuts, so
# every session starts as the shortcuts do, and never overrides a mode the
# user chose.

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

mode_of() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("permissions", {}).get("defaultMode", ""))' "$1"
}

# bats test_tags=unit
@test "a settings file without a mode starts sessions in bypass" {
    printf '{"hooks": {}}\n' >"$SETTINGS_JSON"
    run configure_permission_mode
    [ "$status" -eq 0 ]
    [[ ${output} == *"Sessions start in bypass permissions"* ]]
    [ "$(mode_of "$SETTINGS_JSON")" = "bypassPermissions" ]
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["hooks"] == {}' "$SETTINGS_JSON"
}

# bats test_tags=unit
@test "a mode the user chose stays" {
    printf '{"permissions": {"defaultMode": "auto", "allow": ["Read"]}}\n' >"$SETTINGS_JSON"
    run configure_permission_mode
    [ "$status" -eq 0 ]
    [[ ${output} == *"already set (auto)"* ]]
    [ "$(mode_of "$SETTINGS_JSON")" = "auto" ]
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["permissions"]["allow"] == ["Read"]' "$SETTINGS_JSON"
}

# bats test_tags=unit
@test "rules already there stay beside the mode, and a second run changes nothing" {
    printf '{"permissions": {"deny": ["Read(./.env)"]}}\n' >"$SETTINGS_JSON"
    configure_permission_mode
    cp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
    run configure_permission_mode
    cmp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
    [ "$(mode_of "$SETTINGS_JSON")" = "bypassPermissions" ]
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["permissions"]["deny"] == ["Read(./.env)"]' "$SETTINGS_JSON"
}

# bats test_tags=unit
@test "a settings file that is not JSON is reported and left as it was" {
    printf '{not json\n' >"$SETTINGS_JSON"
    run configure_permission_mode
    [ "$status" -eq 1 ]
    [[ ${output} == *"Failed to set the permission mode"* ]]
    [ "$(cat "$SETTINGS_JSON")" = "{not json" ]
}

# bats test_tags=unit
@test "a permissions value that is not an object is left alone, and setup goes on" {
    for body in '{"permissions": null}' '{"permissions": []}' '[]'; do
        printf '%s\n' "$body" >"$SETTINGS_JSON"
        run configure_permission_mode
        [ "$status" -eq 0 ] || { echo "$body: $output"; return 1; }
        [[ ${output} == *"left alone"* ]]
        [ "$(cat "$SETTINGS_JSON")" = "$body" ]
    done
}

# bats test_tags=unit
@test "the repo's own settings never name a mode: Claude Code ignores bypass there and starts in manual" {
    python3 -c 'import json,sys; assert "defaultMode" not in json.load(open(sys.argv[1])).get("permissions", {})' "${REPO_DIR}/.claude/settings.json"
}

# bats test_tags=unit
@test "as root, outside a sandbox, the mode is left alone: Claude Code would refuse to start" {
    printf '{}\n' >"$SETTINGS_JSON"
    id() { echo 0; }
    run configure_permission_mode
    [ "$status" -eq 0 ]
    [[ ${output} == *"Running as root"* ]]
    [ "$(mode_of "$SETTINGS_JSON")" = "" ]
    IS_SANDBOX=1 run configure_permission_mode
    [ "$(mode_of "$SETTINGS_JSON")" = "bypassPermissions" ]
}

# bats test_tags=unit
@test "both installers run it as its own choice, unless settings are skipped" {
    grep -q '^ *configure_permission_mode$' "${REPO_DIR}/setup.sh"
    grep -q 'INSTALL_BYPASS_DEFAULT}" == "true" && "${SETTINGS_MODE}" != "skip"' "${REPO_DIR}/setup.sh"
    grep -q '^ *Update-PermissionMode$' "${REPO_DIR}/setup.ps1"
    grep -q 'InstallBypassDefault -and $script:SettingsMode -ne "skip"' "${REPO_DIR}/setup.ps1"
}
