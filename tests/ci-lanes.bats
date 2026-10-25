#!/usr/bin/env bats
# ci-lanes.bats -- the CI plan picks the expensive lanes a change needs.
#
# macOS minutes cost ten times Linux ones and Windows about twice: a push to
# main must run what its change needs, not every lane, and only manual and
# scheduled runs take everything.

# bats file_tags=unit,ci

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LANES="${REPO_ROOT}/.github/scripts/ci-lanes.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    git init -q "${REPO}"
    git -C "${REPO}" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
}

# commit <path>: one commit that adds a file at <path>.
commit() {
    mkdir -p "${REPO}/$(dirname "$1")"
    echo x >"${REPO}/$1"
    git -C "${REPO}" add -A
    git -C "${REPO}" -c user.name=t -c user.email=t@example.invalid commit -q -m "touch $1"
}

lanes() { (cd "${REPO}" && "${LANES}" "$1" 2>/dev/null); }

@test "a push to main that only touches prose runs Linux and no Windows lane" {
    commit docs/notes.md
    run lanes push
    [ "${status}" -eq 0 ]
    [[ ${output} == *"powershell=false"* ]]
    [[ ${output} == *"windows-bash=false"* ]]
    [[ ${output} == *'test-os=["ubuntu-24.04-arm"]'* ]]
}

@test "a push to main that touches shell runs macOS too" {
    commit lib/setup/thing.sh
    run lanes push
    [[ ${output} == *'test-os=["ubuntu-24.04-arm","macos-latest"]'* ]]
}

@test "a push to main that touches PowerShell runs the PowerShell lane" {
    commit lib/setup-ps/thing.ps1
    run lanes push
    [[ ${output} == *"powershell=true"* ]]
}

@test "a pull request is planned from the same paths as a push" {
    commit .claude/scripts/statusline.sh
    run lanes pull_request
    [[ ${output} == *"windows-bash=true"* ]]
}

@test "manual and scheduled runs take every lane" {
    commit docs/notes.md
    for event in workflow_dispatch schedule; do
        run lanes "${event}"
        [[ ${output} == *"powershell=true"* ]]
        [[ ${output} == *"windows-bash=true"* ]]
        [[ ${output} == *'test-os=["ubuntu-24.04-arm","macos-latest"]'* ]]
    done
}
