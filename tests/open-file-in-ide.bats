#!/usr/bin/env bats
# open-file-in-ide.bats
# Path: tests/open-file-in-ide.bats
#
# bats-core tests for .claude/hooks/open-file-in-ide.sh — the PreToolUse hook
# that opens a file in the user's IDE before mcp__ide__getDiagnostics runs
# (JetBrains bug #3085 workaround).
#
# Strategy: PATH-shim both `pgrep` and the IDE command to controlled mocks
# in a per-test TMPDIR. Each mock writes its invocation to a marker file so
# the test can assert which IDE command was chosen.
#
# Run: bats tests/open-file-in-ide.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/open-file-in-ide.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq required"

    # Per-test sandbox for PATH shims and marker files
    STUB_DIR="$(mktemp -d)"
    export STUB_DIR
    MARKER="${STUB_DIR}/ide-invoked"
    export MARKER

    # Clear any explicit IDE preference the dev may have set
    unset CLAUDE_IDE
}

teardown() {
    rm -rf "$STUB_DIR"
}

# --- Helpers ---

# Install a mock command in STUB_DIR that logs its argv to $MARKER.
# The mock exits 0 so the hook believes the IDE opened successfully.
install_mock_ide() {
    local name="$1"
    cat >"${STUB_DIR}/${name}" <<STUB
#!/usr/bin/env bash
printf '%s' "${name}" >"\$MARKER"
for arg in "\$@"; do
    printf ' %s' "\$arg" >>"\$MARKER"
done
printf '\n' >>"\$MARKER"
exit 0
STUB
    chmod +x "${STUB_DIR}/${name}"
}

# Install a pgrep mock that reports the given IDE as "running" (matching
# either pattern_1 or pattern_2 from the hook's IDE_DEFINITIONS).
#
# We emulate pgrep -if <pattern>: exit 0 if pattern matches one of the
# "running" process names we've simulated, else exit 1.
install_pgrep_mock() {
    local running_names="$1"
    cat >"${STUB_DIR}/pgrep" <<STUB
#!/usr/bin/env bash
# Simulated running IDE processes:
RUNNING="${running_names}"
# Parse pgrep args — we only care about -if <pattern>
pattern=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -if|-i|-f|-l|-a) shift ;;
        -*) shift ;;
        *) pattern="\$1"; shift ;;
    esac
done
# Case-insensitive regex match (pgrep -i semantics). The hook's patterns
# include anchors (e.g. "^Code$") so we must use bash regex, not substring.
shopt -s nocasematch
for proc in \$RUNNING; do
    if [[ "\$proc" =~ \$pattern ]]; then
        echo "\$proc"
        exit 0
    fi
done
exit 1
STUB
    chmod +x "${STUB_DIR}/pgrep"
}

# Build the JSON input Claude Code would send.
make_input() {
    local uri="$1"
    jq -n --arg u "$uri" '{ tool_input: { uri: $u } }'
}

# Run the hook with the stub PATH prefixed — stubs win over system tools.
run_hook() {
    local uri="${1:-file:///tmp/fake.py}"
    local input
    input=$(make_input "$uri")
    # Prepend STUB_DIR to PATH. Keep /bin and /usr/bin for jq, sed, etc.
    run bash -c "printf %s '$input' | PATH='${STUB_DIR}:/usr/bin:/bin' bash '$HOOK'"
}

# ============================================================================
# Script basics
# ============================================================================

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "exits 0 when no IDE is running and none installed" {
    install_pgrep_mock ""
    run_hook "file:///tmp/fake.py"
    [ "$status" -eq 0 ]
    [ ! -f "$MARKER" ]
}

# ============================================================================
# Tier 1: CLAUDE_IDE environment variable takes priority
# ============================================================================

@test "CLAUDE_IDE env: explicit preference takes priority over auto-detect" {
    install_mock_ide "code"
    install_pgrep_mock ""  # nothing running
    export CLAUDE_IDE="code"

    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
    [ -f "$MARKER" ]
    grep -q "^code " "$MARKER"
    # VSCode-style invocation should NOT use --line flag
    ! grep -q -- "--line" "$MARKER"
}

@test "CLAUDE_IDE env: JetBrains family uses --line flag" {
    install_mock_ide "pycharm"
    install_pgrep_mock ""
    export CLAUDE_IDE="pycharm"

    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
    [ -f "$MARKER" ]
    grep -q "^pycharm" "$MARKER"
    grep -q -- "--line 1" "$MARKER"
}

@test "CLAUDE_IDE env: nonexistent IDE falls through to auto-detect" {
    install_mock_ide "code"
    install_pgrep_mock "Code"  # Code is "running"
    export CLAUDE_IDE="does-not-exist"

    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
    [ -f "$MARKER" ]
    # Should have fallen through to detected 'code'
    grep -q "^code " "$MARKER"
}

# ============================================================================
# Tier 2: Auto-detect running IDE (process list)
# ============================================================================

@test "auto-detect: picks running VSCode when available" {
    install_mock_ide "code"
    install_pgrep_mock "Code"

    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
    [ -f "$MARKER" ]
    grep -q "^code " "$MARKER"
}

@test "auto-detect: picks running PyCharm when available" {
    install_mock_ide "pycharm"
    install_pgrep_mock "PyCharm"

    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
    [ -f "$MARKER" ]
    grep -q "^pycharm" "$MARKER"
    grep -q -- "--line 1" "$MARKER"
}

@test "auto-detect: prefers VSCode over JetBrains per IDE_DEFINITIONS order" {
    # Both Code and PyCharm are "running" AND both commands exist.
    # The hook iterates IDE_DEFINITIONS in order; code-insiders then code
    # then cursor/windsurf/antigravity then pycharm. So code should win.
    install_mock_ide "code"
    install_mock_ide "pycharm"
    install_pgrep_mock "Code PyCharm"

    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
    grep -q "^code " "$MARKER"
    ! grep -q "^pycharm" "$MARKER"
}

# ============================================================================
# Tier 3: Fallback to first available IDE command
# ============================================================================

@test "fallback: uses first available IDE command when nothing is running" {
    install_mock_ide "pycharm"
    install_pgrep_mock ""  # nothing running

    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
    [ -f "$MARKER" ]
    grep -q "^pycharm" "$MARKER"
}

# ============================================================================
# URI handling
# ============================================================================

@test "strips file:// prefix from URI" {
    install_mock_ide "code"
    install_pgrep_mock "Code"

    run_hook "file:///absolute/path/to/file.py"
    [ "$status" -eq 0 ]
    grep -q "/absolute/path/to/file.py" "$MARKER"
    # Must NOT contain the file:// prefix as an argument
    ! grep -q "file:///" "$MARKER"
}

@test "accepts a bare absolute path (no file:// prefix)" {
    install_mock_ide "code"
    install_pgrep_mock "Code"

    run_hook "/already/absolute/file.py"
    [ "$status" -eq 0 ]
    grep -q "/already/absolute/file.py" "$MARKER"
}

# ============================================================================
# Edge cases / graceful failure
# ============================================================================

@test "no stdin: hook exits (does not hang)" {
    install_pgrep_mock ""
    # No stdin → jq produces empty file_path → tier 2/3 run with empty path
    # → hook exits 0. Add a timeout guard so a regression (hang) fails loudly.
    run timeout 5 bash -c "PATH='${STUB_DIR}:/usr/bin:/bin' bash '$HOOK' </dev/null"
    # Expect either exit 0 (graceful) or jq's non-zero when empty — anything
    # except 124 (timeout) is acceptable. 124 == hung.
    [ "$status" -ne 124 ]
}

@test "malformed JSON: hook does not hang" {
    install_pgrep_mock ""
    run timeout 5 bash -c "echo 'not json' | PATH='${STUB_DIR}:/usr/bin:/bin' bash '$HOOK'"
    [ "$status" -ne 124 ]
}

@test "IDE command exists but pgrep is missing: falls back cleanly" {
    # Remove pgrep mock — system pgrep will likely say nothing runs
    install_mock_ide "code"
    # No install_pgrep_mock call. Hook's pgrep calls silently fail, should
    # fall through to tier 3 which finds installed 'code'.
    run_hook "file:///tmp/foo.py"
    [ "$status" -eq 0 ]
}

# ============================================================================
# Performance
# ============================================================================

@test "hook completes in < 2s when no IDE is installed" {
    install_pgrep_mock ""
    local start end elapsed
    start=$("${_PY}" -c "import time; print(int(time.time() * 1000))")
    run_hook "file:///tmp/foo.py"
    end=$("${_PY}" -c "import time; print(int(time.time() * 1000))")
    elapsed=$((end - start))
    # Fast path (no IDE found) — no sleep should fire. < 2s is generous.
    [ "$elapsed" -lt 2000 ]
}
