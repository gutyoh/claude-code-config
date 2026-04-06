#!/usr/bin/env bats
# guard-mcp-key.bats
# Path: tests/guard-mcp-key.bats
#
# Unit + integration tests for the guard-mcp-key.sh PreToolUse hook.
# Tests that MCP calls are blocked when API keys are missing, and
# allowed when keys are present.
#
# Run: bats tests/guard-mcp-key.bats
#      make test

HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/guard-mcp-key.sh"
REPO_ROOT="$BATS_TEST_DIRNAME/.."

# --- Helpers ---

# Build PreToolUse JSON input
make_input() {
    local tool_name="$1"
    jq -n --arg tn "${tool_name}" \
        '{ tool_name: $tn, tool_input: { query: "test" } }'
}

# --- Setup / Teardown ---

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# ==========================================================================
# UNIT TESTS: Script basics
# ==========================================================================

@test "hook script exists and is executable" {
    [ -x "$HOOK" ]
}

@test "handles empty stdin gracefully" {
    run bash -c "echo '' | TAVILY_API_KEY=set bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "handles /dev/null stdin gracefully" {
    run bash -c "TAVILY_API_KEY=set bash '$HOOK' < /dev/null"
    [ "$status" -eq 0 ]
}

@test "handles malformed JSON gracefully" {
    run bash -c "echo 'not json' | TAVILY_API_KEY=set bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "handles JSON with no tool_name gracefully" {
    run bash -c "echo '{\"foo\":\"bar\"}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
}

# ==========================================================================
# UNIT TESTS: Allows calls when key IS set
# ==========================================================================

@test "allows tavily call when TAVILY_API_KEY is set" {
    local input
    input="$(make_input "mcp__tavily__tavily_search")"
    run bash -c "echo '${input}' | TAVILY_API_KEY=tvly-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows tavily_extract when TAVILY_API_KEY is set" {
    local input
    input="$(make_input "mcp__tavily__tavily_extract")"
    run bash -c "echo '${input}' | TAVILY_API_KEY=tvly-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "allows tavily_crawl when TAVILY_API_KEY is set" {
    local input
    input="$(make_input "mcp__tavily__tavily_crawl")"
    run bash -c "echo '${input}' | TAVILY_API_KEY=tvly-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "allows tavily_map when TAVILY_API_KEY is set" {
    local input
    input="$(make_input "mcp__tavily__tavily_map")"
    run bash -c "echo '${input}' | TAVILY_API_KEY=tvly-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "allows tavily_research when TAVILY_API_KEY is set" {
    local input
    input="$(make_input "mcp__tavily__tavily_research")"
    run bash -c "echo '${input}' | TAVILY_API_KEY=tvly-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "allows brave call when BRAVE_API_KEY is set" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search")"
    run bash -c "echo '${input}' | BRAVE_API_KEY=BSA-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "allows brave_news_search when BRAVE_API_KEY is set" {
    local input
    input="$(make_input "mcp__brave-search__brave_news_search")"
    run bash -c "echo '${input}' | BRAVE_API_KEY=BSA-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "allows brave_image_search when BRAVE_API_KEY is set" {
    local input
    input="$(make_input "mcp__brave-search__brave_image_search")"
    run bash -c "echo '${input}' | BRAVE_API_KEY=BSA-test-key bash '$HOOK'"
    [ "$status" -eq 0 ]
}

# ==========================================================================
# UNIT TESTS: Blocks calls when key is MISSING
# ==========================================================================

@test "blocks tavily call when TAVILY_API_KEY is unset" {
    local input
    input="$(make_input "mcp__tavily__tavily_search")"
    run bash -c "echo '${input}' | env -u TAVILY_API_KEY bash '$HOOK'"
    [ "$status" -eq 2 ]
}

@test "blocks tavily call when TAVILY_API_KEY is empty string" {
    local input
    input="$(make_input "mcp__tavily__tavily_search")"
    run bash -c "echo '${input}' | TAVILY_API_KEY='' bash '$HOOK'"
    [ "$status" -eq 2 ]
}

@test "blocks brave call when BRAVE_API_KEY is unset" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search")"
    run bash -c "echo '${input}' | env -u BRAVE_API_KEY bash '$HOOK'"
    [ "$status" -eq 2 ]
}

@test "blocks brave call when BRAVE_API_KEY is empty string" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search")"
    run bash -c "echo '${input}' | BRAVE_API_KEY='' bash '$HOOK'"
    [ "$status" -eq 2 ]
}

# ==========================================================================
# UNIT TESTS: Error message content
# ==========================================================================

@test "error message mentions the missing env var (TAVILY_API_KEY)" {
    local input
    input="$(make_input "mcp__tavily__tavily_search")"
    run bash -c "echo '${input}' | env -u TAVILY_API_KEY bash '$HOOK' 2>&1"
    [ "$status" -eq 2 ]
    [[ "$output" == *"TAVILY_API_KEY"* ]]
}

@test "error message mentions the missing env var (BRAVE_API_KEY)" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search")"
    run bash -c "echo '${input}' | env -u BRAVE_API_KEY bash '$HOOK' 2>&1"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BRAVE_API_KEY"* ]]
}

@test "error message suggests /web-search fallback" {
    local input
    input="$(make_input "mcp__tavily__tavily_search")"
    run bash -c "echo '${input}' | env -u TAVILY_API_KEY bash '$HOOK' 2>&1"
    [ "$status" -eq 2 ]
    [[ "$output" == *"/web-search"* ]]
}

@test "error message suggests setting key in .env or shell export" {
    local input
    input="$(make_input "mcp__tavily__tavily_search")"
    run bash -c "echo '${input}' | env -u TAVILY_API_KEY bash '$HOOK' 2>&1"
    [ "$status" -eq 2 ]
    [[ "$output" == *".env"* ]]
    [[ "$output" == *"export"* ]]
}

# ==========================================================================
# UNIT TESTS: Pass-through for non-MCP tools
# ==========================================================================

@test "passes through Bash tool calls" {
    local input
    input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "passes through Read tool calls" {
    local input
    input='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}'
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "passes through unknown MCP tools" {
    local input
    input="$(make_input "mcp__other__some_tool")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "passes through IDE MCP tools" {
    local input
    input="$(make_input "mcp__ide__getDiagnostics")"
    run bash -c "echo '${input}' | bash '$HOOK'"
    [ "$status" -eq 0 ]
}

# ==========================================================================
# UNIT TESTS: Key set for one service doesn't affect the other
# ==========================================================================

@test "brave key set does NOT satisfy tavily check" {
    local input
    input="$(make_input "mcp__tavily__tavily_search")"
    run bash -c "echo '${input}' | BRAVE_API_KEY=set env -u TAVILY_API_KEY bash '$HOOK'"
    [ "$status" -eq 2 ]
}

@test "tavily key set does NOT satisfy brave check" {
    local input
    input="$(make_input "mcp__brave-search__brave_web_search")"
    run bash -c "echo '${input}' | TAVILY_API_KEY=set env -u BRAVE_API_KEY bash '$HOOK'"
    [ "$status" -eq 2 ]
}

# ==========================================================================
# INTEGRATION: settings.json validation
# ==========================================================================

@test "settings.json: guard hook is configured in PreToolUse" {
    run jq '[.hooks.PreToolUse[].hooks[].command] | map(select(contains("guard-mcp-key"))) | length' \
        "${REPO_ROOT}/.claude/settings.json"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "settings.json: guard matcher covers tavily and brave-search" {
    local matcher
    matcher="$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | contains("guard-mcp-key")) | .matcher' \
        "${REPO_ROOT}/.claude/settings.json")"
    echo "mcp__tavily__tavily_search" | grep -qE "${matcher}"
    echo "mcp__brave-search__brave_web_search" | grep -qE "${matcher}"
}

@test "settings.json: guard hook comes BEFORE rate-limit hook" {
    # Extract ordered list of hook commands for MCP-related matchers
    local guard_idx rate_idx
    guard_idx="$(jq '[.hooks.PreToolUse[].hooks[].command] | to_entries[] | select(.value | contains("guard-mcp-key")) | .key' \
        "${REPO_ROOT}/.claude/settings.json")"
    rate_idx="$(jq '[.hooks.PreToolUse[].hooks[].command] | to_entries[] | select(.value | contains("rate-limit-brave")) | .key' \
        "${REPO_ROOT}/.claude/settings.json")"
    # Guard index must be less than rate-limit index
    [ "$guard_idx" -lt "$rate_idx" ]
}

@test "settings.json: guard matcher does NOT match non-MCP tools" {
    local matcher
    matcher="$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | contains("guard-mcp-key")) | .matcher' \
        "${REPO_ROOT}/.claude/settings.json")"
    if echo "Bash" | grep -qE "${matcher}" 2>/dev/null; then
        false
    fi
}

# ==========================================================================
# INTEGRATION: Hook ordering with auto-rotate
# ==========================================================================

@test "settings.json: auto-rotate is PostToolUse (runs after guard)" {
    local auto_rotate_hook_type
    auto_rotate_hook_type="$(jq -r 'if .hooks.PostToolUse then "PostToolUse" else "missing" end' \
        "${REPO_ROOT}/.claude/settings.json")"
    [ "$auto_rotate_hook_type" = "PostToolUse" ]

    # Verify auto-rotate is in PostToolUse, not PreToolUse
    local in_pre
    in_pre="$(jq '[.hooks.PreToolUse[].hooks[].command] | map(select(contains("auto-rotate"))) | length' \
        "${REPO_ROOT}/.claude/settings.json")"
    [ "$in_pre" = "0" ]
}

# ==========================================================================
# INTEGRATION: CLAUDE.md documentation
# ==========================================================================

@test "CLAUDE.md: documents guard-mcp-key hook" {
    grep -q "guard-mcp-key" "${REPO_ROOT}/CLAUDE.md"
}

@test "CLAUDE.md: guard hook listed in repo structure" {
    grep -q "guard-mcp-key.sh" "${REPO_ROOT}/CLAUDE.md"
}
