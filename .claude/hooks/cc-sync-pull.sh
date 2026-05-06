#!/usr/bin/env bash
# cc-sync-pull.sh
# Path: .claude/hooks/cc-sync-pull.sh
#
# Claude Code SessionStart hook that pulls the latest ~/.claude/* from
# encrypted cloud storage (claude-sync) so a session resumed on this
# machine sees changes pushed from another machine.
#
# Workflow:
#   1. claude-sync pull -q --force   (skip silently if not installed)
#   2. exec ~/.claude/cc-sync-remap.sh  (per-machine path-remap; optional)
#
# The remap script is per-machine, lives OUTSIDE this repo (so it is not
# symlinked from .claude/hooks/), and is the right place for user-specific
# path rewrites such as
#   claudepath remap /Users/<user>/path /home/<user>/path --yes
# on a Linux machine that pulled sessions written on macOS.
#
# Fail-safe: every step exits 0 even on error. SessionStart hooks must not
# block session startup. Errors are logged to ~/.claude/cc-sync-pull.log.
#
# Usage:     Configured in .claude/settings.json under hooks.SessionStart
# Platforms: macOS, Linux, Windows (Git Bash)

set +e

LOG="${HOME}/.claude/cc-sync-pull.log"
mkdir -p "$(dirname "${LOG}")" 2>/dev/null

# Consume stdin (SessionStart receives JSON we don't need)
cat >/dev/null

# Skip silently if claude-sync is not installed
if ! command -v claude-sync >/dev/null 2>&1; then
    exit 0
fi

{
    echo "--- $(date -u +%FT%TZ) cc-sync-pull start ---"
    claude-sync pull -q --force
    echo "claude-sync pull exit=$?"
} >>"${LOG}" 2>&1

# Per-machine path remap rules (gitignored; lives outside the repo)
REMAP_SCRIPT="${HOME}/.claude/cc-sync-remap.sh"
if [[ -x "${REMAP_SCRIPT}" ]]; then
    "${REMAP_SCRIPT}" >>"${LOG}" 2>&1
fi

exit 0
