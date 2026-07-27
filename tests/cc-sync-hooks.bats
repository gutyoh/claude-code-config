#!/usr/bin/env bats
# cc-sync-hooks.bats
# Path: tests/cc-sync-hooks.bats
#
# bats-core tests for the SessionStart/SessionEnd claude-sync hooks
# (cc-sync-pull.sh and cc-sync-push.sh).
#
# Validates:
#   - both scripts exist and are executable
#   - both scripts no-op silently when claude-sync is not on PATH
#   - both scripts consume stdin (Claude Code feeds JSON to hooks via stdin)
#   - settings.json template wires SessionStart -> cc-sync-pull
#                              and SessionEnd   -> cc-sync-push
#
# Run: bats tests/cc-sync-hooks.bats
#      make test

bats_require_minimum_version 1.5.0

SETTINGS="$BATS_TEST_DIRNAME/../.claude/settings.json"
HOOKS_DIR="$BATS_TEST_DIRNAME/../.claude/hooks"
PULL_SCRIPT="$HOOKS_DIR/cc-sync-pull.sh"
PUSH_SCRIPT="$HOOKS_DIR/cc-sync-push.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    require_cmd jq
    isolate_home
}

# Wait up to `timeout` seconds for `pattern` to appear in `file`. Detached work
# is asynchronous by definition, so polling is the only correct way to observe
# it — a fixed sleep is either flaky or slow.
wait_for_log() {
    local file="$1" pattern="$2" timeout="${3:-15}"
    local waited=0
    while [[ "${waited}" -lt "${timeout}" ]]; do
        [[ -f "${file}" ]] && grep -q "${pattern}" "${file}" 2>/dev/null && return 0
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# --- Hook scripts: presence and executability ---

# bats test_tags=unit,sync
@test "cc-sync-pull.sh exists and is executable" {
    [ -f "$PULL_SCRIPT" ]
    [ -x "$PULL_SCRIPT" ]
}

# bats test_tags=unit,sync
@test "cc-sync-push.sh exists and is executable" {
    [ -f "$PUSH_SCRIPT" ]
    [ -x "$PUSH_SCRIPT" ]
}

# --- Hook scripts: graceful no-op when claude-sync absent ---

# bats test_tags=unit,sync
@test "cc-sync-pull.sh exits 0 when claude-sync is not installed" {
    PATH="/usr/bin:/bin" run bash -c "echo '{}' | '$PULL_SCRIPT'"
    [ "$status" -eq 0 ]
}

# bats test_tags=unit,sync
@test "cc-sync-push.sh exits 0 when claude-sync is not installed" {
    PATH="/usr/bin:/bin" run bash -c "echo '{}' | '$PUSH_SCRIPT'"
    [ "$status" -eq 0 ]
}

# --- Settings template wiring ---

# bats test_tags=unit,sync
@test "settings.json template wires SessionStart to cc-sync-pull.sh" {
    local cmd
    cmd=$(jq -r '
        .hooks.SessionStart // []
        | .[].hooks[]?
        | .command // empty
    ' "$SETTINGS" | grep -F "cc-sync-pull.sh" | head -1)
    [ "$cmd" = "~/.claude/hooks/cc-sync-pull.sh" ]
}

# bats test_tags=unit,sync
@test "settings.json template wires SessionEnd to cc-sync-push.sh" {
    local cmd
    cmd=$(jq -r '
        .hooks.SessionEnd // []
        | .[].hooks[]?
        | .command // empty
    ' "$SETTINGS" | grep -F "cc-sync-push.sh" | head -1)
    [ "$cmd" = "~/.claude/hooks/cc-sync-push.sh" ]
}

# bats test_tags=unit,sync
@test "SessionStart hook command uses ~/ absolute path" {
    local cmd
    cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$SETTINGS")
    [[ "$cmd" == "~/"* ]]
}

# bats test_tags=unit,sync
@test "SessionEnd hook command uses ~/ absolute path" {
    local cmd
    cmd=$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$SETTINGS")
    [[ "$cmd" == "~/"* ]]
}

# bats test_tags=unit,sync
@test "SessionStart entries omit matcher (per official hooks reference)" {
    # SessionStart and SessionEnd do not use matchers — their filtering is
    # done via the `source` / `reason` fields, not a tool matcher.
    # Including a matcher does not break Claude Code, but the convention
    # in the official docs is to omit it.
    local with_matcher
    with_matcher=$(jq '
        .hooks.SessionStart // []
        | map(select(has("matcher")))
        | length
    ' "$SETTINGS")
    [ "$with_matcher" -eq 0 ]
}

# bats test_tags=unit,sync
@test "SessionEnd entries omit matcher (per official hooks reference)" {
    local with_matcher
    with_matcher=$(jq '
        .hooks.SessionEnd // []
        | map(select(has("matcher")))
        | length
    ' "$SETTINGS")
    [ "$with_matcher" -eq 0 ]
}

# --- Timeouts ---------------------------------------------------------------
#
# A hook entry without `timeout` is unbounded: Claude Code waits on it for as
# long as it runs. On SessionStart that is time the user spends staring at a
# blank prompt, so the bound is not optional.

# bats test_tags=unit,sync
@test "SessionStart cc-sync-pull entry declares a timeout" {
    local timeout
    timeout=$(jq -r '
        .hooks.SessionStart[]?.hooks[]?
        | select(.command | test("cc-sync-pull"))
        | .timeout // "MISSING"
    ' "$SETTINGS")
    [ "$timeout" != "MISSING" ]
    [ "$timeout" -gt 0 ]
    [ "$timeout" -le 30 ]
}

# bats test_tags=unit,sync
@test "SessionEnd cc-sync-push entry declares a timeout" {
    local timeout
    timeout=$(jq -r '
        .hooks.SessionEnd[]?.hooks[]?
        | select(.command | test("cc-sync-push"))
        | .timeout // "MISSING"
    ' "$SETTINGS")
    [ "$timeout" != "MISSING" ]
    [ "$timeout" -gt 0 ]
    [ "$timeout" -le 30 ]
}

# --- Detachment: the hook must not block the session ------------------------

# bats test_tags=integration,sync
@test "cc-sync-pull returns immediately even when claude-sync is slow" {
    # Regression: an inline `claude-sync pull` added its full network round
    # trip to every session start. The hook must detach instead.
    stub_slow_bin claude-sync 30

    local start end elapsed
    start=$(date +%s)
    run bash -c "echo '{}' | '$PULL_SCRIPT'"
    end=$(date +%s)
    elapsed=$((end - start))

    [ "$status" -eq 0 ]
    [ "$elapsed" -lt 5 ]
}

# bats test_tags=integration,sync
@test "cc-sync-push returns immediately even when claude-sync is slow" {
    stub_slow_bin claude-sync 30

    local start end elapsed
    start=$(date +%s)
    run bash -c "echo '{}' | '$PUSH_SCRIPT'"
    end=$(date +%s)
    elapsed=$((end - start))

    [ "$status" -eq 0 ]
    [ "$elapsed" -lt 5 ]
}

# bats test_tags=integration,sync
@test "cc-sync-push completes its upload after the hook returns" {
    # The whole point of detaching: SessionEnd kills an inline push mid-flight,
    # the remote never advances, and the next pull diverges into .conflict
    # files. The detached child must outlive the hook and finish the upload.
    stub_bin claude-sync 'sleep 2; exit 0'

    run bash -c "echo '{}' | '$PUSH_SCRIPT'"
    [ "$status" -eq 0 ]

    wait_for_log "${HOME}/.claude/cc-sync-push.log" 'push exit=0' 20
}

# bats test_tags=integration,sync
@test "cc-sync-pull logs a completed pull from the detached child" {
    stub_bin claude-sync 'exit 0'

    run bash -c "echo '{}' | '$PULL_SCRIPT'"
    [ "$status" -eq 0 ]

    wait_for_log "${HOME}/.claude/cc-sync-pull.log" 'pull exit=0' 20
}

# --- Blocking mode is bounded ----------------------------------------------

# bats test_tags=integration,sync
@test "cc-sync-pull blocking mode is bounded by CC_SYNC_TIMEOUT_SEC" {
    if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
        skip "GNU timeout not available (brew install coreutils on macOS)"
    fi
    stub_slow_bin claude-sync 60

    local start end elapsed
    start=$(date +%s)
    run bash -c "echo '{}' | CC_SYNC_BLOCKING=1 CC_SYNC_TIMEOUT_SEC=2 '$PULL_SCRIPT'"
    end=$(date +%s)
    elapsed=$((end - start))

    [ "$status" -eq 0 ]
    # 2s timeout + 5s kill grace + slack, and far below the stub's 60s.
    [ "$elapsed" -lt 15 ]
    grep -q 'timed out after 2s' "${HOME}/.claude/cc-sync-pull.log"
}

# --- Installer emits and repairs timeouts -----------------------------------

# bats test_tags=unit,sync
@test "configure_claude_sync_hooks writes entries with a timeout" {
    require_cmd python3
    local settings="${BATS_TEST_TMPDIR}/settings.json"
    echo '{}' >"$settings"
    stub_bin claude-sync 'exit 0'

    run bash -c "
        SETTINGS_JSON='$settings'
        INSTALL_CLAUDE_SYNC=yes
        source '$BATS_TEST_DIRNAME/../lib/setup/settings.sh'
        configure_claude_sync_hooks
    "
    [ "$status" -eq 0 ]

    local pull_timeout
    pull_timeout=$(jq -r '
        .hooks.SessionStart[]?.hooks[]?
        | select(.command | test("cc-sync-pull"))
        | .timeout // "MISSING"
    ' "$settings")
    [ "$pull_timeout" != "MISSING" ]
}

# bats test_tags=unit,sync
@test "configure_claude_sync_hooks upgrades a timeout-less entry in place" {
    require_cmd python3
    local settings="${BATS_TEST_TMPDIR}/settings.json"
    # Shape written by the version of setup.sh that shipped without timeouts.
    cat >"$settings" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "~/.claude/hooks/cc-sync-pull.sh"}]}
    ],
    "SessionEnd": [
      {"hooks": [{"type": "command", "command": "~/.claude/hooks/cc-sync-push.sh"}]}
    ]
  }
}
JSON
    stub_bin claude-sync 'exit 0'

    run bash -c "
        SETTINGS_JSON='$settings'
        INSTALL_CLAUDE_SYNC=yes
        source '$BATS_TEST_DIRNAME/../lib/setup/settings.sh'
        configure_claude_sync_hooks
    "
    [ "$status" -eq 0 ]

    # Repaired in place, not duplicated.
    local count timeout
    count=$(jq '[.hooks.SessionStart[]?.hooks[]? | select(.command | test("cc-sync-pull"))] | length' "$settings")
    [ "$count" -eq 1 ]
    timeout=$(jq -r '.hooks.SessionStart[0].hooks[0].timeout // "MISSING"' "$settings")
    [ "$timeout" != "MISSING" ]
}

# --- Opting out ------------------------------------------------------------

# bats test_tags=unit,sync
@test "customize_installation offers an interactive claude-sync toggle" {
    # The install summary lists claude-sync, but for a while there was no
    # prompt to change it — an interactive user who did not want cross-machine
    # sync had to know the --no-claude-sync flag existed and re-run.
    grep -q 'INSTALL_CLAUDE_SYNC="no"' "$BATS_TEST_DIRNAME/../lib/setup/menu.sh"
    grep -q 'INSTALL_CLAUDE_SYNC="yes"' "$BATS_TEST_DIRNAME/../lib/setup/menu.sh"
}

# bats test_tags=integration,sync
@test "--no-claude-sync installs no hooks even when claude-sync is present" {
    require_cmd python3
    stub_bin claude-sync 'exit 0'
    local repo
    repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    run bash "${repo}/setup.sh" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ]

    local n
    n=$(jq '[.hooks.SessionStart // [], .hooks.SessionEnd // []] | flatten | length' \
        "${HOME}/.claude/settings.json")
    [ "$n" -eq 0 ]
}

# bats test_tags=integration,sync
@test "--no-claude-sync removes hooks a previous run installed" {
    # Opting out has to be reversible, not just preventive: someone who enabled
    # sync and changed their mind should be able to re-run and have the entries
    # taken back out.
    require_cmd python3
    stub_bin claude-sync 'exit 0'
    local repo
    repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    run bash "${repo}/setup.sh" -y --minimal --with-claude-sync --no-opencode
    [ "$status" -eq 0 ]
    local before
    before=$(jq '[.hooks.SessionStart // []] | flatten | length' "${HOME}/.claude/settings.json")
    [ "$before" -gt 0 ]

    run bash "${repo}/setup.sh" -y --minimal --no-claude-sync --no-opencode
    [ "$status" -eq 0 ]
    local after
    after=$(jq '[.hooks.SessionStart // [], .hooks.SessionEnd // []] | flatten | length' \
        "${HOME}/.claude/settings.json")
    [ "$after" -eq 0 ]
}

# bats test_tags=integration,sync
@test "auto mode skips the hooks when claude-sync is not installed" {
    require_cmd python3
    local repo
    repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

    # No claude-sync stub on PATH: auto must resolve to "no".
    run env PATH="/usr/bin:/bin" HOME="$HOME" bash "${repo}/setup.sh" \
        -y --minimal --no-opencode
    [ "$status" -eq 0 ]

    local n
    n=$(jq '[.hooks.SessionStart // [], .hooks.SessionEnd // []] | flatten | length' \
        "${HOME}/.claude/settings.json")
    [ "$n" -eq 0 ]
}

# --- The detached transfer must not be capped -------------------------------
#
# Regression: sync_once() applied run_bounded on BOTH paths, so the detached
# child inherited the 10s startup bound. On any machine with GNU timeout (or
# Homebrew gtimeout) a pull that legitimately runs longer was SIGTERMed every
# session — exit 124, remote never merged. The hook returned fast, so the bug
# looked like a fix: startup was instant and the sync silently never completed.

# bats test_tags=integration,sync
@test "detached pull is NOT killed by the startup timeout" {
    if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
        skip "no timeout binary — nothing could cap the transfer here anyway"
    fi
    # Comfortably longer than the 10s default bound.
    stub_bin claude-sync 'sleep 13; exit 0'

    run bash -c "echo '{}' | '$PULL_SCRIPT'"
    [ "$status" -eq 0 ]

    wait_for_log "${HOME}/.claude/cc-sync-pull.log" 'pull exit=' 40
    run grep -c 'pull exit=0' "${HOME}/.claude/cc-sync-pull.log"
    [ "$output" -ge 1 ] || {
        echo "detached pull did not complete:"
        cat "${HOME}/.claude/cc-sync-pull.log"
        false
    }
    ! grep -q 'pull exit=124' "${HOME}/.claude/cc-sync-pull.log"
}

# bats test_tags=integration,sync
@test "blocking pull is still bounded by CC_SYNC_TIMEOUT_SEC" {
    # The bound has to stay where it matters: blocking mode holds up startup.
    if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
        skip "GNU timeout not available"
    fi
    stub_slow_bin claude-sync 60

    local start end
    start=$(date +%s)
    run bash -c "echo '{}' | CC_SYNC_BLOCKING=1 CC_SYNC_TIMEOUT_SEC=2 '$PULL_SCRIPT'"
    end=$(date +%s)

    [ "$status" -eq 0 ]
    [ $((end - start)) -lt 15 ]
    grep -q 'timed out after 2s' "${HOME}/.claude/cc-sync-pull.log"
}
