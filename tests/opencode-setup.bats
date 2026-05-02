#!/usr/bin/env bats
# opencode-setup.bats
# Path: tests/opencode-setup.bats
#
# Unit + integration tests for OpenCode parallel install (lib/setup/opencode.sh).
# Verifies detection tiers, agent translation, opencode.json generation,
# AGENTS.md symlink, and idempotent re-runs.
#
# Run: bats tests/opencode-setup.bats

# shellcheck disable=SC2030,SC2031 # false positives — each @test is a subshell by design

OPENCODE_SH="$BATS_TEST_DIRNAME/../lib/setup/opencode.sh"
MCP_SH="$BATS_TEST_DIRNAME/../lib/setup/mcp.sh"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# --- Setup / Teardown ---

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d)"

    export OPENCODE_CONFIG_DIR_OVERRIDE="${TEST_TMPDIR}/opencode"
    export REPO_DIR="${TEST_TMPDIR}/repo"
    mkdir -p "${REPO_DIR}/.claude/agents" "${REPO_DIR}/.claude/skills"
    export CLAUDE_JSON="${TEST_TMPDIR}/claude.json"

    INSTALL_MCP_SERVERS=("brave-search" "tavily")

    # shellcheck source=../lib/setup/mcp.sh
    source "$MCP_SH"
    # shellcheck source=../lib/setup/opencode.sh
    source "$OPENCODE_SH"

    # Force envfile backend by default — tests that need doppler override locally.
    detect_mcp_backend() { echo "envfile"; }

    unset OPENCODE_FORCE
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
    unset OPENCODE_FORCE OPENCODE_CONFIG_DIR_OVERRIDE
}

# ==========================================================================
# UNIT TESTS: detect_opencode tiers
# ==========================================================================

@test "detect_opencode: Tier 0 OPENCODE_FORCE=1 returns yes regardless of binary" {
    export OPENCODE_FORCE=1
    run detect_opencode
    [ "$status" -eq 0 ]
}

@test "detect_opencode: Tier 0 OPENCODE_FORCE=0 returns no regardless of binary" {
    export OPENCODE_FORCE=0
    run detect_opencode
    [ "$status" -eq 1 ]
}

@test "detect_opencode: Tier 0 accepts true/yes/on aliases" {
    export OPENCODE_FORCE=true
    run detect_opencode
    [ "$status" -eq 0 ]

    export OPENCODE_FORCE=yes
    run detect_opencode
    [ "$status" -eq 0 ]

    export OPENCODE_FORCE=on
    run detect_opencode
    [ "$status" -eq 0 ]
}

@test "detect_opencode: Tier 0 accepts false/no/off aliases" {
    export OPENCODE_FORCE=false
    run detect_opencode
    [ "$status" -eq 1 ]

    export OPENCODE_FORCE=no
    run detect_opencode
    [ "$status" -eq 1 ]

    export OPENCODE_FORCE=off
    run detect_opencode
    [ "$status" -eq 1 ]
}

@test "detect_opencode: Tier 2 returns yes when config dir exists (no binary)" {
    # No binary, but config dir exists
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    # Re-source to pick up override
    source "$OPENCODE_SH"

    # Mask any opencode binary on PATH for this test
    export PATH="${TEST_TMPDIR}/empty-path:${PATH}"
    mkdir -p "${TEST_TMPDIR}/empty-path"

    if command -v opencode &>/dev/null; then
        skip "opencode binary on PATH cannot be masked safely; Tier 1 will fire first"
    fi

    run detect_opencode
    [ "$status" -eq 0 ]
}

@test "detect_opencode: returns no when no binary, no dir, no force" {
    # Empty PATH so opencode is unreachable
    local blank="${TEST_TMPDIR}/blank-path"
    mkdir -p "${blank}"
    PATH="${blank}" run detect_opencode
    [ "$status" -eq 1 ]
}

@test "opencode_detect_label: reports forced state correctly" {
    export OPENCODE_FORCE=1
    run opencode_detect_label
    [ "$status" -eq 0 ]
    [[ "$output" == *"forced"* ]]

    export OPENCODE_FORCE=0
    run opencode_detect_label
    [ "$status" -eq 0 ]
    [[ "$output" == *"forced"* ]]
}

@test "opencode_detect_label: reports config-dir adoption" {
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    local blank="${TEST_TMPDIR}/blank-path"
    mkdir -p "${blank}"
    if PATH="${blank}" command -v opencode &>/dev/null; then
        skip "opencode binary still resolvable in masked PATH"
    fi
    PATH="${blank}" run opencode_detect_label
    [[ "$output" == *"config dir"* ]]
}

# ==========================================================================
# UNIT TESTS: agent frontmatter translation
# ==========================================================================

_make_agent() {
    local name="$1" body="$2"
    cat > "${REPO_DIR}/.claude/agents/${name}.md" <<EOF
${body}
EOF
}

@test "translate: drops name: line (filename = name in OpenCode)" {
    _make_agent "test-agent" '---
name: test-agent
description: Test agent for translation
model: inherit
color: blue
---
body content here'

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/test-agent.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/test-agent.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/test-agent.md")"
    [[ "$out" != *"name: test-agent"* ]]
}

@test "translate: drops model: inherit (subagent inherits from caller)" {
    _make_agent "inheritor" '---
name: inheritor
description: Inherits model from caller
model: inherit
color: red
---
body'

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/inheritor.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/inheritor.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/inheritor.md")"
    [[ "$out" != *"model: inherit"* ]]
}

@test "translate: drops hooks: block (no OpenCode equivalent)" {
    _make_agent "hooked" '---
name: hooked
description: Has hooks block
model: inherit
color: green
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "~/.claude/hooks/sql-guardrail.sh"
---
body'

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/hooked.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/hooked.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/hooked.md")"
    [[ "$out" != *"hooks:"* ]]
    [[ "$out" != *"sql-guardrail"* ]]
    # Body must survive
    [[ "$out" == *"body"* ]]
}

@test "translate: drops tools: CSV (uses OpenCode default permissions)" {
    _make_agent "tooled" '---
name: tooled
description: Has tools CSV
tools: Read, Write, Edit, Bash, Glob, Grep
model: inherit
color: purple
---
body'

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/tooled.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/tooled.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/tooled.md")"
    [[ "$out" != *"tools: Read"* ]]
}

@test "translate: adds mode: subagent if not present" {
    _make_agent "modeless" '---
name: modeless
description: No mode field
model: inherit
color: cyan
---
body'

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/modeless.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/modeless.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/modeless.md")"
    [[ "$out" == *"mode: subagent"* ]]
}

@test "translate: preserves description, skills, body" {
    _make_agent "preserve" '---
name: preserve
description: Long description that should survive
model: inherit
color: orange
skills:
  - python-standards
  - rust-standards
---
This is the body.

It has multiple paragraphs.'

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/preserve.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/preserve.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/preserve.md")"
    [[ "$out" == *"description: Long description that should survive"* ]]
    [[ "$out" == *"skills:"* ]]
    [[ "$out" == *"- python-standards"* ]]
    [[ "$out" == *"- rust-standards"* ]]
    [[ "$out" == *"This is the body."* ]]
    [[ "$out" == *"multiple paragraphs"* ]]
}

# ==========================================================================
# UNIT TESTS: color translation (Claude Code named → OpenCode theme tokens)
# ==========================================================================

_translate_color_check() {
    local color_in="$1" color_out_expected="$2"
    local name="color-${color_in}"
    cat > "${REPO_DIR}/.claude/agents/${name}.md" <<EOF
---
name: ${name}
description: Color test
model: inherit
color: ${color_in}
---
body
EOF

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/${name}.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/${name}.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/${name}.md")"

    if [[ -z "${color_out_expected}" ]]; then
        # Expected no color line at all
        ! grep -q "^color:" "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/${name}.md"
    else
        [[ "$out" == *"color: ${color_out_expected}"* ]]
    fi
}

@test "translate color: red -> error" {
    _translate_color_check red error
}

@test "translate color: green -> success" {
    _translate_color_check green success
}

@test "translate color: yellow -> warning" {
    _translate_color_check yellow warning
}

@test "translate color: orange -> warning" {
    _translate_color_check orange warning
}

@test "translate color: blue -> info" {
    _translate_color_check blue info
}

@test "translate color: cyan -> info" {
    _translate_color_check cyan info
}

@test "translate color: purple -> accent" {
    _translate_color_check purple accent
}

@test "translate color: pink -> accent" {
    _translate_color_check pink accent
}

@test "translate color: existing theme token (success) preserved" {
    _translate_color_check success success
}

@test "translate color: hex #fab283 preserved" {
    _translate_color_check "#fab283" "#fab283"
}

@test "translate color: unknown color (mauve) dropped entirely" {
    _translate_color_check mauve ""
}

@test "translate color: zod regex validates output (no invalid colors emitted)" {
    # Translate every Claude Code agent in the repo and assert none has an
    # invalid color line. This is the canary against ConfigInvalidError.
    local repo_agents="${BATS_TEST_DIRNAME}/../.claude/agents"
    if [[ ! -d "${repo_agents}" ]]; then
        skip "no real agents dir to canary against"
    fi
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents"
    for src in "${repo_agents}"/*.md; do
        [[ -f "${src}" ]] || continue
        local name
        name="$(basename "${src}" .md)"
        local dest="${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/${name}.md"
        _opencode_translate_one "${src}" "${dest}"

        # Extract color line if present
        local color_line color_value
        color_line="$(grep "^color:" "${dest}" 2>/dev/null || true)"
        if [[ -n "${color_line}" ]]; then
            color_value="$(echo "${color_line}" | sed 's/^color:[[:space:]]*//' | tr -d ' ')"
            # Must match either theme token or hex regex
            case "${color_value}" in
                primary|secondary|accent|success|warning|error|info) ;;
                "#"*)
                    [[ "${color_value}" =~ ^#[0-9a-fA-F]{6}$ ]] || {
                        echo "Invalid hex color in ${name}: ${color_value}"
                        return 1
                    }
                    ;;
                *)
                    echo "Invalid color token in ${name}: ${color_value}"
                    return 1
                    ;;
            esac
        fi
    done
}

@test "translate: produces valid YAML frontmatter (delimited by ---)" {
    _make_agent "yaml-test" '---
name: yaml-test
description: Test
model: inherit
color: blue
---
body'

    _opencode_translate_one \
        "${REPO_DIR}/.claude/agents/yaml-test.md" \
        "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/yaml-test.md"

    local out
    out="$(cat "${OPENCODE_CONFIG_DIR_OVERRIDE}/agents/yaml-test.md")"
    # Starts with ---
    [[ "$(head -1 <<< "$out")" == "---" ]]
    # Has at least 2 --- delimiters
    local count
    count="$(grep -c "^---$" <<< "$out")"
    [ "$count" -ge 2 ]
}

# ==========================================================================
# UNIT TESTS: opencode.json generation
# ==========================================================================

@test "_opencode_generate_json: writes valid JSON with mcp section" {
    INSTALL_MCP_SERVERS=("brave-search" "tavily")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    _opencode_generate_json

    [ -f "${OPENCODE_JSON}" ]

    # Validate JSON
    python3 -m json.tool < "${OPENCODE_JSON}" > /dev/null
}

@test "_opencode_generate_json: uses mcp-env-inject as command" {
    INSTALL_MCP_SERVERS=("brave-search")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    _opencode_generate_json

    local cmd
    cmd="$(jq -r '.mcp."brave-search".command[0]' "${OPENCODE_JSON}")"
    [ "$cmd" = "mcp-env-inject" ]
}

@test "_opencode_generate_json: type is local for stdio servers" {
    INSTALL_MCP_SERVERS=("tavily")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    _opencode_generate_json

    local typ
    typ="$(jq -r '.mcp.tavily.type' "${OPENCODE_JSON}")"
    [ "$typ" = "local" ]
}

@test "_opencode_generate_json: includes \$schema field" {
    INSTALL_MCP_SERVERS=("brave-search")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    _opencode_generate_json

    local schema
    schema="$(jq -r '."$schema"' "${OPENCODE_JSON}")"
    [ "$schema" = "https://opencode.ai/config.json" ]
}

@test "_opencode_generate_json: preserves existing keys when merging" {
    INSTALL_MCP_SERVERS=("brave-search")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    # Pre-seed an existing opencode.json with a custom key
    cat > "${OPENCODE_JSON}" <<'EOF'
{
  "model": "anthropic/claude-sonnet-4-5",
  "autoupdate": false
}
EOF

    _opencode_generate_json

    local model autoupdate
    model="$(jq -r '.model' "${OPENCODE_JSON}")"
    autoupdate="$(jq -r '.autoupdate' "${OPENCODE_JSON}")"
    [ "$model" = "anthropic/claude-sonnet-4-5" ]
    [ "$autoupdate" = "false" ]
}

@test "_opencode_generate_json: idempotent (re-run produces same mcp section)" {
    INSTALL_MCP_SERVERS=("brave-search" "tavily")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    _opencode_generate_json
    local first
    first="$(jq -S '.mcp' "${OPENCODE_JSON}")"

    _opencode_generate_json
    local second
    second="$(jq -S '.mcp' "${OPENCODE_JSON}")"

    [ "$first" = "$second" ]
}

@test "_opencode_build_mcp_entry: doppler backend emits doppler run command" {
    source "$OPENCODE_SH"
    local entry
    entry="$(_opencode_build_mcp_entry "@brave/brave-search-mcp-server" "doppler")"
    local cmd0 cmd1 cmd2 cmd3 cmd4 cmd5 cmd6 cmd7 cmd8
    cmd0="$(echo "${entry}" | jq -r '.command[0]')"
    cmd1="$(echo "${entry}" | jq -r '.command[1]')"
    cmd2="$(echo "${entry}" | jq -r '.command[2]')"
    cmd3="$(echo "${entry}" | jq -r '.command[3]')"
    cmd4="$(echo "${entry}" | jq -r '.command[4]')"
    cmd5="$(echo "${entry}" | jq -r '.command[5]')"
    cmd6="$(echo "${entry}" | jq -r '.command[6]')"
    cmd7="$(echo "${entry}" | jq -r '.command[7]')"
    cmd8="$(echo "${entry}" | jq -r '.command[8]')"
    [ "$cmd0" = "doppler" ]
    [ "$cmd1" = "run" ]
    [ "$cmd2" = "-p" ]
    [ "$cmd3" = "claude-code-config" ]
    [ "$cmd4" = "-c" ]
    [ "$cmd5" = "dev" ]
    [ "$cmd6" = "--" ]
    [ "$cmd7" = "npx" ]
    [ "$cmd8" = "-y" ]
}

@test "_opencode_build_mcp_entry: envfile backend emits mcp-env-inject command" {
    source "$OPENCODE_SH"
    local entry
    entry="$(_opencode_build_mcp_entry "tavily-mcp@0.2.17" "envfile")"
    local cmd0 cmd1
    cmd0="$(echo "${entry}" | jq -r '.command[0]')"
    cmd1="$(echo "${entry}" | jq -r '.command[1]')"
    [ "$cmd0" = "mcp-env-inject" ]
    [ "$cmd1" = "npx" ]
}

@test "_opencode_generate_json: respects active backend (doppler vs envfile)" {
    INSTALL_MCP_SERVERS=("brave-search")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"

    # Force envfile backend by overriding detection
    detect_mcp_backend() { echo "envfile"; }
    export -f detect_mcp_backend

    source "$OPENCODE_SH"
    _opencode_generate_json

    local cmd0
    cmd0="$(jq -r '.mcp."brave-search".command[0]' "${OPENCODE_JSON}")"
    [ "$cmd0" = "mcp-env-inject" ]

    # Now switch to doppler and regenerate
    detect_mcp_backend() { echo "doppler"; }
    export -f detect_mcp_backend
    _opencode_generate_json

    cmd0="$(jq -r '.mcp."brave-search".command[0]' "${OPENCODE_JSON}")"
    [ "$cmd0" = "doppler" ]

    unset -f detect_mcp_backend
}

@test "_opencode_generate_json: writes to existing opencode.jsonc (no split config)" {
    INSTALL_MCP_SERVERS=("brave-search")
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"

    # Pre-seed user's existing .jsonc with custom plugin + share
    cat > "${OPENCODE_CONFIG_DIR_OVERRIDE}/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@slkiser/opencode-quota"],
  "share": "disabled"
}
EOF

    source "$OPENCODE_SH"
    _opencode_generate_json

    # No new opencode.json should appear
    [ ! -f "${OPENCODE_CONFIG_DIR_OVERRIDE}/opencode.json" ]

    # .jsonc must still exist
    [ -f "${OPENCODE_CONFIG_DIR_OVERRIDE}/opencode.jsonc" ]

    # User's plugin and share keys preserved
    local plugin share
    plugin="$(jq -r '.plugin[0]' "${OPENCODE_CONFIG_DIR_OVERRIDE}/opencode.jsonc")"
    share="$(jq -r '.share' "${OPENCODE_CONFIG_DIR_OVERRIDE}/opencode.jsonc")"
    [ "$plugin" = "@slkiser/opencode-quota" ]
    [ "$share" = "disabled" ]

    # MCP block added
    local mcp_cmd
    mcp_cmd="$(jq -r '.mcp."brave-search".command[0]' "${OPENCODE_CONFIG_DIR_OVERRIDE}/opencode.jsonc")"
    [ "$mcp_cmd" = "mcp-env-inject" ]
}

# ==========================================================================
# UNIT TESTS: skills symlink
# ==========================================================================

@test "_opencode_link_skills: creates symlink to repo .claude/skills" {
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    _opencode_link_skills

    [ -L "${OPENCODE_SKILLS_DIR}" ]
    local target
    target="$(readlink "${OPENCODE_SKILLS_DIR}")"
    [ "$target" = "${REPO_DIR}/.claude/skills" ]
}

@test "_opencode_link_skills: idempotent (no error on re-run)" {
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    _opencode_link_skills
    run _opencode_link_skills
    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured"* ]]
}

@test "_opencode_link_skills: replaces stale symlink pointing elsewhere" {
    mkdir -p "${OPENCODE_CONFIG_DIR_OVERRIDE}"
    source "$OPENCODE_SH"

    # Create stale symlink to wrong target
    ln -sfn "/tmp/wrong-target" "${OPENCODE_SKILLS_DIR}"

    _opencode_link_skills

    local target
    target="$(readlink "${OPENCODE_SKILLS_DIR}")"
    [ "$target" = "${REPO_DIR}/.claude/skills" ]
}

# ==========================================================================
# UNIT TESTS: AGENTS.md symlink
# ==========================================================================

@test "_opencode_link_agents_md: symlinks AGENTS.md -> CLAUDE.md when CLAUDE.md exists" {
    echo "# Project context" > "${REPO_DIR}/CLAUDE.md"

    _opencode_link_agents_md

    [ -L "${REPO_DIR}/AGENTS.md" ]
    local target
    target="$(readlink "${REPO_DIR}/AGENTS.md")"
    [ "$target" = "CLAUDE.md" ]
}

@test "_opencode_link_agents_md: skips if AGENTS.md is a regular file" {
    echo "# Project context" > "${REPO_DIR}/CLAUDE.md"
    echo "# Different content" > "${REPO_DIR}/AGENTS.md"  # regular file

    run _opencode_link_agents_md
    [ "$status" -eq 0 ]
    [[ "$output" == *"leaving alone"* ]]
    [ ! -L "${REPO_DIR}/AGENTS.md" ]
}

@test "_opencode_link_agents_md: idempotent re-run" {
    echo "# Project" > "${REPO_DIR}/CLAUDE.md"

    _opencode_link_agents_md
    run _opencode_link_agents_md
    [ "$status" -eq 0 ]
    [[ "$output" == *"already linked"* ]]
}

# ==========================================================================
# INTEGRATION TEST: full configure_opencode flow
# ==========================================================================

@test "configure_opencode: full flow when opencode CLI present" {
    if ! command -v opencode &>/dev/null; then
        skip "opencode CLI not in PATH; integration test requires real binary"
    fi

    # Seed repo with one agent + one skill + CLAUDE.md
    cat > "${REPO_DIR}/.claude/agents/sample.md" <<'EOF'
---
name: sample
description: Sample agent for integration test
model: inherit
color: blue
skills:
  - sample-skill
---
You are a sample agent.
EOF
    mkdir -p "${REPO_DIR}/.claude/skills/sample-skill"
    cat > "${REPO_DIR}/.claude/skills/sample-skill/SKILL.md" <<'EOF'
---
name: sample-skill
description: Sample skill for integration test
---
Skill content.
EOF
    echo "# Sample project context" > "${REPO_DIR}/CLAUDE.md"

    INSTALL_MCP_SERVERS=("brave-search")
    source "$OPENCODE_SH"

    run configure_opencode
    [ "$status" -eq 0 ]

    # Skills symlinked
    [ -L "${OPENCODE_SKILLS_DIR}" ]
    # Agent translated
    [ -f "${OPENCODE_AGENTS_DIR}/sample.md" ]
    grep -q "mode: subagent" "${OPENCODE_AGENTS_DIR}/sample.md"
    ! grep -q "model: inherit" "${OPENCODE_AGENTS_DIR}/sample.md"
    ! grep -q "^name:" "${OPENCODE_AGENTS_DIR}/sample.md"
    # opencode.json valid
    python3 -m json.tool < "${OPENCODE_JSON}" > /dev/null
    # AGENTS.md symlinked
    [ -L "${REPO_DIR}/AGENTS.md" ]
}
