#!/usr/bin/env bash
# ci-lanes.sh -- which CI lanes a change needs, as GITHUB_OUTPUT lines.
# Path: .github/scripts/ci-lanes.sh
#
# Usage: ci-lanes.sh <event> [<base> <head>]
# Every event but pull_request takes every lane. A pull request is compared
# with its base: the merge commit's first parent, unless both are given.

set -euo pipefail

event=$1
base=${2:-HEAD^1}
head=${3:-HEAD}
all_os='["ubuntu-24.04-arm","macos-latest"]'

if [[ ${event} != pull_request ]]; then
	echo "powershell=true"
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
if grep -qE '\.(sh|bash|bats|fish)$|^(bin|lib/setup|tests|\.claude/hooks|\.claude/scripts)/|^(setup\.sh|justfile|mise\.(toml|lock))$|^\.github/' <<<"${changed}"; then
	test_os=${all_os}
fi

echo "powershell=${powershell}"
echo "test-os=${test_os}"
