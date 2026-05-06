#!/usr/bin/env bash
# cc-sync-push.sh
# Path: .claude/hooks/cc-sync-push.sh
#
# Claude Code SessionEnd hook that uploads the local ~/.claude/* to
# encrypted cloud storage (claude-sync) so other machines can sync the
# session changes from this turn.
#
# SessionEnd cannot block termination, so this hook is best-effort: exits
# 0 even on failure and logs to ~/.claude/cc-sync-push.log so missed pushes
# are visible after the fact.
#
# Usage:     Configured in .claude/settings.json under hooks.SessionEnd
# Platforms: macOS, Linux, Windows (Git Bash)

set +e

LOG="${HOME}/.claude/cc-sync-push.log"
mkdir -p "$(dirname "${LOG}")" 2>/dev/null

# Consume stdin (SessionEnd receives JSON we don't need)
cat >/dev/null

if ! command -v claude-sync >/dev/null 2>&1; then
    exit 0
fi

{
    echo "--- $(date -u +%FT%TZ) cc-sync-push start ---"
    claude-sync push -q
    echo "claude-sync push exit=$?"
} >>"${LOG}" 2>&1

exit 0
