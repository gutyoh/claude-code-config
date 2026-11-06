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
# A `gh api` call with no body and a GET or HEAD method only reads and passes
# unscanned. The address a command sends to (endpoint, -R) is never scanned.
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

# Whether the `gh api` call in $1 only reads. A field or --input sends a body
# and makes gh POST; an explicit -X/--method wins. graphql always POSTs, so
# there only a query with no mutation reads.
gh_api_reads() {
    local call="${1#*gh api}" method=""
    # -X takes its value attached too (-XPOST), as pflag allows.
    [[ "${call}" =~ (^|[[:space:]])(-X|--method)([[:space:]]+|=)?([A-Za-z]+) ]] \
        && method=$(printf '%s' "${BASH_REMATCH[4]}" | tr '[:lower:]' '[:upper:]')
    if [[ "${call}" =~ (^|[[:space:]])graphql([[:space:]]|$) ]]; then
        [[ "$(printf '%s' "${call}" | tr '[:upper:]' '[:lower:]')" == *mutation* ]] && return 1
        [[ "${call}" =~ (--input|=@) ]] && return 1
        return 0
    fi
    case "${method}" in
        GET | HEAD) return 0 ;;
        "") ;;
        *) return 1 ;;
    esac
    # A short field flag sends a body with its value attached as well (-ftitle=x).
    ! [[ "${call}" =~ (^|[[:space:]])(-[fF]|--field([[:space:]]|=)|--raw-field([[:space:]]|=)|--input([[:space:]]|=)) ]]
}

main() {
    [[ -n "${CLAUDE_LEAK_GUARD:-}" ]] || exit 0
    command -v jq >/dev/null 2>&1 || block "jq is required to read the command"

    local input cmd
    input=$(cat)
    cmd=$(printf '%s' "${input}" | jq -r '.tool_input.command // empty')
    [[ -n "${cmd}" ]] || exit 0

    # Each publishing verb is detected on its own, so a read chained to a
    # write never lets the write through. git's global options may sit
    # between git and its subcommand (git -c k=v commit).
    local start='(^|[^[:alnum:]_-])'
    local git_opts='([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|config-env|exec-path)(=[^[:space:]]+|[[:space:]]+[^[:space:]]+)|-[pP]|--(no-pager|paginate|bare|no-replace-objects|no-optional-locks|no-advice|no-lazy-fetch)))*'
    local gh_verbs='((pr|issue)[[:space:]]+(create|edit|comment|review|close|merge)|(release|repo|label)[[:space:]]+(create|edit)|gist[[:space:]]+(create|edit)|workflow[[:space:]]+run)'
    local gh_text=0 gh_api=0 commit=0 push=0
    [[ "${cmd}" =~ ${start}gh[[:space:]]+${gh_verbs}([[:space:]]|$) ]] && gh_text=1
    [[ "${cmd}" =~ ${start}gh[[:space:]]+api[[:space:]] ]] && gh_api=1
    [[ "${cmd}" =~ ${start}git${git_opts}[[:space:]]+commit([[:space:]]|$) ]] && commit=1
    [[ "${cmd}" =~ ${start}git${git_opts}[[:space:]]+push([[:space:]]|$) ]] && push=1
    # A gh api read publishes nothing, whatever its endpoint names.
    ((gh_api)) && gh_api_reads "${cmd}" && gh_api=0

    local kind=""
    if ((gh_text || gh_api)); then
        kind="gh"
    elif ((commit)); then
        kind="commit"
    elif ((push)); then
        kind="push"
    fi
    [[ -n "${kind}" ]] || exit 0

    local dir repo="" remote="origin"
    dir=$(command_dir "${cmd}")
    [[ "${cmd}" =~ ${start}git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]] \
        && dir=$(literal_path "${BASH_REMATCH[3]}" "${dir}") || true
    # A push sends to the remote it names, not necessarily origin.
    if ((push)) && [[ "${cmd}" =~ ${start}git${git_opts}[[:space:]]+push(([[:space:]]+-[^[:space:]]*)*)[[:space:]]+([^-\;\&\|[:space:]][^\;\&\|[:space:]]*) ]]; then
        remote="${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}"
    fi

    # The address names the repository: -R, else a gh api repos/<owner>/<name>
    # endpoint. Several different ones leave the repository unknown.
    local -a addresses=() distinct=()
    local unread="${cmd}" named
    while [[ "${kind}" == "gh" && "${unread}" =~ ((-R|--repo)[[:space:]=]+|(^|[[:space:]/])repos/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) ]]; do
        named="${BASH_REMATCH[4]}"
        addresses+=("${BASH_REMATCH[0]#"${BASH_REMATCH[3]}"}")
        [[ " ${distinct[*]-} " == *" ${named} "* ]] || distinct+=("${named}")
        unread="${unread#*"${BASH_REMATCH[0]}"}"
    done
    if ((${#addresses[@]} > 0)); then
        ((${#distinct[@]} == 1)) && repo="${distinct[0]}"
    else
        local url known=0
        url=$(git -C "${dir}" remote get-url "${remote}" 2>/dev/null) || known=1
        ((known == 0)) || url="${remote}"
        repo=$(github_repo "${url}")
        # Outside GitHub nothing is public. A word that is neither a remote nor
        # a URL (say, a misread flag value) stays unknown and is checked.
        if [[ -z "${repo}" && "${kind}" != "gh" ]]; then
            ((known == 0)) && exit 0
            [[ "${url}" == *"://"* || "${url}" == *@*:* ]] && exit 0
        fi
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
    # Where the text goes is not the text: endpoints and -R values are left out.
    local_only+=(${addresses[@]+"${addresses[@]}"})

    # Text a flag reads from a file: gh --body-file/-F, git commit -F/--file.
    local rest="${cmd}" arg path
    local file_flags='(--body-file|--file|-F)'
    [[ "${kind}" == "gh" && "${cmd}" =~ gh[[:space:]]+api ]] && file_flags='(--input)'
    # An unquoted path ends at the first operator: `--body-file b.md; echo` reads b.md.
    while [[ "${rest}" =~ (^|[[:space:]])${file_flags}([[:space:]]+|=)(\"[^\"]*\"|\'[^\']*\'|[^[:space:]\;\&\|]+) ]]; do
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
    while [[ "${rest}" =~ (-F|--field)[[:space:]]+[^=[:space:]]+=@([^[:space:]\;\&\|]+) ]]; do
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
    # A push may send any local branch or tag the remote lacks, so every commit
    # message the remote has not seen is checked, and annotated tag messages too.
    if ((push)); then
        local -a lacks=(--not --remotes)
        git -C "${dir}" remote get-url "${remote}" >/dev/null 2>&1 && lacks=(--not "--remotes=${remote}")
        git -C "${dir}" log --format='%B' --branches --tags "${lacks[@]}" -n 200 >"${work}/pushed-messages.txt" 2>/dev/null \
            || block "cannot list the commits this push sends"
        if [[ "${cmd}" =~ (--tags|--follow-tags|refs/tags/) || "$(git -C "${dir}" config --bool push.followTags 2>/dev/null)" == "true" ]]; then
            git -C "${dir}" for-each-ref --count=200 --format='%(contents)' refs/tags >>"${work}/pushed-messages.txt" 2>/dev/null \
                || block "cannot list the tags this push may send"
        fi
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
