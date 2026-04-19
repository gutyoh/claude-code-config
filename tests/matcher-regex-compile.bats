#!/usr/bin/env bats
# matcher-regex-compile.bats
# Path: tests/matcher-regex-compile.bats
#
# Validates that every `matcher` regex in .claude/settings.json:
#   1. Is non-null (or explicitly "" for Stop events, which is idiomatic)
#   2. Compiles as a POSIX Extended Regular Expression (what Claude Code uses)
#   3. Matches the tool names the hook it fires is logically meant to cover
#   4. Does NOT match tool names it is NOT meant to cover
#
# Catches silent "hook never fires" bugs caused by a typo in the matcher —
# Claude Code does not surface invalid regexes at runtime; it just silently
# fails to match them.
#
# Run: bats tests/matcher-regex-compile.bats
#      make test

SETTINGS="$BATS_TEST_DIRNAME/../.claude/settings.json"

setup() {
    command -v jq >/dev/null 2>&1 || skip "jq required"
}

# --- Helpers ---

# Collect every non-empty matcher string from settings.json. Empty strings
# are idiomatic for Stop events (match all) and are skipped by this check.
all_matchers() {
    jq -r '
        [.hooks | to_entries[] | .value[] | .matcher // empty]
        | map(select(. != ""))
        | .[]
    ' "$SETTINGS"
}

# Collect all matchers tied to a specific event (includes empty strings).
matchers_for_event() {
    local event="$1"
    jq -r --arg e "$event" '
        .hooks[$e] // []
        | map(.matcher)
        | .[]
        | if . == null then "" else . end
    ' "$SETTINGS"
}

# Collect (matcher, command) pairs for a specific event.
hooks_for_event() {
    local event="$1"
    jq -r --arg e "$event" '
        .hooks[$e] // []
        | map(
            .matcher as $m |
            .hooks[]? |
            [$m, .command // ""] |
            @tsv
        )
        | .[]
    ' "$SETTINGS"
}

# ============================================================================
# Schema + compilation
# ============================================================================

@test "settings.json parses as valid JSON" {
    jq empty "$SETTINGS"
}

@test "at least one matcher exists in PreToolUse" {
    local n
    n=$(matchers_for_event PreToolUse | wc -l | tr -d ' ')
    [ "$n" -gt 0 ]
}

@test "every non-empty matcher compiles as POSIX ERE" {
    # Test each matcher against a neutral probe string. grep -E returns:
    #   0 if the regex compiled AND matched
    #   1 if compiled but did not match  (fine)
    #   2 if the regex failed to compile (the bug we're catching)
    # Any status ≠ 2 is acceptable. Using `|| rc=$?` so bats' `set -e`
    # doesn't abort on grep's no-match exit 1.
    local failed=0
    while IFS= read -r matcher; do
        [ -z "$matcher" ] && continue
        local rc=0
        printf 'tool-name-probe\n' | grep -E -- "$matcher" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 2 ]; then
            echo "MATCHER FAILS TO COMPILE: '$matcher'"
            failed=$((failed + 1))
        fi
    done < <(all_matchers)

    if [ "$failed" -gt 0 ]; then
        echo ""
        echo "$failed matcher(s) in settings.json are not valid ERE."
        echo "Claude Code will SILENTLY skip these hooks — no runtime error is raised."
        false
    fi
}

# ============================================================================
# Semantic matches — every hook fires on what it claims to handle
# ============================================================================

@test "PreToolUse: Bash matcher fires on Bash tool name" {
    local matched="false"
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"enforce-git-pull-rebase.sh" ]]; then
            # This hook must match the literal tool name "Bash"
            if printf 'Bash' | grep -qE -- "$matcher"; then
                matched="true"
            fi
        fi
    done < <(hooks_for_event PreToolUse)
    [ "$matched" = "true" ]
}

@test "PreToolUse: ide-diagnostics matcher fires on mcp__ide__getDiagnostics" {
    local matched="false"
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"open-file-in-ide.sh" ]]; then
            if printf 'mcp__ide__getDiagnostics' | grep -qE -- "$matcher"; then
                matched="true"
            fi
        fi
    done < <(hooks_for_event PreToolUse)
    [ "$matched" = "true" ]
}

@test "PreToolUse: guard-mcp-key fires on tavily AND brave-search tools" {
    local t_match="false" b_match="false"
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"guard-mcp-key.sh" ]]; then
            if printf 'mcp__tavily__tavily_search' | grep -qE -- "$matcher"; then
                t_match="true"
            fi
            if printf 'mcp__brave-search__brave_web_search' | grep -qE -- "$matcher"; then
                b_match="true"
            fi
        fi
    done < <(hooks_for_event PreToolUse)
    [ "$t_match" = "true" ]
    [ "$b_match" = "true" ]
}

@test "PreToolUse: rate-limit-brave matcher fires ONLY on brave (not tavily)" {
    local b_match="false" t_match="false"
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"rate-limit-brave-search.sh" ]]; then
            if printf 'mcp__brave-search__brave_web_search' | grep -qE -- "$matcher"; then
                b_match="true"
            fi
            if printf 'mcp__tavily__tavily_search' | grep -qE -- "$matcher"; then
                t_match="true"
            fi
        fi
    done < <(hooks_for_event PreToolUse)
    [ "$b_match" = "true" ]
    [ "$t_match" = "false" ]
}

@test "PreToolUse: refresh-usage-cache matcher fires on representative tools" {
    local found=0
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"refresh-usage-cache.sh" ]]; then
            # Must match at least these representative tool names
            for probe in Bash Edit Read mcp__tavily__tavily_search TaskCreate; do
                if printf '%s' "$probe" | grep -qE -- "$matcher"; then
                    found=$((found + 1))
                fi
            done
        fi
    done < <(hooks_for_event PreToolUse)
    # The current matcher is ".*" which matches all 5 probes.
    # If someone tightens it to exclude TaskCreate, this test still passes
    # as long as at least Bash/Edit/Read/mcp__* match.
    [ "$found" -ge 4 ]
}

@test "PostToolUse: auto-rotate matcher fires on both tavily and brave" {
    local t_match="false" b_match="false"
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"auto-rotate-mcp-key.sh" ]]; then
            if printf 'mcp__tavily__tavily_search' | grep -qE -- "$matcher"; then
                t_match="true"
            fi
            if printf 'mcp__brave-search__brave_web_search' | grep -qE -- "$matcher"; then
                b_match="true"
            fi
        fi
    done < <(hooks_for_event PostToolUse)
    [ "$t_match" = "true" ]
    [ "$b_match" = "true" ]
}

# ============================================================================
# Semantic non-matches — no hook fires on unrelated tools it shouldn't
# ============================================================================

@test "guard-mcp-key does NOT fire on Bash" {
    # A non-MCP tool call must not be gated by the MCP key guard.
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"guard-mcp-key.sh" ]]; then
            if printf 'Bash' | grep -qE -- "$matcher"; then
                echo "guard-mcp-key matcher '$matcher' incorrectly matches Bash"
                false
            fi
        fi
    done < <(hooks_for_event PreToolUse)
}

@test "rate-limit-brave does NOT fire on mcp__ide__getDiagnostics" {
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"rate-limit-brave-search.sh" ]]; then
            if printf 'mcp__ide__getDiagnostics' | grep -qE -- "$matcher"; then
                echo "rate-limit matcher '$matcher' incorrectly matches ide tool"
                false
            fi
        fi
    done < <(hooks_for_event PreToolUse)
}

@test "auto-rotate does NOT fire on non-MCP Bash tool" {
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"auto-rotate-mcp-key.sh" ]]; then
            if printf 'Bash' | grep -qE -- "$matcher"; then
                echo "auto-rotate matcher '$matcher' incorrectly matches Bash"
                false
            fi
        fi
    done < <(hooks_for_event PostToolUse)
}

@test "ide-diagnostics hook does NOT fire on unrelated MCP tools" {
    while IFS=$'\t' read -r matcher cmd; do
        [ -z "$matcher" ] && continue
        if [[ "$cmd" == *"open-file-in-ide.sh" ]]; then
            if printf 'mcp__tavily__tavily_search' | grep -qE -- "$matcher"; then
                echo "ide matcher '$matcher' incorrectly matches tavily"
                false
            fi
        fi
    done < <(hooks_for_event PreToolUse)
}

# ============================================================================
# Stop event convention (empty matcher = match all)
# ============================================================================

@test "Stop event: at least one Stop hook is configured" {
    # The Stop hook traditionally uses matcher: "" to match every stop event.
    # Verify at least one Stop entry exists (empty matcher is valid here).
    local stop_count
    stop_count=$(jq -r '.hooks.Stop // [] | length' "$SETTINGS")
    [ "$stop_count" -gt 0 ]
}

# ============================================================================
# Structural — every entry has required fields
# ============================================================================

@test "every hook entry has a matcher field (may be empty string)" {
    local missing
    missing=$(jq -r '
        [.hooks | to_entries[] | .value[] | select(.matcher == null)]
        | length
    ' "$SETTINGS")
    [ "$missing" -eq 0 ]
}

@test "every matcher is a string (never a number or bool)" {
    local non_string
    non_string=$(jq -r '
        [.hooks | to_entries[] | .value[] | select(.matcher != null and (.matcher | type) != "string")]
        | length
    ' "$SETTINGS")
    [ "$non_string" -eq 0 ]
}
