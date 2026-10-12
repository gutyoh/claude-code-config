#!/usr/bin/env bats
# transcript-retention.bats
# Path: tests/transcript-retention.bats
#
# Claude Code deletes session transcripts after 30 days by default, and with
# them every conversation `--resume` could reopen. The installer keeps them for
# a century on every path, and never overrides a period the user chose.

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

retention() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("cleanupPeriodDays",""))' "$1"
}

# bats test_tags=unit
@test "a settings file without a period gets a century" {
    printf '{"hooks": {}}\n' >"$SETTINGS_JSON"
    run configure_transcript_retention
    [ "$status" -eq 0 ]
    [ "$(retention "$SETTINGS_JSON")" = "36500" ]
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["hooks"] == {}' "$SETTINGS_JSON"
}

# bats test_tags=unit
@test "a period the user chose stays" {
    printf '{"cleanupPeriodDays": 90}\n' >"$SETTINGS_JSON"
    run configure_transcript_retention
    [ "$status" -eq 0 ]
    [ "$(retention "$SETTINGS_JSON")" = "90" ]
}

# bats test_tags=unit
@test "a second run changes nothing" {
    printf '{}\n' >"$SETTINGS_JSON"
    configure_transcript_retention
    cp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
    run configure_transcript_retention
    cmp "$SETTINGS_JSON" "${BATS_TEST_TMPDIR}/first.json"
}

# bats test_tags=unit
@test "fresh, merged and overwritten settings all keep transcripts" {
    write_default_settings "$SETTINGS_JSON"
    [ "$(retention "$SETTINGS_JSON")" = "36500" ]
    [ "$(retention "${REPO_DIR}/.claude/settings.json")" = "36500" ]
    grep -q '^ *configure_transcript_retention$' "${REPO_DIR}/setup.sh"
    grep -q '^ *Update-TranscriptRetention$' "${REPO_DIR}/setup.ps1"
    grep -q 'cleanupPeriodDays = 36500' "${REPO_DIR}/setup.ps1"
}
