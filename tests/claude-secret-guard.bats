#!/usr/bin/env bats
# claude-secret-guard.bats
# Path: tests/claude-secret-guard.bats
#
# Tests for bin/claude-secret-guard: off by default, on adds exactly its rules
# once, off removes exactly them, other keys and rules survive both, backups,
# a symlinked settings file, CLAUDE_CONFIG_DIR, and refusal on bad JSON. Every
# fixture lives in a throwaway HOME.
#
# Run: bats tests/claude-secret-guard.bats

# bats file_tags=unit

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../bin/claude-secret-guard"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    require_cmd jq
    SETTINGS="${HOME}/.claude/settings.json"
    mkdir -p "${HOME}/.claude"
}

rule_count() { "${SCRIPT}" list | wc -l | tr -d ' '; }

@test "off by default: with no settings file the guard is off and nothing is written" {
    run "${SCRIPT}" status
    [ "$status" -eq 0 ]
    [ "$output" = "off" ]
    [ ! -e "${SETTINGS}" ]
}

@test "status is the default subcommand" {
    run "${SCRIPT}"
    [ "$status" -eq 0 ]
    [ "$output" = "off" ]
}

@test "on adds every rule to permissions.deny" {
    echo '{}' >"${SETTINGS}"
    run "${SCRIPT}" on
    [ "$status" -eq 0 ]
    [[ "$output" == *"secret guard: on"* ]]
    [ "$(jq '.permissions.deny | length' "${SETTINGS}")" -eq "$(rule_count)" ]
    jq -e '.permissions.deny | index("Read(~/.oci/**)")' "${SETTINGS}" >/dev/null
}

@test "on twice adds nothing the second time" {
    echo '{}' >"${SETTINGS}"
    "${SCRIPT}" on >/dev/null
    run "${SCRIPT}" on
    [ "$status" -eq 0 ]
    [ "$(jq '.permissions.deny | length' "${SETTINGS}")" -eq "$(rule_count)" ]
    [[ "$output" != *"backup:"* ]]
}

@test "on keeps other keys and the user's own allow and deny rules, in place" {
    cat >"${SETTINGS}" <<'EOF'
{"env": {"EXAMPLE": "1"}, "permissions": {"allow": ["Bash(ls *)"], "deny": ["Bash(git push *)"], "defaultMode": "acceptEdits"}, "theme": "dark"}
EOF
    "${SCRIPT}" on >/dev/null
    [ "$(jq -r '.env.EXAMPLE' "${SETTINGS}")" = "1" ]
    [ "$(jq -r '.theme' "${SETTINGS}")" = "dark" ]
    [ "$(jq -r '.permissions.defaultMode' "${SETTINGS}")" = "acceptEdits" ]
    [ "$(jq -r '.permissions.allow[0]' "${SETTINGS}")" = "Bash(ls *)" ]
    [ "$(jq -r '.permissions.deny[0]' "${SETTINGS}")" = "Bash(git push *)" ]
}

@test "off removes only the guard's rules and keeps the user's deny rule" {
    cat >"${SETTINGS}" <<'EOF'
{"permissions": {"deny": ["Bash(git push *)"]}}
EOF
    "${SCRIPT}" on >/dev/null
    run "${SCRIPT}" off
    [ "$status" -eq 0 ]
    [[ "$output" == *"secret guard: off"* ]]
    [ "$(jq -c '.permissions.deny' "${SETTINGS}")" = '["Bash(git push *)"]' ]
}

@test "on then off returns a file to exactly what it was" {
    cat >"${SETTINGS}" <<'EOF'
{"env": {"A": "1"}, "statusLine": {"type": "command", "command": "x"}}
EOF
    before=$(jq -S . "${SETTINGS}")
    "${SCRIPT}" on >/dev/null
    "${SCRIPT}" off >/dev/null
    [ "$(jq -S . "${SETTINGS}")" = "${before}" ]
}

@test "off with the guard already off changes nothing and makes no backup" {
    echo '{"theme": "dark"}' >"${SETTINGS}"
    run "${SCRIPT}" off
    [ "$status" -eq 0 ]
    [[ "$output" != *"backup:"* ]]
    [ ! -d "${HOME}/.claude/backups/permissions" ]
    [ "$(jq -c . "${SETTINGS}")" = '{"theme":"dark"}' ]
}

@test "a partial set reads as partial, and on completes it" {
    echo '{"permissions": {"deny": ["Read(~/.oci/**)", "Read(~/.azure/**)"]}}' >"${SETTINGS}"
    run "${SCRIPT}" status
    [ "$output" = "partial (2/$(rule_count))" ]
    "${SCRIPT}" on >/dev/null
    run "${SCRIPT}" status
    [ "$output" = "on" ]
    [ "$(jq '.permissions.deny | length' "${SETTINGS}")" -eq "$(rule_count)" ]
}

@test "every change is backed up first, privately" {
    echo '{"theme": "dark"}' >"${SETTINGS}"
    run "${SCRIPT}" on
    backup=$(sed -n 's/^backup: //p' <<<"$output")
    [ -f "${backup}" ]
    [ "$(jq -c . "${backup}")" = '{"theme":"dark"}' ]
    mode=$(stat -c %a "${backup}" 2>/dev/null || stat -f %Lp "${backup}")
    [ "${mode}" = "600" ]
}

@test "the settings file keeps its mode" {
    echo '{}' >"${SETTINGS}"
    chmod 644 "${SETTINGS}"
    "${SCRIPT}" on >/dev/null
    mode=$(stat -c %a "${SETTINGS}" 2>/dev/null || stat -f %Lp "${SETTINGS}")
    [ "${mode}" = "644" ]
}

@test "a symlinked settings.json is updated at its target and stays a link" {
    mkdir -p "${HOME}/profiles"
    echo '{}' >"${HOME}/profiles/settings.json"
    rm -f "${SETTINGS}"
    ln -s "${HOME}/profiles/settings.json" "${SETTINGS}"
    "${SCRIPT}" on >/dev/null
    [ -L "${SETTINGS}" ]
    [ "$(jq '.permissions.deny | length' "${HOME}/profiles/settings.json")" -eq "$(rule_count)" ]
}

@test "CLAUDE_CONFIG_DIR picks the profile it edits" {
    mkdir -p "${HOME}/.claude-work"
    echo '{}' >"${HOME}/.claude-work/settings.json"
    echo '{}' >"${SETTINGS}"
    CLAUDE_CONFIG_DIR="${HOME}/.claude-work" "${SCRIPT}" on >/dev/null
    [ "$(jq '.permissions.deny | length' "${HOME}/.claude-work/settings.json")" -eq "$(rule_count)" ]
    [ "$(jq -c . "${SETTINGS}")" = '{}' ]
}

@test "invalid JSON is refused and left untouched" {
    printf '{ not json' >"${SETTINGS}"
    run "${SCRIPT}" on
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a JSON object"* ]]
    [ "$(cat "${SETTINGS}")" = "{ not json" ]
}

@test "an unknown subcommand prints usage and exits 2" {
    run "${SCRIPT}" enable
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "the rules cover the credential paths and only Read rules" {
    run "${SCRIPT}" list
    [ "$status" -eq 0 ]
    for p in '~/.oci/**' '~/.ssh/id_*' '~/.config/fnox/age.txt' '~/.azure/**' '~/.config/gh/hosts.yml'; do
        [[ "$output" == *"Read(${p})"* ]]
    done
    ! grep -qv '^Read(' <<<"$output"
}
