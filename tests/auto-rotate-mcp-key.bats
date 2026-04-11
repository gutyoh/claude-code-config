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
    # Default: no cooldown (0 seconds) for fast tests
    export AUTO_ROTATE_COOLDOWN_SEC=0
    # Hermetic default: disable transparent replay so tests don't hit real
    # Tavily/Brave APIs or burn credits. Replay-path tests explicitly unset
    # this and provide curl/key mocks.
    export AUTO_ROTATE_DISABLE_REPLAY=1
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
