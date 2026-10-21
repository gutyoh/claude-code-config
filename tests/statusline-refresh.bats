#!/usr/bin/env bats
# statusline-refresh.bats
# Path: tests/statusline-refresh.bats
#
# The statusline redraws on events only unless refreshInterval is set, so an
# idle session froze its countdowns and never saw usage other sessions spent.
# The installer sets it for this repository's statusline, never for another.

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd python3
    isolate_home
    # Never the real Keychain: a lookup there can raise an administrator
    # prompt or read a real login.
    stub_bin security 'exit 44'
    REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_DIR
    SETTINGS_JSON="${BATS_TEST_TMPDIR}/settings.json"
    export SETTINGS_JSON
    # shellcheck source=../lib/setup/settings.sh
    source "${REPO_DIR}/lib/setup/settings.sh"
}

field() {
    python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("statusLine",{}).get(sys.argv[2]); print("" if v is None else v)' "$1" "$2"
}

# bats test_tags=unit
@test "a new statusline refreshes every 60s" {
    printf '{"hooks": {}}\n' >"$SETTINGS_JSON"
    run configure_statusline
    [ "$status" -eq 0 ]
    [ "$(field "$SETTINGS_JSON" refreshInterval)" = "60" ]
    [ "$(field "$SETTINGS_JSON" command)" = "~/.claude/scripts/statusline.sh" ]
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["hooks"] == {}' "$SETTINGS_JSON"
}

# bats test_tags=unit
@test "an existing statusline of this repository gains the interval" {
    printf '{"statusLine": {"type": "command", "command": "~/.claude/scripts/statusline.sh", "padding": 0}}\n' >"$SETTINGS_JSON"
    run configure_statusline
    [ "$status" -eq 0 ]
    [[ "$output" == *"refreshes every 60s"* ]]
    [ "$(field "$SETTINGS_JSON" refreshInterval)" = "60" ]
    [ "$(field "$SETTINGS_JSON" padding)" = "0" ]
}

# bats test_tags=unit
@test "an interval the user chose stays" {
    printf '{"statusLine": {"type": "command", "command": "~/.claude/scripts/statusline.sh", "refreshInterval": 5}}\n' >"$SETTINGS_JSON"
    run configure_statusline
    [ "$status" -eq 0 ]
    [ "$(field "$SETTINGS_JSON" refreshInterval)" = "5" ]
}

# bats test_tags=unit
@test "another statusline is left alone" {
    printf '{"statusLine": {"type": "command", "command": "npx ccstatusline"}}\n' >"$SETTINGS_JSON"
    run configure_statusline
    [ "$status" -eq 0 ]
    [ -z "$(field "$SETTINGS_JSON" refreshInterval)" ]
    [ "$(field "$SETTINGS_JSON" command)" = "npx ccstatusline" ]
}

# bats test_tags=unit
@test "running twice changes nothing the second time" {
    printf '{}\n' >"$SETTINGS_JSON"
    configure_statusline >/dev/null
    cp "$SETTINGS_JSON" "$BATS_TEST_TMPDIR/first.json"
    run configure_statusline
    [[ "$output" == *"already configured"* ]]
    cmp "$SETTINGS_JSON" "$BATS_TEST_TMPDIR/first.json"
}

# bats test_tags=unit
@test "the shipped settings refresh the statusline" {
    [ "$(field "$REPO_DIR/.claude/settings.json" refreshInterval)" = "60" ]
}
