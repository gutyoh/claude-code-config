#!/usr/bin/env bash
# cc-sync-pull.sh
# Path: .claude/hooks/cc-sync-pull.sh
#
# Claude Code SessionStart hook that pulls the latest ~/.claude/* from
# encrypted cloud storage (claude-sync) so a session resumed on this
# machine sees changes pushed from another machine.
#
# SessionStart runs synchronously: whatever this hook spends is added to the
# time before the user gets a prompt. A full `claude-sync pull` is a network
# round trip over the whole tracked file set, so the pull is DETACHED by
# default — the hook returns in milliseconds and the transfer completes in
# the background, ready for the next session. Set CC_SYNC_BLOCKING=1 to wait
# for it instead; that path is bounded by CC_SYNC_TIMEOUT_SEC so a stalled
# transfer can never hang startup indefinitely.
#
# Workflow:
#   1. claude-sync pull -q --force   (skip silently if not installed)
#   2. ~/.claude/cc-sync-remap.sh    (per-machine path-remap; optional)
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
# Env:
#   CC_SYNC_BLOCKING     - 1 to wait for the pull (default: 0, detached)
#   CC_SYNC_TIMEOUT_SEC  - wall-clock bound in blocking mode (default: 10)
#   CC_SYNC_DETACHED     - internal; set on the re-executed background child
#
# Usage:     Configured in .claude/settings.json under hooks.SessionStart
# Platforms: macOS, Linux, Windows (Git Bash)

set +e

LOG="${HOME}/.claude/cc-sync-pull.log"
REMAP_SCRIPT="${HOME}/.claude/cc-sync-remap.sh"
BLOCKING="${CC_SYNC_BLOCKING:-0}"
TIMEOUT_SEC="${CC_SYNC_TIMEOUT_SEC:-10}"

mkdir -p "$(dirname "${LOG}")" 2>/dev/null

# Run "$@" under a wall-clock bound when a timeout binary exists. GNU coreutils
# ships `timeout`, Homebrew's coreutils ships `gtimeout`, stock macOS has
# neither — there the command runs unbounded. Only the blocking path uses this;
# see sync_once for why the detached transfer must not be capped.
run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout --foreground --kill-after=5s "${TIMEOUT_SEC}s" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout --foreground --kill-after=5s "${TIMEOUT_SEC}s" "$@"
    else
        "$@"
    fi
}

sync_once() {
    echo "--- $(date -u +%FT%TZ) cc-sync-pull start (blocking=${BLOCKING}) ---"

    # The bound exists to protect session startup, so it applies only when we are
    # actually holding startup up. A detached transfer blocks nothing, and a full
    # pull over a large tracked set routinely runs longer than any bound short
    # enough to be useful in the foreground — capping it there would kill every
    # pull just before it finished and leave the remote permanently unmerged,
    # which is the failure this hook exists to prevent.
    local rc
    if [[ "${BLOCKING}" == "1" ]]; then
        run_bounded claude-sync pull -q --force
        rc=$?
    else
        claude-sync pull -q --force
        rc=$?
    fi

    echo "claude-sync pull exit=${rc}"
    if [[ "${rc}" -eq 124 ]]; then
        echo "  timed out after ${TIMEOUT_SEC}s — retrying next session"
    fi

    # Per-machine path remap rules (gitignored; lives outside the repo)
    if [[ -x "${REMAP_SCRIPT}" ]]; then
        "${REMAP_SCRIPT}"
    fi
}

# --- Background child: do the work and exit ---
if [[ "${CC_SYNC_DETACHED:-0}" == "1" ]]; then
    sync_once >>"${LOG}" 2>&1
    exit 0
fi

# --- Foreground hook ---
# Consume stdin (SessionStart receives JSON we don't need)
cat >/dev/null

# Skip silently if claude-sync is not installed
if ! command -v claude-sync >/dev/null 2>&1; then
    exit 0
fi

if [[ "${BLOCKING}" == "1" ]]; then
    sync_once >>"${LOG}" 2>&1
    exit 0
fi

# Detach so SessionStart returns immediately. `setsid` escapes the process
# group when available (Linux, util-linux); `nohup` alone suffices elsewhere
# and is what macOS gets.
_self="${BASH_SOURCE[0]}"
if command -v setsid >/dev/null 2>&1; then
    CC_SYNC_DETACHED=1 setsid nohup "${BASH:-bash}" "${_self}" </dev/null >>"${LOG}" 2>&1 &
else
    CC_SYNC_DETACHED=1 nohup "${BASH:-bash}" "${_self}" </dev/null >>"${LOG}" 2>&1 &
fi

exit 0
