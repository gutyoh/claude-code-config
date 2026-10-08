#!/usr/bin/env bats
# claude-permissions-audit.bats
# Path: tests/claude-permissions-audit.bats
#
# Tests for bin/claude-permissions-audit: detection, secret masking, --fix
# backups and rewrites, JSON shape, exit codes and directory pruning. Every
# fixture lives in a throwaway HOME; the secrets are fake.
#
# Run: bats tests/claude-permissions-audit.bats

# bats file_tags=unit

bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../bin/claude-permissions-audit"
FAKE_PW="hunter2-example-pw"
FAKE_TOKEN="example-token-0123456789abcdef"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    require_cmd jq
    unset CLAUDE_PERMS_ROOTS CLAUDE_CONFIG_DIR
    PROJ="${HOME}/work/sample-app"
    SETTINGS="${PROJ}/.claude/settings.local.json"
    mkdir -p "${PROJ}/.claude"
}

# write_json <path> -- JSON from stdin, creating parent directories.
write_json() {
    mkdir -p "$(dirname "$1")"
    cat >"$1"
}

# The standard fixture: one rule of every category plus look-alikes that must
# NOT be flagged, and non-permission keys that --fix must leave alone.
write_fixture() {
    write_json "${SETTINGS}" <<EOF
{
  "permissions": {
    "allow": [
      "Bash(git * main)",
      "Bash(npm run test:*)",
      "Bash(ls *)",
      "Bash(PGPASSWORD=${FAKE_PW} psql -h db.example.test -U app)",
      "Bash(curl -H \"Authorization: Bearer ${FAKE_TOKEN}\" https://api.example.test)",
      "Bash(npm run test:*)",
      "Bash(rm *)",
      "Bash(mkdir -p /tmp/example/build)",
      "Bash(export GH_TOKEN=\$(gh auth token))",
      "Bash(grep -rn password src/)",
      "Bash(docker run -u 1000:1000 example-image)",
      "Read(//tmp/**)"
    ],
    "deny": ["Bash(git push *)"]
  },
  "env": {"EXAMPLE_FLAG": "1"},
  "model": "example-model"
}
EOF
}

audit_json() {
    run --separate-stderr bash "$SCRIPT" --json "$@"
}

# --- Basics -----------------------------------------------------------------

@test "script exists, is executable and prints help" {
    [ -x "$SCRIPT" ]
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-permissions-audit [options] [ROOT...]"* ]]
}

@test "a clean tree exits 0" {
    write_json "${SETTINGS}" <<'EOF'
{"permissions": {"allow": ["Bash(npm run test:*)", "Bash(ls *)", "Read(//tmp/**)"]}}
EOF
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"settings.local.json: rules=3 mid_wildcard=0 secret_like=0 broad=0 duplicates=0"* ]]
}

@test "findings exit 1 with one count line per file" {
    write_fixture
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"~/work/sample-app/.claude/settings.local.json: rules=12 mid_wildcard=1 secret_like=2 broad=1 duplicates=1"* ]]
    [[ "$output" == *"total: files=1 rules=12"* ]]
}

# --- Detection --------------------------------------------------------------

@test "a wildcard before the end of a Bash rule is flagged" {
    write_fixture
    audit_json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.files[0].mid_wildcard == ["Bash(git * main)"]'
}

@test "a trailing * or :* is not flagged" {
    write_json "${SETTINGS}" <<'EOF'
{"permissions": {"allow": ["Bash(ls *)", "Bash(npm run test:*)", "Bash(git log *)", "Bash(* --version)", "Bash(git:* main)"]}}
EOF
    audit_json
    echo "$output" | jq -e '.files[0].mid_wildcard == ["Bash(* --version)", "Bash(git:* main)"]'
}

@test "common look-alikes are not flagged as secrets" {
    write_fixture
    audit_json
    echo "$output" | jq -e '.files[0].secret_like | length == 2'
    echo "$output" | jq -e '[.files[0].secret_like[] | select(test("mkdir|GH_TOKEN|grep|docker"))] | length == 0'
}

@test "secret shapes beyond env assignments are detected" {
    write_json "${SETTINGS}" <<EOF
{"permissions": {"allow": [
  "Bash(curl -u admin:${FAKE_PW} https://api.example.test)",
  "Bash(psql postgresql://app:${FAKE_PW}@db.example.test/app)",
  "Bash(mysql -uroot -p${FAKE_PW} app)",
  "Bash(tool login --password ${FAKE_PW})",
  "Bash(curl https://api.example.test/v1?api_key=${FAKE_TOKEN})"
]}}
EOF
    audit_json
    echo "$output" | jq -e '.files[0].secret_like | length == 5'
}

@test "overly broad allows are reported" {
    write_json "${SETTINGS}" <<'EOF'
{"permissions": {"allow": ["Bash", "Bash(*)", "Bash(sudo *)", "Bash(python3:*)", "Bash(rm -rf build)", "Bash(curl https://example.test)"]}}
EOF
    audit_json
    echo "$output" | jq -e '.files[0].broad == ["Bash", "Bash(*)", "Bash(sudo *)", "Bash(python3:*)"]'
}

@test "exact duplicates are counted once each extra copy" {
    write_json "${SETTINGS}" <<'EOF'
{"permissions": {"allow": ["Bash(make test)", "Bash(make test)", "Bash(make test)", "Bash(make lint)"]}}
EOF
    audit_json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.files[0].duplicates == ["Bash(make test)", "Bash(make test)"]'
}

# --- Masking ----------------------------------------------------------------

@test "a secret never appears in any output mode" {
    write_fixture
    local mode
    for mode in "" "--verbose" "--json" "--dry-run" "--dry-run --json"; do
        # shellcheck disable=SC2086 # mode is a flag list
        run bash "$SCRIPT" $mode
        [[ "$output" != *"${FAKE_PW}"* ]] || {
            echo "password leaked with '${mode}'"
            false
        }
        [[ "$output" != *"${FAKE_TOKEN}"* ]] || {
            echo "token leaked with '${mode}'"
            false
        }
    done
    run bash "$SCRIPT" --fix
    [[ "$output" != *"${FAKE_PW}"* ]]
    [[ "$output" != *"${FAKE_TOKEN}"* ]]
}

@test "masking cuts before a secret that starts inside the first 24 chars" {
    write_fixture
    run bash "$SCRIPT" --verbose
    [[ "$output" == *"secret-like   Bash(PGPASSWORD=…[masked]"* ]]
    [[ "$output" == *"secret-like   Bash(curl -H \"Authorizat…[masked]"* ]]
}

# --- --fix / --dry-run ------------------------------------------------------

@test "--dry-run lists removals and writes nothing" {
    write_fixture
    cp "${SETTINGS}" "${BATS_TEST_TMPDIR}/before.json"
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"would remove 4:"* ]]
    cmp -s "${SETTINGS}" "${BATS_TEST_TMPDIR}/before.json"
    [ ! -e "${HOME}/.claude/backups" ]
}

@test "--fix removes mid-wildcard, secret and duplicate rules and keeps the rest" {
    write_fixture
    run bash "$SCRIPT" --fix
    [[ "$output" == *"removed 4 (backup: ~/.claude/backups/permissions/"* ]]
    jq -e . "${SETTINGS}" >/dev/null
    jq -e '.permissions.allow == [
        "Bash(npm run test:*)", "Bash(ls *)", "Bash(rm *)",
        "Bash(mkdir -p /tmp/example/build)", "Bash(export GH_TOKEN=$(gh auth token))",
        "Bash(grep -rn password src/)", "Bash(docker run -u 1000:1000 example-image)",
        "Read(//tmp/**)"]' "${SETTINGS}"
    jq -e '.permissions.deny == ["Bash(git push *)"]' "${SETTINGS}"
    jq -e '.env == {"EXAMPLE_FLAG": "1"} and .model == "example-model"' "${SETTINGS}"
    run grep -c "${FAKE_PW}" "${SETTINGS}"
    [ "$output" = "0" ]
}

@test "--fix backs up the original with owner-only permissions" {
    write_fixture
    cp "${SETTINGS}" "${BATS_TEST_TMPDIR}/before.json"
    run bash "$SCRIPT" --fix
    local dir backup
    dir="$(find "${HOME}/.claude/backups/permissions" -mindepth 1 -maxdepth 1 -type d)"
    [ -n "$dir" ]
    backup="${dir}/$(printf '%s' "${SETTINGS#/}" | tr '/' '_')"
    [ -f "$backup" ]
    cmp -s "$backup" "${BATS_TEST_TMPDIR}/before.json"
    [ "$(file_mode "$backup")" = "600" ]
    [ "$(file_mode "$dir")" = "700" ]
}

@test "--fix exits 1 while broad rules remain and 0 once clean" {
    write_fixture
    run bash "$SCRIPT" --fix
    [ "$status" -eq 1 ]
    write_json "${SETTINGS}" <<'EOF'
{"permissions": {"allow": ["Bash(git * main)", "Bash(ls *)"]}}
EOF
    run bash "$SCRIPT" --fix
    [ "$status" -eq 0 ]
    jq -e '.permissions.allow == ["Bash(ls *)"]' "${SETTINGS}"
}

@test "--fix leaves untouched files without a backup" {
    write_json "${SETTINGS}" <<'EOF'
{"permissions": {"allow": ["Bash(ls *)"]}}
EOF
    run bash "$SCRIPT" --fix
    [ "$status" -eq 0 ]
    [ ! -e "${HOME}/.claude/backups" ]
}

@test "--fix rewrites through a symlink instead of replacing it" {
    local real="${HOME}/dotfiles/settings.local.json"
    write_json "$real" <<'EOF'
{"permissions": {"allow": ["Bash(git * main)", "Bash(ls *)"]}}
EOF
    ln -s "$real" "${SETTINGS}"
    run bash "$SCRIPT" --fix
    [ -L "${SETTINGS}" ]
    jq -e '.permissions.allow == ["Bash(ls *)"]' "$real"
}

# --- JSON shape -------------------------------------------------------------

@test "--json reports mode, files, errors and totals" {
    write_fixture
    audit_json
    echo "$output" | jq -e '
        .mode == "audit"
        and (.files | length) == 1
        and (.files[0] | has("path") and has("rules") and has("mid_wildcard")
             and has("secret_like") and has("broad") and has("duplicates"))
        and (.files[0] | has("removed") | not)
        and .errors == []
        and .totals == {files: 1, rules: 12, mid_wildcard: 1, secret_like: 2, broad: 1, duplicates: 1}'
}

@test "--dry-run --json carries the removal list" {
    write_fixture
    audit_json --dry-run
    echo "$output" | jq -e '.mode == "dry-run" and .totals.removed == 4'
    echo "$output" | jq -e '[.files[0].removed[].category] == ["mid-wildcard", "secret-like", "secret-like", "duplicate"]'
}

# --- Errors -----------------------------------------------------------------

@test "an unknown option exits 2" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown option: --bogus"* ]]
}

@test "a root that is not a directory exits 2" {
    run bash "$SCRIPT" "${HOME}/does-not-exist"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a directory"* ]]
}

@test "an invalid settings file is reported and exits 2" {
    write_fixture
    mkdir -p "${HOME}/work/broken/.claude"
    printf '{ not json' >"${HOME}/work/broken/.claude/settings.json"
    run --separate-stderr bash "$SCRIPT" --json
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"broken/.claude/settings.json: unreadable or invalid JSON"* ]]
    echo "$output" | jq -e '(.errors | length) == 1 and .totals.files == 1'
}

# --- Discovery --------------------------------------------------------------

@test "node_modules, .worktrees and .git are skipped" {
    write_fixture
    local d
    for d in node_modules/pkg .worktrees/feature .git/modules/sub; do
        write_json "${PROJ}/${d}/.claude/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(git * main)"]}}
EOF
    done
    audit_json
    echo "$output" | jq -e '.totals.files == 1'
}

@test "dot-directories directly under HOME are skipped only when HOME is the root" {
    write_fixture
    write_json "${HOME}/.tool-state/clone/.claude/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(git * main)"]}}
EOF
    audit_json
    echo "$output" | jq -e '.totals.files == 1'
    audit_json "${HOME}/.tool-state"
    echo "$output" | jq -e '.totals.files == 1 and .totals.mid_wildcard == 1'
}

@test "user settings are scanned even outside the given roots" {
    write_json "${HOME}/.claude/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(git * main)"]}}
EOF
    mkdir -p "${BATS_TEST_TMPDIR}/elsewhere"
    audit_json "${BATS_TEST_TMPDIR}/elsewhere"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.totals.files == 1 and .totals.mid_wildcard == 1'
}

@test "CLAUDE_PERMS_ROOTS selects the roots when none are given" {
    write_fixture
    write_json "${BATS_TEST_TMPDIR}/other/repo/.claude/settings.json" <<'EOF'
{"permissions": {"allow": ["Bash(make test)"]}}
EOF
    CLAUDE_PERMS_ROOTS="${BATS_TEST_TMPDIR}/other" audit_json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.totals.files == 1 and .totals.rules == 1'
}

# bats test_tags=portability
@test "runs under stock macOS bash 3.2" {
    [ -x /bin/bash ] || skip "no /bin/bash on this platform"
    write_fixture
    run /bin/bash "$SCRIPT" --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"would remove 4:"* ]]
}

@test "setup.sh installs the tool into ~/.local/bin" {
    local setup_sh="$BATS_TEST_DIRNAME/../setup.sh"
    grep -q 'ln -sf "${REPO_DIR}/bin/claude-permissions-audit" "${bin_dir}/claude-permissions-audit"' "$setup_sh"
}

# --- Tracked files ------------------------------------------------------------

# PROJ as a git repository; settings.local.json is committed unless ignored.
git_project() {
    git -C "${PROJ}" init -q
    if [[ "${1:-}" == "ignore" ]]; then
        printf '.claude/settings.local.json\n' >"${PROJ}/.gitignore"
    fi
    git -C "${PROJ}" add -A
    git -C "${PROJ}" -c user.name=T -c user.email=t@example.invalid commit -qm init
}

@test "--fix leaves a git-tracked settings file byte-identical and says why" {
    write_fixture
    git_project
    cp "${SETTINGS}" "${BATS_TEST_TMPDIR}/before.json"
    run bash "$SCRIPT" --fix "${HOME}/work"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tracked by git: 4 left unchanged (--include-tracked rewrites it)"* ]]
    [[ "$output" == *"removed=0"* ]]
    cmp "${BATS_TEST_TMPDIR}/before.json" "${SETTINGS}"
    [ -z "$(git -C "${PROJ}" status --porcelain)" ]
    [ ! -d "${HOME}/.claude/backups/permissions" ]
}

@test "--fix --include-tracked rewrites a tracked file, with a backup" {
    write_fixture
    git_project
    run bash "$SCRIPT" --fix --include-tracked "${HOME}/work"
    [[ "$output" == *"removed 4 (backup:"* ]]
    ! grep -q "${FAKE_PW}" "${SETTINGS}"
    [ -n "$(git -C "${PROJ}" status --porcelain)" ]
}

@test "--dry-run reports a tracked file as left unchanged" {
    write_fixture
    git_project
    run bash "$SCRIPT" --dry-run "${HOME}/work"
    [[ "$output" == *"tracked by git: 4 left unchanged"* ]]
    [[ "$output" == *"would_remove=0"* ]]
}

@test "--fix still cleans a settings file the repository ignores" {
    write_fixture
    git_project ignore
    run bash "$SCRIPT" --fix "${HOME}/work"
    [[ "$output" == *"removed 4 (backup:"* ]]
    [[ "$output" != *"tracked by git"* ]]
    ! grep -q "${FAKE_PW}" "${SETTINGS}"
    [ -z "$(git -C "${PROJ}" status --porcelain)" ]
}

@test "--json marks how many rules a tracked file kept" {
    write_fixture
    git_project
    audit_json --dry-run "${HOME}/work"
    [ "$(jq '.files[0].tracked_held' <<<"$output")" -eq 4 ]
    [ "$(jq '.files[0].removed | length' <<<"$output")" -eq 0 ]
}
