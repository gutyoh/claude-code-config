#!/usr/bin/env bash
# guard-public-text.sh
# Path: .claude/hooks/guard-public-text.sh
#
# Claude Code PreToolUse hook that scans what a Bash command is about to
# publish to a public GitHub repository: pull request, issue, release and
# gist text, `gh api` fields, commit messages, and the messages of commits
# a push sends. GitHub keeps every revision of a description and offers no
# API to delete one, so the check has to run before the text leaves.
#
# The scanner is yours: CLAUDE_LEAK_GUARD holds a command that takes file
# paths and exits non-zero when one holds something private, for example
# `workstation --fleet ~/fleet leak-guard`, whose needles come from a private
# fleet. Unset, the hook does nothing. Set, any failure blocks: a scanner
# that cannot run, or a body file the hook cannot read, never lets text out.
#
# Usage:     Configured in .claude/settings.json as a PreToolUse hook (Bash)
# Platforms: macOS, Linux, Windows (Git Bash)

set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/claude-code/repo-visibility"
CACHE_TTL_S=86400

block() {
    printf 'guard-public-text: %s\n' "$1" >&2
    exit 2
}

# Prints the visibility of $1 (owner/name): PUBLIC, PRIVATE or INTERNAL,
# cached for a day. Prints UNKNOWN when gh cannot tell.
visibility() {
    local repo="$1" file now mtime value
    file="${CACHE_DIR}/${repo//\//__}"
    now=$(date +%s)
    if [[ -f "${file}" ]]; then
        mtime=$(stat -c %Y "${file}" 2>/dev/null || stat -f %m "${file}" 2>/dev/null || echo 0)
        if ((now - mtime < CACHE_TTL_S)); then
            cat "${file}"
            return
        fi
    fi
    value=$(gh repo view "${repo}" --json visibility --jq .visibility 2>/dev/null) || value=""
    case "${value}" in
        PUBLIC | PRIVATE | INTERNAL)
            mkdir -p "${CACHE_DIR}" 2>/dev/null && printf '%s' "${value}" >"${file}" 2>/dev/null
            printf '%s' "${value}"
            ;;
        *) printf 'UNKNOWN' ;;
    esac
}

# owner/name of a GitHub remote URL, or nothing for any other host.
github_repo() {
    local url="$1"
    [[ "${url}" =~ github\.com[:/]([^/]+)/([^/]+)$ ]] || return 0
    printf '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
}

# The directory a command runs in: the last `cd <dir> &&` before the
# publishing verb, else the hook's own working directory.
command_dir() {
    local cmd="$1" dir="${PWD}"
    if [[ "${cmd}" =~ (^|[;&|][[:space:]]*)cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*\&\& ]]; then
        dir="${BASH_REMATCH[2]}"
        dir="${dir%\"}" dir="${dir#\"}" dir="${dir%\'}" dir="${dir#\'}"
        [[ "${dir}" == "~" || "${dir}" == "~/"* ]] && dir="${HOME}${dir#\~}"
    fi
    printf '%s' "${dir}"
}

# A path argument as the shell would see it; fails when it uses expansion.
literal_path() {
    local path="$1" dir="$2"
    path="${path%\"}" path="${path#\"}" path="${path%\'}" path="${path#\'}"
    [[ "${path}" == *'$'* || "${path}" == *'`'* ]] && return 1
    [[ "${path}" == "~" || "${path}" == "~/"* ]] && path="${HOME}${path#\~}"
    [[ "${path}" == /* ]] || path="${dir}/${path}"
    printf '%s' "${path}"
}

main() {
    [[ -n "${CLAUDE_LEAK_GUARD:-}" ]] || exit 0
    command -v jq >/dev/null 2>&1 || block "jq is required to read the command"

    local input cmd
    input=$(cat)
    cmd=$(printf '%s' "${input}" | jq -r '.tool_input.command // empty')
    [[ -n "${cmd}" ]] || exit 0

    local kind=""
    if [[ "${cmd}" =~ (^|[^[:alnum:]_-])gh[[:space:]]+((pr|issue)[[:space:]]+(create|edit|comment|review)|release[[:space:]]+(create|edit)|gist[[:space:]]+create|api[[:space:]]) ]]; then
        kind="gh"
    elif [[ "${cmd}" =~ (^|[^[:alnum:]_-])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?commit([[:space:]]|$) ]]; then
        kind="commit"
    elif [[ "${cmd}" =~ (^|[^[:alnum:]_-])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push([[:space:]]|$) ]]; then
        kind="push"
    fi
    [[ -n "${kind}" ]] || exit 0

    local dir repo=""
    dir=$(command_dir "${cmd}")
    [[ "${cmd}" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]] && dir=$(literal_path "${BASH_REMATCH[1]}" "${dir}") || true
    if [[ "${kind}" == "gh" && "${cmd}" =~ (-R|--repo)[[:space:]=]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) ]]; then
        repo="${BASH_REMATCH[2]}"
    else
        repo=$(github_repo "$(git -C "${dir}" remote get-url origin 2>/dev/null)")
        # Outside GitHub nothing is public.
        [[ -n "${repo}" || "${kind}" == "gh" ]] || exit 0
    fi
    if [[ -n "${repo}" ]]; then
        case "$(visibility "${repo}")" in
            PRIVATE | INTERNAL) exit 0 ;;
        esac
    fi

    local work
    work=$(mktemp -d "${TMPDIR:-/tmp}/guard-public-text.XXXXXX") || block "cannot create a temporary directory"
    trap 'rm -rf "${work}"' EXIT
    local -a files=("${work}/command.txt")
    # Paths only this machine sees are not published; they leave the text.
    local -a local_only=()
    [[ "${cmd}" =~ (^|[;&|][[:space:]]*)cd[[:space:]]+([^;&|[:space:]]+)[[:space:]]*\&\& ]] && local_only+=("${BASH_REMATCH[2]}")
    [[ "${cmd}" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]] && local_only+=("${BASH_REMATCH[1]}")

    # Text a flag reads from a file: gh --body-file/-F, git commit -F/--file.
    local rest="${cmd}" arg path
    local file_flags='(--body-file|--file|-F)'
    [[ "${kind}" == "gh" && "${cmd}" =~ gh[[:space:]]+api ]] && file_flags='(--input)'
    while [[ "${rest}" =~ (^|[[:space:]])${file_flags}([[:space:]]+|=)(\"[^\"]*\"|\'[^\']*\'|[^[:space:]]+) ]]; do
        arg="${BASH_REMATCH[4]}"
        rest="${rest#*"${BASH_REMATCH[0]}"}"
        [[ "${arg}" == "-" ]] && continue
        path=$(literal_path "${arg}" "${dir}") || block "write ${arg} as a literal path so the text it holds can be checked"
        [[ -r "${path}" ]] || block "cannot read ${path} to check it"
        files+=("${path}")
        local_only+=("${arg}")
    done
    # gh api fields read with @file.
    rest="${cmd}"
    while [[ "${rest}" =~ (-F|--field)[[:space:]]+[^=[:space:]]+=@([^[:space:]]+) ]]; do
        arg="${BASH_REMATCH[2]}"
        rest="${rest#*"${BASH_REMATCH[0]}"}"
        path=$(literal_path "${arg}" "${dir}") || block "write @${arg} as a literal path so the text it holds can be checked"
        [[ -r "${path}" ]] || block "cannot read ${path} to check it"
        files+=("${path}")
        local_only+=("${arg}")
    done
    local published="${cmd}" token
    for token in ${local_only[@]+"${local_only[@]}"}; do
        published="${published//"${token}"/}"
    done
    printf '%s\n' "${published}" >"${work}/command.txt"
    # A push sends every commit the remotes lack, with its message.
    if [[ "${kind}" == "push" ]]; then
        git -C "${dir}" log --format='%B' HEAD --not --remotes -n 200 >"${work}/pushed-messages.txt" 2>/dev/null \
            || block "cannot list the commits this push sends"
        files+=("${work}/pushed-messages.txt")
    fi

    local -a scanner
    read -ra scanner <<<"${CLAUDE_LEAK_GUARD}"
    local i
    for i in "${!scanner[@]}"; do
        [[ "${scanner[i]}" == "~/"* ]] && scanner[i]="${HOME}${scanner[i]#\~}"
    done
    local report status
    report=$("${scanner[@]}" "${files[@]}" 2>&1)
    status=$?
    ((status == 0)) && exit 0
    block "this would publish text the leak guard flags in ${repo:-a repository of unknown visibility}:
${report}"
}

main "$@"
