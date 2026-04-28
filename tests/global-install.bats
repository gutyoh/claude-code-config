#!/usr/bin/env bats
# global-install.bats
# Path: tests/global-install.bats
#
# Verifies that bin/claude-proxy works correctly when installed globally
# (symlinked into ~/.local/bin or called from a different cwd).
#
# On macOS/Linux setup.sh installs it as a symlink. On Windows setup.ps1
# writes a bash shim + a .ps1 companion. Both paths route through the real
# repo script, which must be symlink-aware so $ROOT_DIR resolves to the
# repo and NOT to ~/.local (where the siblings don't exist).
#
# Also asserts:
#   - setup.sh contains the claude-proxy symlink block
#   - setup.ps1 contains the bash + PowerShell shim blocks
#
# Run: bats tests/global-install.bats
#      make test

PROXY_BIN="$BATS_TEST_DIRNAME/../bin/claude-proxy"
SETUP_SH="$BATS_TEST_DIRNAME/../setup.sh"
SETUP_PS1="$BATS_TEST_DIRNAME/../setup.ps1"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq required"

    # Install stubs for commands claude-proxy calls at init time
    # (need_cmd claude / curl / nohup). These must be on PATH so the script
    # doesn't exit early before we reach the logic we want to test.
    STUB_DIR="${BATS_TEST_TMPDIR}/stubs"
    mkdir -p "$STUB_DIR"
    for cmd in claude nohup; do
        cat >"${STUB_DIR}/${cmd}" <<STUB
#!/usr/bin/env bash
exit 0
STUB
        chmod +x "${STUB_DIR}/${cmd}"
    done
    cat >"${STUB_DIR}/curl" <<'STUB'
#!/usr/bin/env bash
# Simulate proxy being down so claude-proxy goes to offline registry path
for arg in "$@"; do
    [[ "$arg" == */v1/models ]] && exit 22
done
exit 0
STUB
    chmod +x "${STUB_DIR}/curl"

    export STUBBED_PATH="${STUB_DIR}:${PATH}"
}

# ============================================================================
# Symlink resolution — single and multi-level
# ============================================================================

@test "symlink resolution: single-level symlink resolves to repo" {
    local sym="${BATS_TEST_TMPDIR}/claude-proxy"
    ln -sf "$PROXY_BIN" "$sym"

    # --help exits early and proves the initial `source lib/proxy/preflight.sh`
    # succeeded — which is only possible if ROOT_DIR resolved to the repo.
    run env PATH="$STUBBED_PATH" "$sym" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-proxy"* ]]
    [[ "$output" == *"Run Claude Code against a local proxy"* ]]
}

@test "symlink resolution: symlink in a nested directory still resolves" {
    local sym_dir="${BATS_TEST_TMPDIR}/nested/deeply/bin"
    mkdir -p "$sym_dir"
    ln -sf "$PROXY_BIN" "${sym_dir}/claude-proxy"

    run env PATH="$STUBBED_PATH" "${sym_dir}/claude-proxy" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-proxy"* ]]
}

@test "symlink resolution: multi-level symlink (symlink to symlink)" {
    local hop1="${BATS_TEST_TMPDIR}/hop1/claude-proxy"
    local hop2="${BATS_TEST_TMPDIR}/hop2/claude-proxy"
    mkdir -p "$(dirname "$hop1")" "$(dirname "$hop2")"
    ln -sf "$PROXY_BIN" "$hop1"
    ln -sf "$hop1" "$hop2"

    run env PATH="$STUBBED_PATH" "$hop2" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-proxy"* ]]
}

@test "symlink resolution: relative symlink target is handled" {
    # Real setup.sh uses absolute `ln -sf <abs-target>` paths so this test
    # only covers the narrow case where someone manually creates a relative
    # symlink within the SAME filesystem root. Cross-root relative symlinks
    # (e.g. /tmp -> /private/tmp on macOS) are out of scope because the
    # underlying filesystem resolution breaks before our script even runs.
    local link_dir="${BATS_TEST_TMPDIR}/relative"
    mkdir -p "$link_dir"
    # Place symlink IN the same directory as the real bin/claude-proxy
    # so the relative target is just "./claude-proxy". This exercises the
    # `[[ "$src" != /* ]] && src="$dir/$src"` branch in _resolve_self
    # without fighting macOS's /tmp → /private/tmp symlink.
    local bin_dir
    bin_dir="$(cd "$BATS_TEST_DIRNAME/../bin" && pwd -P)"
    (cd "$bin_dir" && ln -sf "./claude-proxy" "${link_dir}/.not-used-directly" 2>/dev/null || true)
    # Instead create the relative symlink inside bin/ itself
    local sym="${bin_dir}/.test-relative-symlink-$$"
    ln -sf "./claude-proxy" "$sym"
    # Cleanup on test exit
    trap 'rm -f "'"$sym"'"' EXIT

    run env PATH="$STUBBED_PATH" "$sym" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-proxy"* ]]
    rm -f "$sym"
    trap - EXIT
}

# ============================================================================
# Sibling-file resolution via resolved ROOT_DIR
# ============================================================================

@test "sibling lookup: lib/proxy/preflight.sh is sourced when invoked via symlink" {
    # If ROOT_DIR resolves wrong, `source ${ROOT_DIR}/lib/proxy/preflight.sh`
    # at the top of the script fails with "No such file or directory" and
    # under `set -euo pipefail` the whole script exits non-zero BEFORE any
    # output. So a zero exit + visible output is proof that the sourcing
    # succeeded — which requires correct ROOT_DIR resolution via symlink.
    local sym="${BATS_TEST_TMPDIR}/claude-proxy"
    ln -sf "$PROXY_BIN" "$sym"

    run env PATH="$STUBBED_PATH" "$sym" --help
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "sibling lookup: --models via symlink reaches fetch_offline_models" {
    # --models forces the offline path (curl stub returns exit 22). The
    # offline path calls fetch_offline_models which needs CLI_PROXY_DIR to
    # be set. Our export at bin/claude-proxy top defaults it to
    # ~/Documents/dev/CLIProxyAPI. If the real repo exists on the test
    # machine the output will include "offline"; if not, it prints the
    # "Cannot list models" fallback. Either outcome confirms the code path
    # ran successfully via the symlink.
    local sym="${BATS_TEST_TMPDIR}/claude-proxy"
    ln -sf "$PROXY_BIN" "$sym"

    run env PATH="$STUBBED_PATH" "$sym" -p antigravity --models
    [ "$status" -eq 0 ]
    [[ "$output" == *"antigravity"* ]]
}

@test "sibling lookup: validate_model via symlink rejects bogus model" {
    local sym="${BATS_TEST_TMPDIR}/claude-proxy"
    ln -sf "$PROXY_BIN" "$sym"

    run env PATH="$STUBBED_PATH" "$sym" -p antigravity \
        -m "totally-fake-model-xyz-no-way" --no-start
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown model"* ]]
}

# ============================================================================
# Invocation from arbitrary working directory
# ============================================================================

@test "arbitrary cwd: direct invocation from random dir works" {
    # Regression: earlier versions of the script would pick up a relative
    # path if cwd != repo root. Confirm the absolute-path resolution holds.
    local random_cwd="${BATS_TEST_TMPDIR}/some/random/place"
    mkdir -p "$random_cwd"

    run env PATH="$STUBBED_PATH" bash -c "cd '$random_cwd' && '$PROXY_BIN' --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-proxy"* ]]
}

@test "arbitrary cwd: symlink invocation from random dir works" {
    local sym="${BATS_TEST_TMPDIR}/claude-proxy"
    ln -sf "$PROXY_BIN" "$sym"
    local random_cwd="${BATS_TEST_TMPDIR}/elsewhere"
    mkdir -p "$random_cwd"

    run env PATH="$STUBBED_PATH" bash -c "cd '$random_cwd' && '$sym' --help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-proxy"* ]]
}

# ============================================================================
# setup.sh wiring — Unix install path
# ============================================================================

@test "setup.sh: claude-proxy is in the bin/ install list" {
    grep -q "ln -sf \"\${REPO_DIR}/bin/claude-proxy\"" "$SETUP_SH"
}

@test "setup.sh: claude-proxy install block prints success message" {
    grep -q "~/.local/bin/claude-proxy -> \${REPO_DIR}/bin/claude-proxy" "$SETUP_SH"
}

@test "setup.sh: claude-proxy block warns when binary missing" {
    grep -q "bin/claude-proxy not found or not executable" "$SETUP_SH"
}

# ============================================================================
# setup.ps1 wiring — Windows install path (bash shim + PS1 companion)
# ============================================================================

@test "setup.ps1: generates a bash shim for claude-proxy" {
    grep -q "\$shimPath = \"\$binDir\\\\claude-proxy\"" "$SETUP_PS1"
    # Bash shim must use exec to re-exec the real script
    grep -q "exec \"\$bashPath\" \"\`\$@\"" "$SETUP_PS1"
    # Must write with LF (CRLF breaks bash shebang parsing on Windows)
    grep -q "\"\`r\`n\", \"\`n\"" "$SETUP_PS1"
}

@test "setup.ps1: generates a PowerShell companion (.ps1)" {
    grep -q "\$ps1Path = \"\$binDir\\\\claude-proxy.ps1\"" "$SETUP_PS1"
    grep -q "PowerShell companion" "$SETUP_PS1"
}

@test "setup.ps1: PS1 companion body searches PATH before Git Bash install dirs" {
    grep -q "Get-Command bash -ErrorAction SilentlyContinue" "$SETUP_PS1"
    grep -q "ProgramFiles\\\\Git\\\\bin\\\\bash.exe" "$SETUP_PS1"
    grep -q "ProgramFiles(x86)" "$SETUP_PS1"
    grep -q "LOCALAPPDATA\\\\Programs\\\\Git\\\\bin\\\\bash.exe" "$SETUP_PS1"
}

@test "setup.ps1: PS1 companion errors when bash is unfindable" {
    # Must emit a helpful error + nonzero exit if bash isn't present
    grep -q "Install Git for Windows" "$SETUP_PS1"
    grep -q "exit 1" "$SETUP_PS1"
}

# ============================================================================
# Real-world install simulation
# ============================================================================

@test "simulated global install: symlink into fake ~/.local/bin works end-to-end" {
    # Mimic what setup.sh does, but in a sandbox.
    local fake_local_bin="${BATS_TEST_TMPDIR}/fake_home/.local/bin"
    mkdir -p "$fake_local_bin"
    ln -sf "$PROXY_BIN" "${fake_local_bin}/claude-proxy"

    # Now invoke as if from PATH
    run env PATH="${fake_local_bin}:${STUBBED_PATH}" claude-proxy --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-proxy"* ]]
}

@test "simulated global install: symlink + --models integration" {
    local fake_local_bin="${BATS_TEST_TMPDIR}/fake_home/.local/bin"
    mkdir -p "$fake_local_bin"
    ln -sf "$PROXY_BIN" "${fake_local_bin}/claude-proxy"

    run env PATH="${fake_local_bin}:${STUBBED_PATH}" claude-proxy -p codex --models
    [ "$status" -eq 0 ]
    # Offline mode because proxy is "down" (curl stub exits 22).
    # Output should contain offline or cannot-list or a model id from the
    # user's actual CLIProxyAPI registry.
    [[ "$output" == *"codex"* ]] || [[ "$output" == *"Cannot list"* ]] || [[ "$output" == *"offline"* ]]
}
