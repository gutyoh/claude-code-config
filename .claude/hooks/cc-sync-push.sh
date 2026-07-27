#!/usr/bin/env bash
# cc-sync-push.sh
# Path: .claude/hooks/cc-sync-push.sh
#
# Claude Code SessionEnd hook that uploads the local ~/.claude/* to
# encrypted cloud storage (claude-sync) so other machines can sync the
# session changes from this turn.
#
# SessionEnd fires while the process is tearing down, so an inline push is
# killed the moment Claude Code exits — the upload dies mid-flight and the
# remote never advances. A remote frozen behind the local state is what makes
# the next `pull` diverge and write .conflict.<timestamp> copies, which then
# become newly tracked files and compound every session.
#
# So the push is DETACHED: re-exec self through setsid/nohup into a new
# session, which outlives the parent and lets the upload finish. Completion is
# recorded in ~/.claude/cc-sync-push.log — compare `push start` against
# `push exit=` lines there to confirm pushes are landing.
#
# Env:
#   CC_SYNC_BLOCKING  - 1 to wait for the push (default: 0, detached).
#                       Used by tests; in a real SessionEnd it will be killed.
#   CC_SYNC_DETACHED  - internal; set on the re-executed background child
#
# Usage:     Configured in .claude/settings.json under hooks.SessionEnd
# Platforms: macOS, Linux, Windows (Git Bash)

set +e

LOG="${HOME}/.claude/cc-sync-push.log"
BLOCKING="${CC_SYNC_BLOCKING:-0}"

mkdir -p "$(dirname "${LOG}")" 2>/dev/null

push_once() {
    echo "--- $(date -u +%FT%TZ) cc-sync-push start (blocking=${BLOCKING}) ---"
    claude-sync push -q
    echo "claude-sync push exit=$?"
}

# --- Background child: do the work and exit ---
if [[ "${CC_SYNC_DETACHED:-0}" == "1" ]]; then
    push_once >>"${LOG}" 2>&1
    exit 0
fi

# --- Foreground hook ---
# Consume stdin (SessionEnd receives JSON we don't need)
cat >/dev/null

if ! command -v claude-sync >/dev/null 2>&1; then
    exit 0
fi

if [[ "${BLOCKING}" == "1" ]]; then
    push_once >>"${LOG}" 2>&1
    exit 0
fi

_self="${BASH_SOURCE[0]}"
if command -v setsid >/dev/null 2>&1; then
    CC_SYNC_DETACHED=1 setsid nohup "${BASH:-bash}" "${_self}" </dev/null >>"${LOG}" 2>&1 &
else
    CC_SYNC_DETACHED=1 nohup "${BASH:-bash}" "${_self}" </dev/null >>"${LOG}" 2>&1 &
fi

exit 0
