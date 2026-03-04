#!/usr/bin/env bats
# langfuse-skill.bats
# Path: tests/langfuse-skill.bats
#
# Unit + integration tests for the Langfuse skill, agent, and CLI.
# Validates file structure, frontmatter, internal links, CLI availability,
# and (when Langfuse is reachable) actual API queries.
#
# Run: bats tests/langfuse-skill.bats
#      make test

SKILL_DIR="$BATS_TEST_DIRNAME/../.claude/skills/langfuse"
AGENT_FILE="$BATS_TEST_DIRNAME/../.claude/agents/langfuse-expert.md"
CLAUDE_MD="$BATS_TEST_DIRNAME/../CLAUDE.md"

# ==========================================================================
# UNIT TESTS: Skill file structure
# ==========================================================================

@test "skill: SKILL.md exists" {
    [ -f "$SKILL_DIR/SKILL.md" ]
}

@test "skill: core.md exists" {
    [ -f "$SKILL_DIR/core.md" ]
}

@test "skill: references/cli.md exists" {
    [ -f "$SKILL_DIR/references/cli.md" ]
}

@test "skill: references/instrumentation.md exists" {
    [ -f "$SKILL_DIR/references/instrumentation.md" ]
}

@test "skill: references/prompt-migration.md exists" {
    [ -f "$SKILL_DIR/references/prompt-migration.md" ]
}

# ==========================================================================
# UNIT TESTS: SKILL.md frontmatter and content
# ==========================================================================

@test "skill: SKILL.md has valid YAML frontmatter" {
    # Check it starts with --- and has a closing ---
    head -1 "$SKILL_DIR/SKILL.md" | grep -q "^---$"
    # Find closing --- (line 2+)
    local closing_line
    closing_line=$(tail -n +2 "$SKILL_DIR/SKILL.md" | grep -n "^---$" | head -1 | cut -d: -f1)
    [ -n "$closing_line" ]
    [ "$closing_line" -gt 0 ]
}

@test "skill: SKILL.md frontmatter has name field" {
    grep -q "^name: langfuse" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md frontmatter has description field" {
    grep -q "^description:" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md references core.md" {
    grep -q "\[core.md\](core.md)" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md references cli.md" {
    grep -q "\[references/cli.md\](references/cli.md)" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md references instrumentation.md" {
    grep -q "\[references/instrumentation.md\](references/instrumentation.md)" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md references prompt-migration.md" {
    grep -q "\[references/prompt-migration.md\](references/prompt-migration.md)" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md contains langfuse-cli commands" {
    grep -q "npx langfuse-cli" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md contains --json flag usage" {
    grep -q "\-\-json" "$SKILL_DIR/SKILL.md"
}

@test "skill: SKILL.md contains health check command" {
    grep -q "healths list" "$SKILL_DIR/SKILL.md"
}

# ==========================================================================
# UNIT TESTS: core.md content
# ==========================================================================

@test "core: documents three auth methods" {
    local count
    count=$(grep -c "Method [123]" "$SKILL_DIR/core.md")
    [ "$count" -eq 3 ]
}

@test "core: documents v2 endpoint preference" {
    grep -q "observations-v2s" "$SKILL_DIR/core.md"
    grep -q "metrics-v2s" "$SKILL_DIR/core.md"
    grep -q "score-v2s" "$SKILL_DIR/core.md"
}

@test "core: documents safety guardrails" {
    grep -q "read-only" "$SKILL_DIR/core.md"
    grep -q "Destructive" "$SKILL_DIR/core.md"
}

@test "core: documents 26 resources" {
    grep -q "26" "$SKILL_DIR/core.md"
}

# ==========================================================================
# UNIT TESTS: references/cli.md content
# ==========================================================================

@test "cli ref: documents trace filtering" {
    grep -q "errorCount" "$SKILL_DIR/references/cli.md"
    grep -q "totalCost" "$SKILL_DIR/references/cli.md"
}

@test "cli ref: documents session analysis" {
    grep -q "sessions list" "$SKILL_DIR/references/cli.md"
    grep -q "sessions get" "$SKILL_DIR/references/cli.md"
}

@test "cli ref: documents prompt management" {
    grep -q "prompts list" "$SKILL_DIR/references/cli.md"
    grep -q "prompts create" "$SKILL_DIR/references/cli.md"
}

@test "cli ref: documents advanced JSON filter syntax" {
    grep -q "\-\-filter" "$SKILL_DIR/references/cli.md"
}

# ==========================================================================
# UNIT TESTS: references/instrumentation.md content
# ==========================================================================

@test "instrumentation ref: documents Python decorator pattern" {
    grep -q "@observe()" "$SKILL_DIR/references/instrumentation.md"
}

@test "instrumentation ref: documents OpenTelemetry" {
    grep -q "opentelemetry\|OpenTelemetry" "$SKILL_DIR/references/instrumentation.md"
}

@test "instrumentation ref: documents framework integrations table" {
    grep -q "LangChain" "$SKILL_DIR/references/instrumentation.md"
    grep -q "LlamaIndex" "$SKILL_DIR/references/instrumentation.md"
}

# ==========================================================================
# UNIT TESTS: references/prompt-migration.md content
# ==========================================================================

@test "prompt-migration ref: documents 8-step flow" {
    grep -q "Step 1" "$SKILL_DIR/references/prompt-migration.md"
    grep -q "Step 8" "$SKILL_DIR/references/prompt-migration.md"
}

@test "prompt-migration ref: documents template syntax" {
    grep -q "{{variable}}" "$SKILL_DIR/references/prompt-migration.md"
}

@test "prompt-migration ref: documents label-based deployment" {
    grep -q "production" "$SKILL_DIR/references/prompt-migration.md"
    grep -q "staging" "$SKILL_DIR/references/prompt-migration.md"
}

# ==========================================================================
# UNIT TESTS: Agent file
# ==========================================================================

@test "agent: langfuse-expert.md exists" {
    [ -f "$AGENT_FILE" ]
}

@test "agent: has valid YAML frontmatter" {
    head -1 "$AGENT_FILE" | grep -q "^---$"
    local closing_line
    closing_line=$(tail -n +2 "$AGENT_FILE" | grep -n "^---$" | head -1 | cut -d: -f1)
    [ -n "$closing_line" ]
    [ "$closing_line" -gt 0 ]
}

@test "agent: frontmatter has name field" {
    grep -q "^name: langfuse-expert" "$AGENT_FILE"
}

@test "agent: frontmatter has description field" {
    grep -q "^description:" "$AGENT_FILE"
}

@test "agent: frontmatter references langfuse skill" {
    grep -q "langfuse" "$AGENT_FILE"
    grep -q "skills:" "$AGENT_FILE"
}

@test "agent: frontmatter has model: inherit" {
    grep -q "^model: inherit" "$AGENT_FILE"
}

@test "agent: frontmatter has color" {
    grep -q "^color:" "$AGENT_FILE"
}

@test "agent: body references langfuse-cli" {
    grep -q "langfuse-cli" "$AGENT_FILE"
}

@test "agent: body references v2 endpoints" {
    grep -q "observations-v2s" "$AGENT_FILE"
    grep -q "score-v2s" "$AGENT_FILE"
}

# ==========================================================================
# UNIT TESTS: CLAUDE.md integration
# ==========================================================================

@test "CLAUDE.md: lists langfuse skill" {
    grep -q "langfuse.*Langfuse observability" "$CLAUDE_MD"
}

@test "CLAUDE.md: lists langfuse-expert agent" {
    grep -q "langfuse-expert" "$CLAUDE_MD"
}

@test "CLAUDE.md: lists langfuse directory in tree" {
    grep -q "langfuse/" "$CLAUDE_MD"
}

@test "CLAUDE.md: documents LANGFUSE env vars" {
    grep -q "LANGFUSE_PUBLIC_KEY" "$CLAUDE_MD"
    grep -q "LANGFUSE_SECRET_KEY" "$CLAUDE_MD"
    grep -q "LANGFUSE_HOST" "$CLAUDE_MD"
}

# ==========================================================================
# UNIT TESTS: All internal markdown links resolve
# ==========================================================================

@test "skill: all markdown links in SKILL.md resolve to existing files" {
    local failed=0
    while IFS= read -r link; do
        local target="$SKILL_DIR/$link"
        if [ ! -f "$target" ]; then
            echo "BROKEN LINK: $link -> $target" >&2
            failed=1
        fi
    done < <(grep -oE '\[[^]]+\]\([^)]+\)' "$SKILL_DIR/SKILL.md" | sed -E 's/^[^(]*\(([^)]*)\).*$/\1/' | grep -v '^http')
    [ "$failed" -eq 0 ]
}

# ==========================================================================
# INTEGRATION TESTS: langfuse-cli availability
# ==========================================================================

@test "integration: langfuse-cli is available via npx" {
    # This verifies npx can resolve the package (may download on first run)
    run npx -y langfuse-cli --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"langfuse"* ]]
}

@test "integration: langfuse-cli api __schema lists 26 resources" {
    run npx -y langfuse-cli api __schema
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resources: 26"* ]]
}

@test "integration: langfuse-cli api traces --help shows list action" {
    run npx -y langfuse-cli api traces --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"get"* ]]
}

@test "integration: langfuse-cli api prompts --help shows CRUD actions" {
    run npx -y langfuse-cli api prompts --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"get"* ]]
    [[ "$output" == *"create"* ]]
}

@test "integration: langfuse-cli api traces list --help shows filter options" {
    run npx -y langfuse-cli api traces list --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--limit"* ]]
    [[ "$output" == *"--filter"* ]]
    [[ "$output" == *"--json"* ]]
}

@test "integration: langfuse-cli api traces list --curl generates valid curl" {
    # Use dummy credentials to generate curl preview without executing
    run npx -y langfuse-cli \
        --host https://example.com --public-key pk-test --secret-key sk-test \
        api traces list --limit 1 --curl
    [ "$status" -eq 0 ]
    [[ "$output" == *"curl"* ]]
    [[ "$output" == *"traces"* ]]
}

# ==========================================================================
# INTEGRATION TESTS: Live Langfuse instance (skipped if unavailable)
# ==========================================================================

# Helper: check if Langfuse is reachable
langfuse_available() {
    [ -n "${LANGFUSE_PUBLIC_KEY:-}" ] && \
    [ -n "${LANGFUSE_SECRET_KEY:-}" ] && \
    [ -n "${LANGFUSE_HOST:-}" ] && \
    curl -sf "${LANGFUSE_HOST}/api/public/health" -o /dev/null 2>/dev/null
}

@test "integration-live: health check passes (requires running Langfuse)" {
    if ! langfuse_available; then
        skip "Langfuse not available (set LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST)"
    fi
    run npx -y langfuse-cli api healths list --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
}

@test "integration-live: traces list returns valid JSON (requires running Langfuse)" {
    if ! langfuse_available; then
        skip "Langfuse not available (set LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST)"
    fi
    run npx -y langfuse-cli api traces list --limit 3 --json
    [ "$status" -eq 0 ]
    # Validate it's JSON (starts with { or [)
    [[ "$output" =~ ^[\{\[] ]]
}

@test "integration-live: prompts list returns valid JSON (requires running Langfuse)" {
    if ! langfuse_available; then
        skip "Langfuse not available (set LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST)"
    fi
    run npx -y langfuse-cli api prompts list --json
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[\{\[] ]]
}

@test "integration-live: sessions list returns valid JSON (requires running Langfuse)" {
    if ! langfuse_available; then
        skip "Langfuse not available (set LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST)"
    fi
    run npx -y langfuse-cli api sessions list --limit 3 --json
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[\{\[] ]]
}

@test "integration-live: trace get by ID works (requires running Langfuse with traces)" {
    if ! langfuse_available; then
        skip "Langfuse not available (set LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST)"
    fi
    # Get the first trace ID
    local trace_id
    trace_id=$(npx -y langfuse-cli api traces list --limit 1 --json 2>/dev/null \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "")
    if [ -z "$trace_id" ]; then
        skip "No traces found in Langfuse instance"
    fi
    run npx -y langfuse-cli api traces get "$trace_id" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"$trace_id"* ]]
}
