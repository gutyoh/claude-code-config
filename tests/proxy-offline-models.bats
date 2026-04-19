#!/usr/bin/env bats
# proxy-offline-models.bats
# Path: tests/proxy-offline-models.bats
#
# Unit tests for fetch_offline_models() and the offline fallback path in
# bin/claude-proxy. Uses a sandboxed CLI_PROXY_DIR with a controlled
# models.json so we assert exact offline-registry behavior independent
# of whatever the user's real CLIProxyAPI clone contains.
#
# Run: bats tests/proxy-offline-models.bats
#      make test

PROXY_BIN="$BATS_TEST_DIRNAME/../bin/claude-proxy"
PREFLIGHT="$BATS_TEST_DIRNAME/../lib/proxy/preflight.sh"

# Minimal models.json that mirrors the shape CLIProxyAPI uses.
# Includes antigravity and all four codex plan tiers.
FAKE_MODELS_JSON='{
  "antigravity": [
    { "id": "fake-antigravity-1", "object": "model" },
    { "id": "fake-antigravity-2", "object": "model" },
    { "id": "gemini-3-pro-high", "object": "model" }
  ],
  "codex-free": [
    { "id": "gpt-5.2", "object": "model" },
    { "id": "gpt-5.3-codex", "object": "model" }
  ],
  "codex-plus": [
    { "id": "gpt-5.2", "object": "model" },
    { "id": "gpt-5.3-codex", "object": "model" },
    { "id": "gpt-5.3-codex-spark", "object": "model" },
    { "id": "gpt-5.4", "object": "model" }
  ],
  "codex-pro": [
    { "id": "gpt-5.4-mini", "object": "model" }
  ],
  "codex-team": []
}'

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq required"

    # Sandbox a fake CLIProxyAPI repo
    SANDBOX="$(mktemp -d)"
    export SANDBOX
    export CLI_PROXY_DIR="${SANDBOX}/fake-cliproxyapi"
    mkdir -p "${CLI_PROXY_DIR}/internal/registry/models"
    echo "$FAKE_MODELS_JSON" >"${CLI_PROXY_DIR}/internal/registry/models/models.json"
}

teardown() {
    rm -rf "$SANDBOX"
}

# --- Helpers ---

# Source the script's functions into the current shell (like proxy-preflight
# does). Keeps tests fast (no subprocess per call) and lets us call the
# internal helpers directly.
source_proxy_functions() {
    # shellcheck disable=SC1090
    source "$PREFLIGHT"
    # Replay just the function definitions from bin/claude-proxy. We can't
    # source the whole script because it runs main() at the bottom. Instead,
    # extract the function body region (before `# --- Init ---`).
    local tmp
    tmp=$(mktemp)
    awk '/^# --- Init ---/{exit} {print}' "$PROXY_BIN" >"$tmp"
    # shellcheck disable=SC1090
    source "$tmp"
    rm -f "$tmp"
}

# Run the real bin/claude-proxy with stubbed curl/claude/nohup.
# Args: $1 = body of the curl stub (e.g. 'exit 22' or 'echo {...}')
#       rest = args to claude-proxy
_run_proxy() {
    local curl_body="$1"; shift
    local stub_dir="${SANDBOX}/stubs"
    mkdir -p "$stub_dir"

    cat >"$stub_dir/claude" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat >"$stub_dir/nohup" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    cat >"$stub_dir/curl" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do
    if [[ "\$arg" == */v1/models ]]; then
        ${curl_body}
        exit \$?
    fi
    if [[ "\$arg" == */v1/messages ]]; then
        echo "200"
        exit 0
    fi
done
exit 0
STUB
    chmod +x "$stub_dir"/*

    PATH="$stub_dir:$PATH" run "$PROXY_BIN" "$@"
}

# ============================================================================
# fetch_offline_models — the new offline-registry helper
# ============================================================================

@test "fetch_offline_models: returns antigravity models from the sandbox" {
    source_proxy_functions
    local out
    out=$(fetch_offline_models "antigravity" "$CLI_PROXY_DIR")
    [ $? -eq 0 ]
    echo "$out" | grep -qx "fake-antigravity-1"
    echo "$out" | grep -qx "fake-antigravity-2"
    echo "$out" | grep -qx "gemini-3-pro-high"
}

@test "fetch_offline_models: codex profile unions all four plan tiers" {
    source_proxy_functions
    local out
    out=$(fetch_offline_models "codex" "$CLI_PROXY_DIR")
    [ $? -eq 0 ]
    # Every tier must contribute at least one unique model
    echo "$out" | grep -qx "gpt-5.2"                 # codex-free + codex-plus
    echo "$out" | grep -qx "gpt-5.3-codex-spark"     # codex-plus only
    echo "$out" | grep -qx "gpt-5.4"                 # codex-plus
    echo "$out" | grep -qx "gpt-5.4-mini"            # codex-pro
}

@test "fetch_offline_models: deduplicates models across tiers" {
    source_proxy_functions
    local out
    out=$(fetch_offline_models "codex" "$CLI_PROXY_DIR")
    # gpt-5.2 appears in both codex-free and codex-plus in the fixture
    local count
    count=$(echo "$out" | grep -cx "gpt-5.2")
    [ "$count" -eq 1 ]
}

@test "fetch_offline_models: returns 1 when repo dir is missing" {
    source_proxy_functions
    run fetch_offline_models "codex" "${SANDBOX}/does-not-exist"
    [ "$status" -eq 1 ]
}

@test "fetch_offline_models: returns 1 when models.json is missing" {
    source_proxy_functions
    rm -f "${CLI_PROXY_DIR}/internal/registry/models/models.json"
    run fetch_offline_models "codex"
    [ "$status" -eq 1 ]
}

@test "fetch_offline_models: returns 1 on malformed JSON (graceful)" {
    source_proxy_functions
    echo "this is not json" >"${CLI_PROXY_DIR}/internal/registry/models/models.json"
    run fetch_offline_models "codex"
    [ "$status" -eq 1 ]
}

@test "fetch_offline_models: returns 1 for unknown profile" {
    source_proxy_functions
    run fetch_offline_models "unknown-profile" "$CLI_PROXY_DIR"
    [ "$status" -eq 1 ]
}

@test "fetch_offline_models: missing tier section does not crash" {
    # codex-team is empty in the fixture; the union must still work.
    source_proxy_functions
    local out
    out=$(fetch_offline_models "codex" "$CLI_PROXY_DIR")
    [ $? -eq 0 ]
    [ -n "$out" ]
}

@test "fetch_offline_models: completely empty sections return 1 (no models)" {
    source_proxy_functions
    cat >"${CLI_PROXY_DIR}/internal/registry/models/models.json" <<'EOF'
{ "antigravity": [], "codex-free": [], "codex-plus": [], "codex-pro": [], "codex-team": [] }
EOF
    run fetch_offline_models "codex"
    [ "$status" -eq 1 ]
}

@test "fetch_offline_models: env CLI_PROXY_DIR used when \$2 omitted" {
    source_proxy_functions
    # CLI_PROXY_DIR is already exported by setup(). Call without explicit arg.
    local out
    out=$(fetch_offline_models "antigravity")
    [ $? -eq 0 ]
    echo "$out" | grep -qx "fake-antigravity-1"
}

# ============================================================================
# End-to-end via bin/claude-proxy --models (offline fallback is exercised)
# ============================================================================

@test "--models offline: shows antigravity models from sandbox" {
    _run_proxy 'exit 22' -p antigravity --models
    [ "$status" -eq 0 ]
    [[ "$output" == *"offline"* ]]
    [[ "$output" == *"fake-antigravity-1"* ]]
    [[ "$output" == *"fake-antigravity-2"* ]]
    # Helpful default hint must still appear
    [[ "$output" == *"claude-opus-4-6-thinking"* ]]
}

@test "--models offline: shows codex models from sandbox" {
    _run_proxy 'exit 22' -p codex --models
    [ "$status" -eq 0 ]
    [[ "$output" == *"offline"* ]]
    [[ "$output" == *"gpt-5.3-codex-spark"* ]]
    [[ "$output" == *"gpt-5.4-mini"* ]]
    # Default + efforts hint
    [[ "$output" == *"gpt-5.3-codex(high)"* ]]
    [[ "$output" == *"minimal"* ]]
}

@test "--models: empty registry yields 'Cannot list' message, not empty list" {
    cat >"${CLI_PROXY_DIR}/internal/registry/models/models.json" <<'EOF'
{ "antigravity": [] }
EOF
    _run_proxy 'exit 22' -p antigravity --models
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cannot list models"* ]]
    [[ "$output" == *"not reachable"* || "$output" == *"registry not found"* ]]
}

@test "--models: missing repo yields 'Cannot list' message" {
    rm -rf "$CLI_PROXY_DIR"
    _run_proxy 'exit 22' -p codex --models
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cannot list models"* ]]
    [[ "$output" == *"registry not found"* ]]
}

# ============================================================================
# Validation path also uses the offline registry
# ============================================================================

@test "validate_model: accepts fixture-only model when proxy is down" {
    # fake-antigravity-1 only exists in our sandbox models.json (never in
    # upstream CLIProxyAPI). The offline path must still accept it.
    _run_proxy 'exit 22' -p antigravity -m "fake-antigravity-1"
    [ "$status" -eq 0 ]
}

@test "validate_model: rejects unknown model when proxy is down" {
    _run_proxy 'exit 22' -p antigravity -m "truly-bogus-model"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown model"* ]]
}

@test "validate_model: live proxy wins over sandbox offline registry" {
    # Proxy advertises ONLY "live-only-model". Sandbox has others. The
    # live list must take priority — unknown model should fail even though
    # sandbox might accept it.
    _run_proxy 'echo "{\"data\":[{\"id\":\"live-only-model\"}]}"' \
        -p antigravity -m "fake-antigravity-1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown model"* ]]
}

@test "validate_model: accepts live-only model the sandbox doesn't know" {
    _run_proxy 'echo "{\"data\":[{\"id\":\"live-only-model\"}]}"' \
        -p antigravity -m "live-only-model"
    [ "$status" -eq 0 ]
}

@test "validate_model: codex effort xhigh accepted (no per-model gate)" {
    _run_proxy 'exit 22' -p codex -m "gpt-5.3-codex(xhigh)"
    [ "$status" -eq 0 ]
}

@test "validate_model: codex effort minimal accepted" {
    _run_proxy 'exit 22' -p codex -m "gpt-5.2(minimal)"
    [ "$status" -eq 0 ]
}

@test "validate_model: codex unknown effort rejected" {
    _run_proxy 'exit 22' -p codex -m "gpt-5.3-codex(turbocharged)"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown effort"* ]]
}
