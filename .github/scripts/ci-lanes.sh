#!/usr/bin/env bash
# ci-lanes.sh -- which CI lanes a change needs, as GITHUB_OUTPUT lines.
# Path: .github/scripts/ci-lanes.sh
#
# Usage: ci-lanes.sh <event> [<base> <head>]
# A pull request and a push to main take the lanes their change needs: a pull
# request is compared with its base (the merge commit's first parent), a push
# with the commit before it, unless both are given. The pull request already
# ran the same lanes on the same change, so a push re-runs no more than that.
# Manual and scheduled runs take every lane, and catch drift in the runners.

set -euo pipefail

event=$1
base=${2:-HEAD^1}
head=${3:-HEAD}
all_os='["ubuntu-24.04-arm","macos-latest"]'

if [[ ${event} != pull_request && ${event} != push ]]; then
    echo "powershell=true"
    echo "windows-bash=true"
    echo "test-os=${all_os}"
    exit 0
fi

changed=$(git diff --name-only "${base}" "${head}")
printf '%s\n' "${changed}" >&2

# PowerShell lanes: the scripts, their analyzer settings and tests, the
# settings the installer merges, and this workflow.
powershell=false
if grep -qE '\.(ps1|psm1|psd1)$|^lib/setup-ps/|^\.claude/settings\.json$|^\.github/' <<<"${changed}"; then
    powershell=true
fi

# macOS differs from Linux in shell behavior only: sed, stat, date and the
# system bash. Prose, skills and agents test the same on both.
test_os='["ubuntu-24.04-arm"]'
if grep -qE '\.(sh|bash|bats|fish)$|^(bin|lib/setup|tests|\.claude/hooks|\.claude/scripts|\.claude/skills/full-search/scripts)/|^(setup\.sh|justfile|mise\.(toml|lock))$|^\.github/' <<<"${changed}"; then
    test_os=${all_os}
fi

# Windows runs the status line, /full-search and the remote title hook under
# Git Bash: their scripts, their tests and this workflow.
windows_bash=false
if grep -qE '^\.claude/scripts/|^\.claude/skills/full-search/scripts/|^\.claude/hooks/session-remote-title\.sh$|^tests/(statusline|cc-status|full-search|session-remote-title|helpers)|^\.github/' <<<"${changed}"; then
    windows_bash=true
fi

echo "powershell=${powershell}"
echo "windows-bash=${windows_bash}"
echo "test-os=${test_os}"
