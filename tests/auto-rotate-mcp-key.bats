#!/usr/bin/env bats
# auto-rotate-mcp-key.bats
# Path: tests/auto-rotate-mcp-key.bats
#
# Unit + integration tests for the auto-rotate-mcp-key.sh PostToolUse hook.
# Tests error detection, service resolution, cooldown, actual rotation
# with mock mcp-key-rotate, and settings.json integration.
#
# Run: bats tests/auto-rotate-mcp-key.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/auto-rotate-mcp-key.sh"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

# --- Test fixtures ---
KEY_A="test-key-AAAA-1111"
KEY_B="test-key-BBBB-2222"
KEY_C="test-key-CCCC-3333"

# --- Helpers ---

# Build PostToolUse JSON input
make_input() {
    local tool_name="$1" result="$2"
    # Use jq if available, else printf
    if command -v jq &>/dev/null; then
        jq -n \
            --arg tn "${tool_name}" \
            --arg tr "${result}" \
            '{ tool_name: $tn, tool_input: {query: "test"}, tool_result: $tr }'
    else
        printf '{"tool_name":"%s","tool_input":{"query":"test"},"tool_result":"%s"}' \
            "${tool_name}" "${result}"
    fi
}

# Build input with tool_output field (alternative field name)
make_input_output_field() {
    local tool_name="$1" result="$2"
    jq -n \
        --arg tn "${tool_name}" \
        --arg tr "${result}" \
        '{ tool_name: $tn, tool_input: {query: "test"}, tool_output: $tr }'
}

# Build input with error field
make_input_error_field() {
    local tool_name="$1" result="$2"
    jq -n \
        --arg tn "${tool_name}" \
        --arg tr "${result}" \
        '{ tool_name: $tn, tool_input: {query: "test"}, error: $tr }'
}

# Build REAL Claude Code PostToolUse payload: .tool_response is an object
# (matching PostToolUseHookInput from @anthropic-ai/claude-agent-sdk).
# The tool_response mirrors the MCP content-array shape the Tavily/Brave
# MCP servers return on error.
make_input_real() {
    local tool_name="$1" query="$2" err_text="$3"
    jq -n \
        --arg tn "${tool_name}" \
        --arg q "${query}" \
        --arg e "${err_text}" \
        '{
            session_id: "test-session",
            transcript_path: "/tmp/fake-transcript.jsonl",
            cwd: "/tmp",
            permission_mode: "default",
            hook_event_name: "PostToolUse",
            tool_name: $tn,
            tool_input: { query: $q },
            tool_response: {
                content: [ { type: "text", text: $e } ],
                isError: true
            },
            tool_use_id: "toolu_test_01"
        }'
}

# Same as make_input_real but sets hook_event_name to PostToolUseFailure to
# simulate the failure-path event Claude Code fires when an MCP tool throws
# (e.g. Tavily/Brave raise on 432/429 instead of returning isError content).
make_input_failure() {
    local tool_name="$1" query="$2" err_text="$3"
    jq -n \
        --arg tn "${tool_name}" \
        --arg q "${query}" \
        --arg e "${err_text}" \
        '{
            session_id: "test-session",
            transcript_path: "/tmp/fake-transcript.jsonl",
            cwd: "/tmp",
            permission_mode: "default",
            hook_event_name: "PostToolUseFailure",
            tool_name: $tn,
            tool_input: { query: $q },
            tool_response: {
                content: [ { type: "text", text: $e } ],
                isError: true
            },
            tool_use_id: "toolu_test_01"
        }'
}

# Create a curl mock that returns canned Tavily and Brave JSON without
# hitting the network. Placed in TEST_TMPDIR and picked up via PATH.
# Controlled by env vars so tests can exercise success/failure paths:
#   TAVILY_MOCK_STATUS=success|malformed|empty|http_error
#   BRAVE_MOCK_STATUS=success|malformed|empty|http_error
create_curl_mock() {
    local mock="${TEST_TMPDIR}/curl"
    cat > "${mock}" <<'MOCK_EOF'
#!/usr/bin/env bash
# curl mock for auto-rotate replay tests. Pattern-matches the URL in argv
# and returns a canned response with no network I/O.
args=("$@")
url=""
for a in "${args[@]}"; do
    case "$a" in
        https://*|http://*) url="$a" ;;
    esac
done

# Tavily search endpoint
if [[ "$url" == *"api.tavily.com/search"* ]]; then
    case "${TAVILY_MOCK_STATUS:-success}" in
        success)
            cat <<'JSON'
{
  "query": "test-query",
  "answer": "Mocked answer for test.",
  "results": [
    {"title": "Mocked Result 1", "url": "https://example.com/1", "content": "First mock result content."},
    {"title": "Mocked Result 2", "url": "https://example.com/2", "content": "Second mock result content."}
  ]
}
JSON
            exit 0
            ;;
        malformed)
            echo "not valid json {"
            exit 0
            ;;
        empty)
            echo '{}'
            exit 0
            ;;
        http_error)
            echo '{"error": "unauthorized"}' >&2
            exit 22
            ;;
    esac
fi

# Brave web search endpoint
if [[ "$url" == *"api.search.brave.com"* ]]; then
    case "${BRAVE_MOCK_STATUS:-success}" in
        success)
            cat <<'JSON'
{
  "query": {"original": "test-query"},
  "web": {
    "results": [
      {"title": "Brave Mock 1", "url": "https://example.com/b1", "description": "Brave first mock description."},
      {"title": "Brave Mock 2", "url": "https://example.com/b2", "description": "Brave second mock description."}
    ]
  }
}
JSON
            exit 0
            ;;
        malformed)
            echo "nope"
            exit 0
            ;;
        empty)
            echo '{}'
            exit 0
            ;;
        http_error)
            exit 22
            ;;
    esac
fi

# Fallback: unknown URL -> error so tests fail loudly instead of silently
echo "curl mock: unexpected url: ${url}" >&2
exit 99
MOCK_EOF
    chmod +x "${mock}"
}

# Create a mock mcp-key-rotate that succeeds
create_rotate_mock() {
    local mock="${TEST_TMPDIR}/mcp-key-rotate"
    cat > "${mock}" <<'MOCK_EOF'
#!/usr/bin/env bash
service="${1:-unknown}"
echo "Rotated ${service}: old-key -> new-key (key [2] of 3, backend: dotenv)"
MOCK_EOF
    chmod +x "${mock}"
}

# Create a mock mcp-key-rotate that fails
create_rotate_mock_fail() {
    local mock="${TEST_TMPDIR}/mcp-key-rotate"
    cat > "${mock}" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "Only 1 key in pool -- nothing to rotate to." >&2
exit 1
MOCK_EOF
    chmod +x "${mock}"
}

# --- Setup / Teardown ---

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"
    export AUTO_ROTATE_STATE_DIR="${TEST_TMPDIR}/state"
    mkdir -p "${AUTO_ROTATE_STATE_DIR}"
    export AUTO_ROTATE_COOLDOWN_SEC=0
    # Keep replay off by default so tests don't burn real API credits.
    export AUTO_ROTATE_DISABLE_REPLAY=1
    # Tests that want drift set TAVILY/BRAVE_API_KEY explicitly; default empty.
    unset TAVILY_API_KEY
    unset BRAVE_API_KEY
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

# ==========================================================================
# UNIT TESTS: Script basics
# ==========================================================================

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "exits 0 for non-MCP tool (Bash)" {
    local input
    input='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_result":"file1\nfile2"}'
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "exits 0 for successful tavily call (no error)" {
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Results found: 5 items about testing")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "exits 0 for successful brave call (no error)" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "Web results for query")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "handles empty stdin gracefully" {
    run bash -c "echo '' | bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "handles /dev/null stdin gracefully" {
    run bash "$HOOK" < /dev/null
    [ "$status" -eq 0 ]
}

@test "handles malformed JSON gracefully" {
    run bash -c "echo 'not json at all' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "handles JSON with no tool_name gracefully" {
    run bash -c "echo '{\"foo\":\"bar\"}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "handles JSON with null tool_result gracefully" {
    local input
    input='{"tool_name":"mcp__tavily__tavily_search","tool_input":{},"tool_result":null}'
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ==========================================================================
# UNIT TESTS: Service resolution
# ==========================================================================

@test "resolves mcp__tavily__tavily_search to tavily" {
    # Use a quota error to prove the service was resolved (output mentions tavily)
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Request failed with status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tavily"* ]]
}

@test "resolves mcp__tavily__tavily_extract to tavily" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_extract" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tavily"* ]]
}

@test "resolves mcp__tavily__tavily_crawl to tavily" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_crawl" "Error: 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tavily"* ]]
}

@test "resolves mcp__brave-search__brave_web_search to brave" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "429 Too Many Requests")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"brave"* ]]
}

@test "resolves mcp__brave-search__brave_news_search to brave" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_news_search" "Error: 429")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"brave"* ]]
}

@test "ignores unknown MCP tool (mcp__other__search)" {
    local input
    input="$(make_input "mcp__other__search" "429 error")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ==========================================================================
# UNIT TESTS: Error detection — Tavily
# ==========================================================================

@test "detects tavily HTTP 432 error" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Tavily API error: Request failed with status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
    [[ "$output" == *"tavily"* ]]
}

@test "detects tavily Error: 432 pattern" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Error: 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "does NOT false-positive on bare 432 in content" {
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Found 432 results for your query")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "detects tavily quota exceeded keyword" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "API quota exceeded for this key")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "detects tavily Quota limit reached" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Quota limit reached")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "detects tavily rate limit keyword" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Rate Limit exceeded")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "ignores tavily 500 error (not quota)" {
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Internal Server Error 500")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ignores tavily 401 error (not quota)" {
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Unauthorized 401")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ignores tavily normal error without quota keywords" {
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Connection timeout after 30s")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ==========================================================================
# UNIT TESTS: Error detection — Brave
# ==========================================================================

@test "detects brave HTTP 429 error" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "HTTP 429 Too Many Requests")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
    [[ "$output" == *"brave"* ]]
}

@test "detects brave Error: 429 pattern" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "Error: 429")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "does NOT false-positive on bare 429 in content" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "Page 429 of search results")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "detects brave Too Many Requests" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "Too Many Requests")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "detects brave rate limit keyword" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "rate limit exceeded")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "detects brave quota keyword" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "API quota exhausted")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "ignores brave 500 error (not quota)" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "Internal Server Error")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ==========================================================================
# UNIT TESTS: Alternative result field names
# ==========================================================================

@test "detects error in tool_output field" {
    create_rotate_mock
    local input
    input="$(make_input_output_field "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "detects error in error field" {
    create_rotate_mock
    local input
    input="$(make_input_error_field "mcp__tavily__tavily_search" "432 quota exceeded")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

# ==========================================================================
# INTEGRATION: Auto-rotation with mock mcp-key-rotate
# ==========================================================================

@test "integration: rotates key on tavily 432" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "Tavily API error: Request failed with status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]
}

@test "integration: rotates key on brave 429" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "429 Too Many Requests")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated brave"* ]]
}

@test "integration: outputs restart message after rotation" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTION REQUIRED"* ]]
    [[ "$output" == *"Restart Claude Code"* ]]
}

@test "integration: suggests /web-search fallback" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"IMMEDIATE FALLBACK"* ]]
    [[ "$output" == *"/web-search"* ]]
}

@test "integration: handles rotation failure gracefully" {
    create_rotate_mock_fail
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Auto-rotation failed"* ]]
    [[ "$output" == *"Run manually"* ]]
}

@test "integration: handles mcp-key-rotate not found" {
    # Copy hook to an isolated temp dir so BASH_SOURCE relative path
    # won't find the repo's bin/mcp-key-rotate
    local isolated_hook="${TEST_TMPDIR}/isolated/auto-rotate-mcp-key.sh"
    mkdir -p "${TEST_TMPDIR}/isolated"
    cp "$HOOK" "${isolated_hook}"
    chmod +x "${isolated_hook}"

    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | HOME='${TEST_TMPDIR}/fakehome' PATH='/usr/bin:/bin' bash '${isolated_hook}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mcp-key-rotate not found"* ]]
    [[ "$output" == *"Run manually"* ]]
}

# ==========================================================================
# INTEGRATION: Lock mechanism
# ==========================================================================

@test "lock: lock directory is cleaned up after rotation" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -d "${AUTO_ROTATE_STATE_DIR}/mcp-auto-rotate-tavily.lock" ]
}

@test "lock: lock directory is cleaned up after cooldown hit" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=300
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"

    # First call: rotate (creates cooldown)
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    # Second call: hits cooldown
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -d "${AUTO_ROTATE_STATE_DIR}/mcp-auto-rotate-tavily.lock" ]
}

# ==========================================================================
# INTEGRATION: Cooldown mechanism
# ==========================================================================

@test "cooldown: creates state file after rotation" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=300
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -f "${AUTO_ROTATE_STATE_DIR}/mcp-auto-rotate-tavily.ts" ]
}

@test "cooldown: blocks second rotation within window" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=300

    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"

    # First call: should rotate
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]

    # Second call: should be in cooldown
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already rotated"* ]]
    [[ "$output" != *"Rotated tavily"* ]]
}

@test "cooldown: allows rotation after cooldown expires" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=1

    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"

    # First call: rotate
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]

    # Wait for cooldown to expire
    sleep 2

    # Second call: should rotate again
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]
}

@test "cooldown: separate cooldowns per service" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=300

    local tavily_input brave_input
    tavily_input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    brave_input="$(make_input "mcp__brave-search__brave_web_search" "HTTP 429")"

    # Rotate tavily
    run bash -c "echo '${tavily_input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]

    # Brave should still rotate (different service, different cooldown)
    run bash -c "echo '${brave_input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated brave"* ]]
}

@test "cooldown: handles corrupt state file" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=300

    # Write garbage to cooldown file
    echo "not-a-timestamp" > "${AUTO_ROTATE_STATE_DIR}/mcp-auto-rotate-tavily.ts"

    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    # Should treat corrupt file as expired cooldown and rotate
    [[ "$output" == *"Rotated tavily"* ]]
}

@test "cooldown: zero cooldown allows immediate re-rotation" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=0

    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"

    # Two rapid calls should both rotate
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]

    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]
}

# ==========================================================================
# INTEGRATION: Full rotation with real mcp-key-rotate (dotenv backend)
# ==========================================================================

@test "e2e: full tavily rotation via mcp-key-rotate dotenv backend" {
    # Set up a real .env with pool
    local test_dotenv="${TEST_TMPDIR}/.env"
    echo "TAVILY_API_KEY=${KEY_A}" > "${test_dotenv}"
    echo "TAVILY_API_KEY_POOL=${KEY_A},${KEY_B},${KEY_C}" >> "${test_dotenv}"

    local input
    input="$(make_input "mcp__tavily__tavily_search" "Tavily API error: Request failed with status code 432")"

    run bash -c "echo '${input}' | \
        KEY_ROTATE_BACKEND=dotenv \
        KEY_ROTATE_DOTENV='${test_dotenv}' \
        MCP_KEYS_ENV_FILE='${TEST_TMPDIR}/mcp-keys.env' \
        MCP_KEY_HEALTH_DIR='${TEST_TMPDIR}/health' \
        PATH='${REPO_ROOT}/bin:${PATH}' \
        bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated tavily"* ]]
    [[ "$output" == *"ACTION REQUIRED"* ]]

    # Verify the .env was actually updated
    local new_key
    new_key="$(grep "^TAVILY_API_KEY=" "${test_dotenv}" | head -1 | cut -d'=' -f2-)"
    [ "${new_key}" = "${KEY_B}" ]
}

@test "e2e: full brave rotation via mcp-key-rotate dotenv backend" {
    local test_dotenv="${TEST_TMPDIR}/.env"
    echo "BRAVE_API_KEY=${KEY_B}" > "${test_dotenv}"
    echo "BRAVE_API_KEY_POOL=${KEY_A},${KEY_B}" >> "${test_dotenv}"

    local input
    input="$(make_input "mcp__brave-search__brave_web_search" "429 Too Many Requests")"

    run bash -c "echo '${input}' | \
        KEY_ROTATE_BACKEND=dotenv \
        KEY_ROTATE_DOTENV='${test_dotenv}' \
        MCP_KEYS_ENV_FILE='${TEST_TMPDIR}/mcp-keys.env' \
        MCP_KEY_HEALTH_DIR='${TEST_TMPDIR}/health' \
        PATH='${REPO_ROOT}/bin:${PATH}' \
        bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated brave"* ]]

    # Verify wrap-around: B -> A
    local new_key
    new_key="$(grep "^BRAVE_API_KEY=" "${test_dotenv}" | head -1 | cut -d'=' -f2-)"
    [ "${new_key}" = "${KEY_A}" ]
}

# ==========================================================================
# INTEGRATION: settings.json validation
# ==========================================================================

@test "settings.json: PostToolUse hook is configured" {
    run jq '.hooks.PostToolUse' "${REPO_ROOT}/.claude/settings.json"
    [ "$status" -eq 0 ]
    [[ "$output" != "null" ]]
}

@test "settings.json: PostToolUse matcher covers tavily" {
    local matcher
    matcher="$(jq -r '.hooks.PostToolUse[0].matcher' "${REPO_ROOT}/.claude/settings.json")"
    # Verify the regex matches tavily tool names
    echo "mcp__tavily__tavily_search" | grep -qE "${matcher}"
}

@test "settings.json: PostToolUse matcher covers brave-search" {
    local matcher
    matcher="$(jq -r '.hooks.PostToolUse[0].matcher' "${REPO_ROOT}/.claude/settings.json")"
    echo "mcp__brave-search__brave_web_search" | grep -qE "${matcher}"
}

@test "settings.json: PostToolUse points to auto-rotate hook" {
    local hook_cmd
    hook_cmd="$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "${REPO_ROOT}/.claude/settings.json")"
    [[ "${hook_cmd}" == *"auto-rotate-mcp-key.sh"* ]]
}

@test "settings.json: PostToolUse matcher does NOT match non-MCP tools" {
    local matcher
    matcher="$(jq -r '.hooks.PostToolUse[0].matcher' "${REPO_ROOT}/.claude/settings.json")"
    # Bash should not match
    if echo "Bash" | grep -qE "${matcher}" 2>/dev/null; then
        false  # Should not match
    fi
}

@test "settings.json: PostToolUseFailure hook is configured" {
    local count
    count="$(jq '[.hooks.PostToolUseFailure[].hooks[].command] | map(select(contains("auto-rotate-mcp-key"))) | length' \
        "${REPO_ROOT}/.claude/settings.json")"
    [ "$count" = "1" ]
}

@test "settings.json: PostToolUseFailure matcher covers tavily and brave-search" {
    local matcher
    matcher="$(jq -r '.hooks.PostToolUseFailure[] | select(.hooks[].command | contains("auto-rotate-mcp-key")) | .matcher' \
        "${REPO_ROOT}/.claude/settings.json")"
    echo "mcp__tavily__tavily_search" | grep -qE "${matcher}"
    echo "mcp__brave-search__brave_web_search" | grep -qE "${matcher}"
}

# ==========================================================================
# INTEGRATION: CLAUDE.md documentation
# ==========================================================================

@test "CLAUDE.md: documents auto-rotate hook" {
    grep -q "auto-rotate-mcp-key" "${REPO_ROOT}/CLAUDE.md"
}

@test "CLAUDE.md: mentions PostToolUse" {
    grep -qi "PostToolUse\|post.tool" "${REPO_ROOT}/CLAUDE.md"
}

# ==========================================================================
# REAL CLAUDE CODE SCHEMA: tool_response as object
#
# Claude Code's PostToolUseHookInput sends the tool result in .tool_response
# as an object (per @anthropic-ai/claude-agent-sdk). The previous hook read
# .tool_result / .tool_output / .tool_error and silently ignored
# .tool_response, so auto-rotation never fired in production. These tests
# lock in the fix and prevent regression.
# ==========================================================================

@test "real schema: detects tavily 432 in .tool_response object content[0].text" {
    create_rotate_mock
    local input
    input="$(make_input_real \
        "mcp__tavily__tavily_search" \
        "SOTA git clone 2026" \
        "Tavily API error: Request failed with status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
    [[ "$output" == *"tavily"* ]]
    [[ "$output" == *"Rotated tavily"* ]]
}

@test "real schema: detects brave 429 in .tool_response object" {
    create_rotate_mock
    local input
    input="$(make_input_real \
        "mcp__brave-search__brave_web_search" \
        "test query" \
        "429 Too Many Requests")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
    [[ "$output" == *"brave"* ]]
}

@test "real schema: successful tool_response does not trigger rotation" {
    # Clean tool_response with real results should not match quota patterns
    local input
    input='{
        "tool_name": "mcp__tavily__tavily_search",
        "tool_input": {"query": "test"},
        "tool_response": {
            "content": [{"type":"text","text":"{\"results\":[{\"title\":\"Result\",\"url\":\"https://x.com\"}]}"}],
            "isError": false
        }
    }'
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "real schema: tool_response handles deeply nested quota error text" {
    create_rotate_mock
    local input
    input='{
        "tool_name": "mcp__tavily__tavily_search",
        "tool_input": {"query": "test"},
        "tool_response": {
            "content": [
                {"type":"text","text":"Tool execution failed"},
                {"type":"text","text":"Underlying: HTTP 432 quota exceeded"}
            ],
            "isError": true,
            "_meta": {"retryable": false}
        }
    }'
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[auto-rotate]"* ]]
}

@test "real schema: regression guard -- hook reads tool_response field" {
    # Explicit regression test for the tool_result vs tool_response bug.
    # If someone reverts the jq filter, this test fails loudly.
    run grep -q '\.tool_response' "$HOOK"
    [ "$status" -eq 0 ]
}

# ==========================================================================
# FALLBACK PATH: JSON additionalContext output
#
# When replay is disabled or impossible, the hook must emit valid JSON on
# stdout with hookSpecificOutput.additionalContext so Claude can surface
# the restart instructions to the user. Plain stdout text goes to the
# debug log only and never reaches Claude.
# ==========================================================================

@test "fallback: emits valid JSON when replay disabled" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    # Output should parse as JSON
    echo "$output" | jq -e . >/dev/null
}

@test "fallback: JSON has hookSpecificOutput.hookEventName = PostToolUse" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local name
    name="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName')"
    [ "$name" = "PostToolUse" ]
}

@test "fallback: JSON additionalContext contains restart instructions" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"ACTION REQUIRED"* ]]
    [[ "$ctx" == *"Restart Claude Code"* ]]
    [[ "$ctx" == *"/web-search"* ]]
}

@test "fallback: JSON additionalContext embeds rotate_output" {
    create_rotate_mock
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    # The mock's stdout ("Rotated tavily: old-key -> new-key (...)") should
    # be embedded in the fallback context so Claude sees the rotation detail.
    [[ "$ctx" == *"Rotated tavily"* ]]
    [[ "$ctx" == *"new-key"* ]]
}

@test "fallback: cooldown hit emits valid JSON additionalContext" {
    create_rotate_mock
    export AUTO_ROTATE_COOLDOWN_SEC=300
    local input
    input="$(make_input "mcp__tavily__tavily_search" "status code 432")"

    # First call: normal rotation path
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    # Second call: cooldown hit
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"already rotated"* ]] || [[ "$ctx" == *"cooldown"* ]]
}

# ==========================================================================
# TRANSPARENT REPLAY: updatedMCPToolOutput path
#
# The SOTA 2026 flow: on quota error, rotate the key, replay the original
# request directly against the vendor HTTP API, and return the real results
# via hookSpecificOutput.updatedMCPToolOutput so Claude never sees the 432.
# Uses a curl mock to stay hermetic -- zero real network calls, zero credit
# burn.
# ==========================================================================

@test "replay: tavily_search returns updatedMCPToolOutput with results" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-tavily-key"
    export TAVILY_MOCK_STATUS=success

    local input
    input="$(make_input_real \
        "mcp__tavily__tavily_search" \
        "SOTA git clone" \
        "Tavily API error: Request failed with status code 432")"

    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    # Output must be valid JSON
    echo "$output" | jq -e . >/dev/null

    # Must carry updatedMCPToolOutput as an array of content blocks
    local block_count
    block_count="$(echo "$output" | jq '.hookSpecificOutput.updatedMCPToolOutput | length')"
    [ "$block_count" -ge 1 ]

    # First block must be text type
    local block_type
    block_type="$(echo "$output" | jq -r '.hookSpecificOutput.updatedMCPToolOutput[0].type')"
    [ "$block_type" = "text" ]

    # Text must contain the mocked results (proves replay actually ran)
    local text
    text="$(echo "$output" | jq -r '.hookSpecificOutput.updatedMCPToolOutput[0].text')"
    [[ "$text" == *"Mocked Result 1"* ]]
    [[ "$text" == *"Mocked Result 2"* ]]
    [[ "$text" == *"example.com/1"* ]]
}

@test "replay: tavily_search additionalContext explains what happened" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-tavily-key"
    export TAVILY_MOCK_STATUS=success

    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"transparently replayed"* ]]
    [[ "$ctx" == *"No restart needed"* ]]
}

@test "replay: brave_web_search returns updatedMCPToolOutput with results" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-brave-key"
    export BRAVE_MOCK_STATUS=success

    local input
    input="$(make_input_real \
        "mcp__brave-search__brave_web_search" \
        "claude code hooks" \
        "HTTP 429 Too Many Requests")"

    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    echo "$output" | jq -e . >/dev/null
    local text
    text="$(echo "$output" | jq -r '.hookSpecificOutput.updatedMCPToolOutput[0].text')"
    [[ "$text" == *"Brave Mock 1"* ]]
    [[ "$text" == *"example.com/b1"* ]]
}

@test "replay: skipped for non-replayable tool (tavily_extract) -- falls back" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-key"

    local input
    input="$(make_input_real "mcp__tavily__tavily_extract" "url" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    # Must be JSON fallback, not updatedMCPToolOutput
    echo "$output" | jq -e . >/dev/null
    local has_output
    has_output="$(echo "$output" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("updatedMCPToolOutput"))')"
    [ "$has_output" = "false" ]

    # Must have additionalContext with restart instructions
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"ACTION REQUIRED"* ]]
}

@test "replay: falls back when curl returns malformed JSON" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-key"
    export TAVILY_MOCK_STATUS=malformed

    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    echo "$output" | jq -e . >/dev/null
    local has_output
    has_output="$(echo "$output" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("updatedMCPToolOutput"))')"
    [ "$has_output" = "false" ]
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"ACTION REQUIRED"* ]]
}

@test "replay: falls back when curl returns empty results" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-key"
    export TAVILY_MOCK_STATUS=empty

    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local has_output
    has_output="$(echo "$output" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("updatedMCPToolOutput"))')"
    [ "$has_output" = "false" ]
}

@test "replay: falls back when curl itself exits non-zero" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-key"
    export TAVILY_MOCK_STATUS=http_error

    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local has_output
    has_output="$(echo "$output" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("updatedMCPToolOutput"))')"
    [ "$has_output" = "false" ]
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"ACTION REQUIRED"* ]]
}

@test "replay: falls back when tool_input has empty query" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-key"

    local input
    input='{
        "tool_name": "mcp__tavily__tavily_search",
        "tool_input": {},
        "tool_response": {"content":[{"type":"text","text":"status code 432"}],"isError":true}
    }'
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local has_output
    has_output="$(echo "$output" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("updatedMCPToolOutput"))')"
    [ "$has_output" = "false" ]
}

@test "replay: AUTO_ROTATE_DISABLE_REPLAY=1 forces fallback even with curl mock" {
    create_rotate_mock
    create_curl_mock
    export AUTO_ROTATE_DISABLE_REPLAY=1
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-key"
    export TAVILY_MOCK_STATUS=success

    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local has_output
    has_output="$(echo "$output" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("updatedMCPToolOutput"))')"
    [ "$has_output" = "false" ]
}

@test "replay: cooldown branch still attempts replay with current active key" {
    # After a rotation, a second quota error within the cooldown window should
    # still try to replay (the active key was already advanced, it's wasteful
    # to just surface a fallback). The replay succeeds and Claude sees results.
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_COOLDOWN_SEC=300
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-tavily-key"
    export TAVILY_MOCK_STATUS=success

    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"

    # First call: rotate + replay
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    # Second call: cooldown hit, but replay still runs
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local text
    text="$(echo "$output" | jq -r '.hookSpecificOutput.updatedMCPToolOutput[0].text // ""')"
    [[ "$text" == *"Mocked Result 1"* ]]
}

@test "replay: cooldown branch falls back when replay fails" {
    create_rotate_mock
    create_curl_mock
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_COOLDOWN_SEC=300
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="mock-key"

    local input1 input2
    input1="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    # Second call is a non-replayable tool -> cooldown + try_replay returns 1
    input2="$(make_input_real "mcp__tavily__tavily_extract" "url" "status code 432")"

    run bash -c "echo '${input1}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    run bash -c "echo '${input2}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"already rotated"* ]] || [[ "$ctx" == *"cooldown"* ]]
}

@test "replay: quota usage is NOT burned when replay is disabled" {
    # Sanity check: hermetic default means no curl process runs and no
    # outbound request occurs. We prove this by pointing curl at a mock
    # that exits non-zero if called, and verifying the hook still succeeds
    # via the fallback path.
    create_rotate_mock
    local burn_guard="${TEST_TMPDIR}/curl"
    cat > "${burn_guard}" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "CURL WAS CALLED -- REPLAY SHOULD HAVE BEEN DISABLED" >&2
exit 42
MOCK_EOF
    chmod +x "${burn_guard}"

    # Default setup() sets AUTO_ROTATE_DISABLE_REPLAY=1
    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    # Must NOT contain the burn guard's stderr message
    [[ "$output" != *"CURL WAS CALLED"* ]]
}

# ==========================================================================
# CIRCUIT BREAKER: e2e with real bin/mcp-key-rotate + mock doppler
# ==========================================================================

_cb_setup_doppler_pool() {
    local service="$1" current="$2" pool="$3"

    mkdir -p "${TEST_TMPDIR}/doppler_store"
    cat > "${TEST_TMPDIR}/doppler" <<'MOCK_EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "secrets" ]]; then
    if [[ "${2:-}" == "get" ]]; then
        local_name="${3:-}"
        store_file="${MOCK_DOPPLER_STORE}/${local_name}"
        if [[ -f "${store_file}" ]]; then
            cat "${store_file}"
        else
            exit 1
        fi
    elif [[ "${2:-}" == "set" ]]; then
        local_pair="${3:-}"
        local_name="${local_pair%%=*}"
        local_value="${local_pair#*=}"
        echo -n "${local_value}" > "${MOCK_DOPPLER_STORE}/${local_name}"
    fi
fi
MOCK_EOF
    chmod +x "${TEST_TMPDIR}/doppler"
    export MOCK_DOPPLER_STORE="${TEST_TMPDIR}/doppler_store"

    # Seed pool contents
    local upper
    upper="$(echo "${service}" | tr '[:lower:]' '[:upper:]')"
    echo -n "${current}" > "${MOCK_DOPPLER_STORE}/${upper}_API_KEY"
    echo -n "${pool}" > "${MOCK_DOPPLER_STORE}/${upper}_API_KEY_POOL"
}

_cb_doppler_read() {
    local name="$1"
    cat "${MOCK_DOPPLER_STORE}/${name}" 2>/dev/null
}

# _cb_run_hook <service> <tool_name> <err_text> [env_key]
# env_key defaults to the mock doppler's current value (no drift); pass an
# explicit value to simulate env != backend current.
_cb_run_hook() {
    local service="$1" tool_name="$2" err_text="$3"
    local env_key="${4:-}"
    local health_dir="${TEST_TMPDIR}/health"
    mkdir -p "${health_dir}"

    local upper env_var_name
    upper="$(echo "${service}" | tr '[:lower:]' '[:upper:]')"
    env_var_name="${upper}_API_KEY"

    if [[ -z "${env_key}" ]]; then
        env_key="$(cat "${MOCK_DOPPLER_STORE}/${env_var_name}" 2>/dev/null || echo "")"
    fi

    local input
    input="$(make_input_real "${tool_name}" "q" "${err_text}")"

    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        MOCK_DOPPLER_STORE='${MOCK_DOPPLER_STORE}' \
        KEY_ROTATE_BACKEND=doppler \
        MCP_KEY_HEALTH_DIR='${health_dir}' \
        ${env_var_name}='${env_key}' \
        bash '$HOOK'"
}

@test "circuit: hook marks current key bad before rotating on 432" {
    _cb_setup_doppler_pool tavily "${KEY_A}" "${KEY_A},${KEY_B},${KEY_C}"

    _cb_run_hook tavily mcp__tavily__tavily_search "status code 432"
    [ "$status" -eq 0 ]

    # Health file should exist and mark KEY_A as OPEN
    local health_file="${TEST_TMPDIR}/health/tavily.json"
    [ -f "$health_file" ]
    local fp
    fp="$(printf '%s' "${KEY_A}" | shasum -a 256 | cut -c1-12)"
    local state
    state="$(jq -r --arg fp "$fp" '.keys[$fp].state' "$health_file")"
    [ "$state" = "open" ]
}

@test "circuit: hook rotates A->B when pool is fresh" {
    _cb_setup_doppler_pool brave "${KEY_A}" "${KEY_A},${KEY_B},${KEY_C}"

    _cb_run_hook brave mcp__brave-search__brave_web_search "429 Too Many Requests"
    [ "$status" -eq 0 ]

    local new_active
    new_active="$(_cb_doppler_read BRAVE_API_KEY)"
    [ "$new_active" = "${KEY_B}" ]
}

@test "circuit: hook SKIPS pre-marked bad key and lands on healthy C" {
    _cb_setup_doppler_pool brave "${KEY_A}" "${KEY_A},${KEY_B},${KEY_C}"

    # Pre-mark KEY_B as OPEN with a long TTL so the hook must skip it.
    echo -n "${KEY_B}" > "${MOCK_DOPPLER_STORE}/BRAVE_API_KEY"
    env PATH="${TEST_TMPDIR}:${PATH}" \
        MOCK_DOPPLER_STORE="${MOCK_DOPPLER_STORE}" \
        KEY_ROTATE_BACKEND=doppler \
        MCP_KEY_HEALTH_DIR="${TEST_TMPDIR}/health" \
        bash "${REPO_ROOT}/bin/mcp-key-rotate" brave --mark-bad 7200 >/dev/null
    echo -n "${KEY_A}" > "${MOCK_DOPPLER_STORE}/BRAVE_API_KEY"

    _cb_run_hook brave mcp__brave-search__brave_web_search "status code 429"
    [ "$status" -eq 0 ]

    local new_active
    new_active="$(_cb_doppler_read BRAVE_API_KEY)"
    # Hook first marks A bad (via --mark-bad), then rotates from A.
    # B is already OPEN, so rotation must skip B and land on C.
    [ "$new_active" = "${KEY_C}" ]
}

@test "circuit: hook rotation is idempotent against repeated 432s" {
    _cb_setup_doppler_pool tavily "${KEY_A}" "${KEY_A},${KEY_B},${KEY_C}"

    # First invocation: should mark A bad and rotate to B
    _cb_run_hook tavily mcp__tavily__tavily_search "Quota exceeded"
    [ "$status" -eq 0 ]
    local after1
    after1="$(_cb_doppler_read TAVILY_API_KEY)"
    [ "$after1" = "${KEY_B}" ]

    # Clear cooldown so second invocation actually rotates (simulating time passing)
    rm -f "${AUTO_ROTATE_STATE_DIR}/mcp-auto-rotate-tavily.ts"

    # Second invocation with B now active: should mark B bad and rotate to C
    # (NOT back to A, which is already in circuit-open state).
    _cb_run_hook tavily mcp__tavily__tavily_search "Quota exceeded"
    [ "$status" -eq 0 ]
    local after2
    after2="$(_cb_doppler_read TAVILY_API_KEY)"
    [ "$after2" = "${KEY_C}" ]

    # Both A and B should now be in circuit-open state in the health file
    local health_file="${TEST_TMPDIR}/health/tavily.json"
    local fp_a fp_b
    fp_a="$(printf '%s' "${KEY_A}" | shasum -a 256 | cut -c1-12)"
    fp_b="$(printf '%s' "${KEY_B}" | shasum -a 256 | cut -c1-12)"
    local state_a state_b
    state_a="$(jq -r --arg fp "$fp_a" '.keys[$fp].state' "$health_file")"
    state_b="$(jq -r --arg fp "$fp_b" '.keys[$fp].state' "$health_file")"
    [ "$state_a" = "open" ]
    [ "$state_b" = "open" ]
}

@test "circuit: hook all-keys-open picks least-bad and falls through to Claude" {
    _cb_setup_doppler_pool tavily "${KEY_A}" "${KEY_A},${KEY_B},${KEY_C}"

    # Pre-mark ALL three keys as OPEN, with distinct cooldown times.
    local key ttl
    for key in "${KEY_A}:7200" "${KEY_B}:3600" "${KEY_C}:7200"; do
        local k="${key%%:*}"
        ttl="${key##*:}"
        echo -n "${k}" > "${MOCK_DOPPLER_STORE}/TAVILY_API_KEY"
        env PATH="${TEST_TMPDIR}:${PATH}" \
            MOCK_DOPPLER_STORE="${MOCK_DOPPLER_STORE}" \
            KEY_ROTATE_BACKEND=doppler \
            MCP_KEY_HEALTH_DIR="${TEST_TMPDIR}/health" \
            bash "${REPO_ROOT}/bin/mcp-key-rotate" tavily --mark-bad "${ttl}" >/dev/null
    done
    echo -n "${KEY_A}" > "${MOCK_DOPPLER_STORE}/TAVILY_API_KEY"

    _cb_run_hook tavily mcp__tavily__tavily_search "status code 432"
    [ "$status" -eq 0 ]

    # Hook should still succeed (exits 0), emit additionalContext for Claude,
    # and fall through to least-bad key (KEY_B has shortest TTL).
    local new_active
    new_active="$(_cb_doppler_read TAVILY_API_KEY)"
    [ "$new_active" = "${KEY_B}" ]

    # Output should contain the all-open warning from mcp-key-rotate
    [[ "$output" == *"circuit-open"* ]] || [[ "$output" == *"least-bad"* ]]
}

@test "circuit: hook marks NEWLY-ROTATED key bad when replay also fails" {
    # This tests the second mark-bad call in the hook: after rotation, if replay
    # also fails, the new key gets flagged so subsequent rotations skip it.
    _cb_setup_doppler_pool brave "${KEY_A}" "${KEY_A},${KEY_B}"

    # With DISABLE_REPLAY=1 (set in setup), try_replay returns 1 -> second mark-bad path fires.
    _cb_run_hook brave mcp__brave-search__brave_web_search "status code 429"
    [ "$status" -eq 0 ]

    local health_file="${TEST_TMPDIR}/health/brave.json"
    [ -f "$health_file" ]

    # Both A (marked before rotate) and B (marked after failed replay) should be OPEN
    local fp_a fp_b
    fp_a="$(printf '%s' "${KEY_A}" | shasum -a 256 | cut -c1-12)"
    fp_b="$(printf '%s' "${KEY_B}" | shasum -a 256 | cut -c1-12)"
    local state_a state_b
    state_a="$(jq -r --arg fp "$fp_a" '.keys[$fp].state' "$health_file")"
    state_b="$(jq -r --arg fp "$fp_b" '.keys[$fp].state' "$health_file")"
    [ "$state_a" = "open" ]
    [ "$state_b" = "open" ]
}

@test "circuit: hook health state file stores fingerprints, not raw keys" {
    _cb_setup_doppler_pool tavily "${KEY_A}" "${KEY_A},${KEY_B},${KEY_C}"

    _cb_run_hook tavily mcp__tavily__tavily_search "status code 432"
    [ "$status" -eq 0 ]

    local health_file="${TEST_TMPDIR}/health/tavily.json"
    # Raw key values must NEVER appear in the health state file
    ! grep -q "${KEY_A}" "$health_file"
    ! grep -q "${KEY_B}" "$health_file"
    ! grep -q "${KEY_C}" "$health_file"
}

@test "circuit: bad-key TTL is configurable via AUTO_ROTATE_BAD_KEY_TTL_SEC" {
    _cb_setup_doppler_pool brave "${KEY_A}" "${KEY_A},${KEY_B}"

    local input
    input="$(make_input_real "mcp__brave-search__brave_web_search" "q" "status code 429")"
    local before
    before="$(date +%s)"

    run bash -c "echo '${input}' | \
        PATH='${TEST_TMPDIR}:${PATH}' \
        MOCK_DOPPLER_STORE='${MOCK_DOPPLER_STORE}' \
        KEY_ROTATE_BACKEND=doppler \
        MCP_KEY_HEALTH_DIR='${TEST_TMPDIR}/health' \
        AUTO_ROTATE_BAD_KEY_TTL_SEC=7200 \
        BRAVE_API_KEY='${KEY_A}' \
        bash '$HOOK'"
    [ "$status" -eq 0 ]

    local health_file="${TEST_TMPDIR}/health/brave.json"
    local fp
    fp="$(printf '%s' "${KEY_A}" | shasum -a 256 | cut -c1-12)"
    local ou
    ou="$(jq -r --arg fp "$fp" '.keys[$fp].open_until' "$health_file")"
    local diff=$((ou - before))
    [ "$diff" -ge 7198 ]
    [ "$diff" -le 7210 ]
}

# ==========================================================================
# CIRCUIT BREAKER: env-var drift (backend current != hook env)
# ==========================================================================

@test "drift: hook marks env-key bad (NOT backend current) when they differ" {
    _cb_setup_doppler_pool tavily "${KEY_C}" "${KEY_A},${KEY_B},${KEY_C}"
    _cb_run_hook tavily mcp__tavily__tavily_search "status code 432" "${KEY_A}"
    [ "$status" -eq 0 ]

    local health_file="${TEST_TMPDIR}/health/tavily.json"
    local fp_a fp_c
    fp_a="$(printf '%s' "${KEY_A}" | shasum -a 256 | cut -c1-12)"
    fp_c="$(printf '%s' "${KEY_C}" | shasum -a 256 | cut -c1-12)"

    local state_a
    state_a="$(jq -r --arg fp "$fp_a" '.keys[$fp].state' "$health_file")"
    [ "$state_a" = "open" ]

    # KEY_C (backend current) must NOT have been touched -- this was the
    # critical bug: the old code marked Doppler current bad, which was the
    # only healthy key.
    local state_c
    state_c="$(jq -r --arg fp "$fp_c" '.keys[$fp] // "absent"' "$health_file")"
    [ "$state_c" = "absent" ]
}

@test "drift: hook does NOT rotate when backend current is already healthy" {
    # Doppler is already on healthy KEY_C (out-of-band rotation happened).
    # Env has KEY_A (stale, exhausted). Hook should leave Doppler alone.
    _cb_setup_doppler_pool tavily "${KEY_C}" "${KEY_A},${KEY_B},${KEY_C}"

    _cb_run_hook tavily mcp__tavily__tavily_search "status code 432" "${KEY_A}"
    [ "$status" -eq 0 ]

    # Doppler must remain on KEY_C
    local new_active
    new_active="$(_cb_doppler_read TAVILY_API_KEY)"
    [ "$new_active" = "${KEY_C}" ]

    # Hook output must say "No rotation needed"
    [[ "$output" == *"No rotation needed"* ]]
}

@test "drift: subsequent call (with new env) uses healthy key from prior recover" {
    # Simulates: session 1 crashed with KEY_A, Doppler was advanced to KEY_B by
    # session 1's hook. Session 2 starts with KEY_B in env (new launch). Now
    # session 2 also hits 432 (KEY_B also exhausted). Hook should mark KEY_B
    # bad and rotate to KEY_C.
    _cb_setup_doppler_pool tavily "${KEY_B}" "${KEY_A},${KEY_B},${KEY_C}"
    # Pre-mark KEY_A as already bad from "session 1"
    env PATH="${TEST_TMPDIR}:${PATH}" \
        MOCK_DOPPLER_STORE="${MOCK_DOPPLER_STORE}" \
        KEY_ROTATE_BACKEND=doppler \
        MCP_KEY_HEALTH_DIR="${TEST_TMPDIR}/health" \
        bash "${REPO_ROOT}/bin/mcp-key-rotate" tavily --mark-bad-key "${KEY_A}" 7200 >/dev/null

    # Session 2: env has KEY_B, 432 happens
    _cb_run_hook tavily mcp__tavily__tavily_search "status code 432" "${KEY_B}"
    [ "$status" -eq 0 ]

    # Must rotate from B to C (skipping already-bad A)
    local new_active
    new_active="$(_cb_doppler_read TAVILY_API_KEY)"
    [ "$new_active" = "${KEY_C}" ]

    # Both A and B must be OPEN
    local health_file="${TEST_TMPDIR}/health/tavily.json"
    local fp_a fp_b
    fp_a="$(printf '%s' "${KEY_A}" | shasum -a 256 | cut -c1-12)"
    fp_b="$(printf '%s' "${KEY_B}" | shasum -a 256 | cut -c1-12)"
    local state_a state_b
    state_a="$(jq -r --arg fp "$fp_a" '.keys[$fp].state' "$health_file")"
    state_b="$(jq -r --arg fp "$fp_b" '.keys[$fp].state' "$health_file")"
    [ "$state_a" = "open" ]
    [ "$state_b" = "open" ]
}

@test "drift: env key matches backend current (no drift) still rotates" {
    # Baseline: the "no drift" case -- env and backend agree. Should still
    # rotate because current == failed_key, so fast path doesn't apply.
    _cb_setup_doppler_pool brave "${KEY_A}" "${KEY_A},${KEY_B}"

    _cb_run_hook brave mcp__brave-search__brave_web_search "status code 429" "${KEY_A}"
    [ "$status" -eq 0 ]

    local new_active
    new_active="$(_cb_doppler_read BRAVE_API_KEY)"
    [ "$new_active" = "${KEY_B}" ]
    [[ "$output" == *"Rotated brave"* ]]
}

@test "drift: hook does not mark wrong key on drift scenario (regression guard)" {
    # Regression guard against the pre-fix bug: if backend current drifts,
    # the hook must NOT flag the backend current as bad. This is the exact
    # check that would have caught the original drift bug.
    _cb_setup_doppler_pool brave "${KEY_B}" "${KEY_A},${KEY_B}"

    _cb_run_hook brave mcp__brave-search__brave_web_search "status code 429" "${KEY_A}"
    [ "$status" -eq 0 ]

    # KEY_B (Doppler current AND the healthy one) must NEVER be marked bad
    local health_file="${TEST_TMPDIR}/health/brave.json"
    local fp_b
    fp_b="$(printf '%s' "${KEY_B}" | shasum -a 256 | cut -c1-12)"
    local state_b
    state_b="$(jq -r --arg fp "$fp_b" '.keys[$fp] // "absent"' "$health_file")"
    [ "$state_b" = "absent" ]
}

# ==========================================================================
# REGRESSION: hookEventName echo (Claude Code rejects mismatches)
# ==========================================================================

@test "event name: fallback echoes PostToolUse when hook fires as PostToolUse" {
    create_rotate_mock
    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local emitted
    emitted="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    [ "$emitted" = "PostToolUse" ]
}

@test "event name: fallback echoes PostToolUseFailure when hook fires as PostToolUseFailure" {
    create_rotate_mock
    local input
    input="$(make_input_failure "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local emitted
    emitted="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    [ "$emitted" = "PostToolUseFailure" ]
}

@test "event name: replay success echoes PostToolUse" {
    create_curl_mock
    export TAVILY_MOCK_STATUS=success
    export AUTO_ROTATE_DISABLE_REPLAY=""
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="fake-new-key-for-test"
    create_rotate_mock

    local input
    input="$(make_input_real "mcp__tavily__tavily_search" "test-query" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local emitted has_updated
    emitted="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    [ "$emitted" = "PostToolUse" ]
    has_updated="$(echo "$output" | jq -r '.hookSpecificOutput.updatedMCPToolOutput | length' 2>/dev/null)"
    [ "$has_updated" -ge 1 ]
}

@test "event name: replay success on PostToolUseFailure embeds content in additionalContext (not updatedMCPToolOutput)" {
    create_curl_mock
    export TAVILY_MOCK_STATUS=success
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="fake-new-key-for-test"
    create_rotate_mock

    local input
    input="$(make_input_failure "mcp__tavily__tavily_search" "test-query" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    local emitted ctx has_updated_field
    emitted="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    [ "$emitted" = "PostToolUseFailure" ]

    has_updated_field="$(echo "$output" | jq -r '.hookSpecificOutput | has("updatedMCPToolOutput")' 2>/dev/null)"
    [ "$has_updated_field" = "false" ]

    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
    [[ "$ctx" == *"Mocked Result 1"* ]]
    [[ "$ctx" == *"RECOVERED RESULTS"* ]]
}

@test "event name: PostToolUseFailure additionalContext stays under 10K char cap" {
    create_curl_mock
    export TAVILY_MOCK_STATUS=success
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="fake-new-key-for-test"
    create_rotate_mock

    local input
    input="$(make_input_failure "mcp__tavily__tavily_search" "test-query" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    local ctx_len
    ctx_len="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext | length' 2>/dev/null)"
    [ "$ctx_len" -lt 10000 ]
}

@test "event name: PostToolUseFailure replay truncates huge content with marker" {
    local huge_mock="${TEST_TMPDIR}/curl"
    cat > "${huge_mock}" <<'MOCK_EOF'
#!/usr/bin/env bash
args=("$@")
url=""
for a in "${args[@]}"; do
    case "$a" in https://*|http://*) url="$a" ;; esac
done
if [[ "$url" == *"api.tavily.com/search"* ]]; then
    # Generate a 20KB result text (> 8500 truncation threshold)
    big="$(printf 'LONG%.0s' {1..3000})"
    jq -n --arg b "$big" '{query: "big", results: [{title: $b, url: "http://e.com", content: $b}]}'
    exit 0
fi
exit 99
MOCK_EOF
    chmod +x "${huge_mock}"

    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="fake-key"
    create_rotate_mock

    local input
    input="$(make_input_failure "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    local ctx_len ctx
    ctx_len="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext | length' 2>/dev/null)"
    [ "$ctx_len" -lt 10000 ]

    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
    [[ "$ctx" == *"truncated"* ]]
}

@test "event name: brave replay on PostToolUseFailure embeds content in additionalContext" {
    create_curl_mock
    export BRAVE_MOCK_STATUS=success
    unset AUTO_ROTATE_DISABLE_REPLAY
    export AUTO_ROTATE_REPLAY_KEY_OVERRIDE="fake-new-brave-key"
    create_rotate_mock

    local input
    input="$(make_input_failure "mcp__brave-search__brave_web_search" "test-query" "status code 429")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]

    local emitted ctx
    emitted="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    [ "$emitted" = "PostToolUseFailure" ]

    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
    [[ "$ctx" == *"Brave Mock 1"* ]]
    [[ "$ctx" == *"RECOVERED RESULTS"* ]]
}

@test "event name: cooldown path echoes correct event name" {
    create_rotate_mock
    mkdir -p "${AUTO_ROTATE_STATE_DIR}"
    date +%s > "${AUTO_ROTATE_STATE_DIR}/mcp-auto-rotate-tavily.ts"
    export AUTO_ROTATE_COOLDOWN_SEC=3600

    local input
    input="$(make_input_failure "mcp__tavily__tavily_search" "q" "status code 432")"
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local emitted
    emitted="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    [ "$emitted" = "PostToolUseFailure" ]
}

@test "event name: no hook_event_name in input defaults to PostToolUse" {
    create_rotate_mock
    local input
    input='{"tool_name":"mcp__tavily__tavily_search","tool_input":{"query":"q"},"tool_response":{"content":[{"type":"text","text":"status code 432"}],"isError":true}}'
    run bash -c "echo '${input}' | PATH='${TEST_TMPDIR}:${PATH}' bash '$HOOK'"
    [ "$status" -eq 0 ]
    local emitted
    emitted="$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
    [ "$emitted" = "PostToolUse" ]
}
