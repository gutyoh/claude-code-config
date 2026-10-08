#!/usr/bin/env bats
# managed-entries.bats
# Path: tests/managed-entries.bats
#
# Covers install_managed_entries() in lib/setup/filesystem.sh — the per-entry
# installer that replaced the whole-directory symlink.
#
# The regression it exists to prevent is concrete. ~/.claude is shared: Herdr
# installs hooks/herdr-agent-state.sh, Orca installs skills/orca-cli and
# skills/orchestration. The old create_symlink() pointed the whole directory at
# the repo, so every one of those went dark at once, and its fixed `<name>.bak`
# was `rm -rf`ed by a later run.
#
# Run: bats tests/managed-entries.bats
#      just test

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home

    export REPO_DIR="${BATS_TEST_TMPDIR}/repo"
    export CLAUDE_DIR="${HOME}/.claude"
    mkdir -p "${REPO_DIR}/.claude" "${CLAUDE_DIR}"

    source "$BATS_TEST_DIRNAME/../lib/setup/filesystem.sh"
}

# Populate the repo side with <name>/<entries...>
seed_repo() {
    local name="$1"
    shift
    mkdir -p "${REPO_DIR}/.claude/${name}"
    local e
    for e in "$@"; do
        echo "# repo ${e}" >"${REPO_DIR}/.claude/${name}/${e}"
    done
}

# Turn REPO_DIR into a real git repo and commit whatever is staged, so the
# tracked/untracked distinction the migration relies on actually exists.
make_git_repo() {
    git -C "${REPO_DIR}" init -q
    git -C "${REPO_DIR}" config user.email t@example.com
    git -C "${REPO_DIR}" config user.name Test
    git -C "${REPO_DIR}" add -A
    git -C "${REPO_DIR}" commit -qm init
}

install_hooks() {
    install_managed_entries "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks" "hooks"
}

# bats file_tags=unit

# ============================================================================
# Baseline
# ============================================================================

@test "links each repo entry individually, not the directory" {
    seed_repo hooks a.sh b.sh
    run install_hooks
    [ "$status" -eq 0 ]

    [ ! -L "${CLAUDE_DIR}/hooks" ]
    [ -d "${CLAUDE_DIR}/hooks" ]
    [ -L "${CLAUDE_DIR}/hooks/a.sh" ]
    [ -L "${CLAUDE_DIR}/hooks/b.sh" ]
    [ "$(readlink "${CLAUDE_DIR}/hooks/a.sh")" = "${REPO_DIR}/.claude/hooks/a.sh" ]
}

@test "missing repo directory is skipped, not fatal" {
    run install_managed_entries "${REPO_DIR}/.claude/nope" "${CLAUDE_DIR}/nope" "nope"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping"* ]]
}

# ============================================================================
# Foreign entries — the actual bug
# ============================================================================

@test "a foreign hook file survives installation" {
    seed_repo hooks a.sh
    mkdir -p "${CLAUDE_DIR}/hooks"
    echo "# herdr" >"${CLAUDE_DIR}/hooks/herdr-agent-state.sh"

    run install_hooks
    [ "$status" -eq 0 ]

    [ -f "${CLAUDE_DIR}/hooks/herdr-agent-state.sh" ]
    [ ! -L "${CLAUDE_DIR}/hooks/herdr-agent-state.sh" ]
    grep -q herdr "${CLAUDE_DIR}/hooks/herdr-agent-state.sh"
    [ -L "${CLAUDE_DIR}/hooks/a.sh" ]
}

@test "foreign skill directories survive installation" {
    seed_repo skills repo-skill
    mkdir -p "${CLAUDE_DIR}/skills/orca-cli" "${CLAUDE_DIR}/skills/orchestration"
    echo x >"${CLAUDE_DIR}/skills/orca-cli/SKILL.md"
    echo y >"${CLAUDE_DIR}/skills/orchestration/SKILL.md"

    run install_managed_entries "${REPO_DIR}/.claude/skills" "${CLAUDE_DIR}/skills" "skills"
    [ "$status" -eq 0 ]

    [ -f "${CLAUDE_DIR}/skills/orca-cli/SKILL.md" ]
    [ -f "${CLAUDE_DIR}/skills/orchestration/SKILL.md" ]
    [ -L "${CLAUDE_DIR}/skills/repo-skill" ]
}

@test "a foreign symlink under a name we do not ship is left alone" {
    seed_repo hooks a.sh
    mkdir -p "${CLAUDE_DIR}/hooks" "${BATS_TEST_TMPDIR}/elsewhere"
    echo z >"${BATS_TEST_TMPDIR}/elsewhere/other.sh"
    ln -s "${BATS_TEST_TMPDIR}/elsewhere/other.sh" "${CLAUDE_DIR}/hooks/other.sh"

    run install_hooks
    [ "$status" -eq 0 ]
    [ "$(readlink "${CLAUDE_DIR}/hooks/other.sh")" = "${BATS_TEST_TMPDIR}/elsewhere/other.sh" ]
}

# ============================================================================
# Collisions are backed up, never destroyed
# ============================================================================

@test "a colliding foreign file is backed up with a timestamp, not deleted" {
    seed_repo hooks a.sh
    mkdir -p "${CLAUDE_DIR}/hooks"
    echo "# theirs" >"${CLAUDE_DIR}/hooks/a.sh"

    run install_hooks
    [ "$status" -eq 0 ]

    [ -L "${CLAUDE_DIR}/hooks/a.sh" ]
    local backup
    backup=$(find "${CLAUDE_DIR}/hooks" -name 'a.sh.bak.*' | head -1)
    [ -n "${backup}" ]
    grep -q theirs "${backup}"
}

@test "an existing .bak is never removed by a later run" {
    seed_repo hooks a.sh
    mkdir -p "${CLAUDE_DIR}/hooks"
    echo "# precious" >"${CLAUDE_DIR}/hooks/a.sh.bak.20200101-000000"
    echo "# theirs" >"${CLAUDE_DIR}/hooks/a.sh"

    run install_hooks
    [ "$status" -eq 0 ]

    [ -f "${CLAUDE_DIR}/hooks/a.sh.bak.20200101-000000" ]
    grep -q precious "${CLAUDE_DIR}/hooks/a.sh.bak.20200101-000000"
}

# ============================================================================
# Migration off the legacy whole-directory symlink
# ============================================================================

@test "legacy directory symlink becomes a real dir with per-entry links" {
    seed_repo hooks a.sh b.sh
    make_git_repo
    rmdir "${CLAUDE_DIR}/hooks" 2>/dev/null || true
    ln -s "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks"

    run install_hooks
    [ "$status" -eq 0 ]

    [ ! -L "${CLAUDE_DIR}/hooks" ]
    [ -d "${CLAUDE_DIR}/hooks" ]
    [ -L "${CLAUDE_DIR}/hooks/a.sh" ]
    [ -L "${CLAUDE_DIR}/hooks/b.sh" ]
}

@test "migration lifts an untracked foreign file out of the repo working tree" {
    seed_repo hooks a.sh
    make_git_repo
    # Herdr writes through the legacy link, so its file lands in the checkout.
    echo "# herdr" >"${REPO_DIR}/.claude/hooks/herdr-agent-state.sh"
    rmdir "${CLAUDE_DIR}/hooks" 2>/dev/null || true
    ln -s "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks"

    run install_hooks
    [ "$status" -eq 0 ]

    # Out of the repo — so a branch switch can no longer delete it.
    [ ! -e "${REPO_DIR}/.claude/hooks/herdr-agent-state.sh" ]
    # And still live, as a real file rather than a link into the repo.
    [ -f "${CLAUDE_DIR}/hooks/herdr-agent-state.sh" ]
    [ ! -L "${CLAUDE_DIR}/hooks/herdr-agent-state.sh" ]
    grep -q herdr "${CLAUDE_DIR}/hooks/herdr-agent-state.sh"

    # The repo is clean again.
    [ -z "$(git -C "${REPO_DIR}" status --porcelain)" ]
}

@test "migration leaves tracked repo files in the repo" {
    seed_repo hooks a.sh
    make_git_repo
    rmdir "${CLAUDE_DIR}/hooks" 2>/dev/null || true
    ln -s "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks"

    run install_hooks
    [ "$status" -eq 0 ]
    [ -f "${REPO_DIR}/.claude/hooks/a.sh" ]
    [ -L "${CLAUDE_DIR}/hooks/a.sh" ]
}

@test "a directory symlink pointing somewhere else is preserved, not dismantled" {
    seed_repo hooks a.sh
    mkdir -p "${BATS_TEST_TMPDIR}/other-hooks"
    echo keep >"${BATS_TEST_TMPDIR}/other-hooks/theirs.sh"
    rmdir "${CLAUDE_DIR}/hooks" 2>/dev/null || true
    ln -s "${BATS_TEST_TMPDIR}/other-hooks" "${CLAUDE_DIR}/hooks"

    run install_hooks
    [ "$status" -eq 0 ]

    [ -f "${BATS_TEST_TMPDIR}/other-hooks/theirs.sh" ]
    [ -L "${CLAUDE_DIR}/hooks" ] || [ -d "${CLAUDE_DIR}/hooks" ]
    [ -L "${CLAUDE_DIR}/hooks/a.sh" ]
}

# ============================================================================
# Idempotence and pruning
# ============================================================================

@test "two runs are idempotent" {
    seed_repo hooks a.sh b.sh
    mkdir -p "${CLAUDE_DIR}/hooks"
    echo "# herdr" >"${CLAUDE_DIR}/hooks/herdr-agent-state.sh"

    install_hooks
    local first
    first=$(ls -la "${CLAUDE_DIR}/hooks" | awk '{print $NF}' | sort)

    run install_hooks
    [ "$status" -eq 0 ]
    local second
    second=$(ls -la "${CLAUDE_DIR}/hooks" | awk '{print $NF}' | sort)

    [ "${first}" = "${second}" ]
    [ -f "${CLAUDE_DIR}/hooks/herdr-agent-state.sh" ]
    # No backup churn on a repeat run.
    [ -z "$(find "${CLAUDE_DIR}/hooks" -name '*.bak.*')" ]
}

@test "a managed link is pruned once its repo entry is gone" {
    seed_repo hooks a.sh b.sh
    install_hooks
    [ -L "${CLAUDE_DIR}/hooks/b.sh" ]

    rm "${REPO_DIR}/.claude/hooks/b.sh"
    run install_hooks
    [ "$status" -eq 0 ]

    [ ! -e "${CLAUDE_DIR}/hooks/b.sh" ]
    [ ! -L "${CLAUDE_DIR}/hooks/b.sh" ]
    [ -L "${CLAUDE_DIR}/hooks/a.sh" ]
}

@test "pruning does not touch a foreign dangling symlink" {
    seed_repo hooks a.sh
    mkdir -p "${CLAUDE_DIR}/hooks"
    ln -s "${BATS_TEST_TMPDIR}/gone" "${CLAUDE_DIR}/hooks/theirs.sh"

    run install_hooks
    [ "$status" -eq 0 ]
    [ -L "${CLAUDE_DIR}/hooks/theirs.sh" ]
}

# ============================================================================
# Repo-as-config-dir short circuit
# ============================================================================

@test "no-op when ~/.claude already IS the repo .claude" {
    seed_repo hooks a.sh
    export CLAUDE_DIR="${REPO_DIR}/.claude"

    run install_managed_entries "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}/hooks" "hooks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"same as repo"* ]]
    [ ! -L "${REPO_DIR}/.claude/hooks/a.sh" ]
}

@test "a profile linked to the repo through another profile is converted, not backed up" {
    seed_repo skills a b
    make_git_repo
    # First profile: the legacy whole-directory link straight into the repo.
    mkdir -p "${HOME}/.claude-first"
    ln -s "${REPO_DIR}/.claude/skills" "${HOME}/.claude-first/skills"
    # A foreign file the first profile wrote into the repo through its link.
    echo "# foreign" >"${REPO_DIR}/.claude/skills/foreign"
    # Second profile (the one being installed) links to the first.
    mkdir -p "${CLAUDE_DIR}"
    ln -s "${HOME}/.claude-first/skills" "${CLAUDE_DIR}/skills"

    install_managed_entries "${REPO_DIR}/.claude/skills" "${CLAUDE_DIR}/skills" "skills"

    [ -d "${CLAUDE_DIR}/skills" ] && [ ! -L "${CLAUDE_DIR}/skills" ]
    [ "$(readlink "${CLAUDE_DIR}/skills/a")" = "${REPO_DIR}/.claude/skills/a" ]
    # No backup: the chain ended in the repo, so it was ours.
    ! ls "${CLAUDE_DIR}" | grep -q 'skills.bak'
    # The first profile still sees its foreign file where it left it.
    [ -f "${REPO_DIR}/.claude/skills/foreign" ]
    [ -L "${HOME}/.claude-first/skills" ]
}

@test "migration rescues untracked files when the link names the repo through a symlinked path" {
    seed_repo hooks a.sh
    make_git_repo
    echo "# herdr" >"${REPO_DIR}/.claude/hooks/herdr-agent-state.sh"
    # macOS reaches /tmp through /private/tmp: the link's text and the repo's
    # physical path differ, yet it is a direct link, not a profile chain.
    ln -s "${BATS_TEST_TMPDIR}" "${BATS_TEST_TMPDIR}/alias"
    rmdir "${CLAUDE_DIR}/hooks" 2>/dev/null || true
    ln -s "${BATS_TEST_TMPDIR}/alias/repo/.claude/hooks" "${CLAUDE_DIR}/hooks"

    run install_hooks
    [ "$status" -eq 0 ]
    [[ "$output" == *"rescued hooks/herdr-agent-state.sh"* ]]
    [ -f "${CLAUDE_DIR}/hooks/herdr-agent-state.sh" ]
    [ ! -L "${CLAUDE_DIR}/hooks/herdr-agent-state.sh" ]
    [ -z "$(git -C "${REPO_DIR}" status --porcelain)" ]
}

@test "a relative legacy link into the repo is migrated like an absolute one" {
    seed_repo hooks a.sh
    make_git_repo
    echo "# foreign" >"${REPO_DIR}/.claude/hooks/foreign.sh"
    rmdir "${CLAUDE_DIR}/hooks" 2>/dev/null || true
    local rel
    rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "${REPO_DIR}/.claude/hooks" "${CLAUDE_DIR}")"
    ln -s "${rel}" "${CLAUDE_DIR}/hooks"

    run install_hooks
    [ "$status" -eq 0 ]
    [ -f "${CLAUDE_DIR}/hooks/foreign.sh" ] && [ ! -L "${CLAUDE_DIR}/hooks/foreign.sh" ]
    ! ls "${CLAUDE_DIR}" | grep -q 'hooks.bak'
}
