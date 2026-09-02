# filesystem.sh -- Managed entry installation and prerequisite checking
# Path: lib/setup/filesystem.sh
# Sourced by setup.sh — do not execute directly.

# ---------------------------------------------------------------------------
# Why per-entry links and not one directory symlink
#
# This used to be `create_symlink`, which pointed ~/.claude/hooks at
# <repo>/.claude/hooks — one link for the whole directory. That is hostile to
# every other tool that installs into ~/.claude. Herdr writes
# hooks/herdr-agent-state.sh; Orca writes skills/orca-cli and
# skills/orchestration. A directory-level link makes all of them disappear at
# once, and the old conflict path moved the real directory to a fixed
# `<name>.bak` that the next run would `rm -rf`.
#
# The subtler damage is that it welds live Claude behaviour to a git working
# tree. Once ~/.claude/hooks IS the repo directory, a foreign installer's file
# lands inside the checkout as an untracked file, and the next `git switch`
# deletes it — which is exactly how the Herdr SessionStart hook broke.
#
# So: one symlink per repo entry, foreign entries left strictly alone, and a
# migration that lifts foreign files back out of the working tree.
# ---------------------------------------------------------------------------

# 0 if $1 is a symlink resolving into directory $2 — i.e. one of ours.
_is_managed_link() {
    local link="$1" dir="$2" dest
    [[ -L "${link}" ]] || return 1
    dest=$(readlink "${link}")
    [[ "${dest}" == "${dir}/"* ]]
}

_repo_is_git() {
    command -v git >/dev/null 2>&1 \
        && git -C "${REPO_DIR}" rev-parse --git-dir >/dev/null 2>&1
}

_repo_tracks() {
    git -C "${REPO_DIR}" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

_timestamped_backup() {
    local path="$1" backup
    backup="${path}.bak.$(date +%Y%m%d-%H%M%S)"
    # Never clobber: if a backup from this same second exists, add a counter.
    local n=1
    while [[ -e "${backup}" ]]; do
        backup="${path}.bak.$(date +%Y%m%d-%H%M%S).${n}"
        n=$((n + 1))
    done
    mv "${path}" "${backup}"
    printf '%s' "$(basename "${backup}")"
}

# Convert a legacy whole-directory symlink into a real directory, rescuing any
# foreign files that were written into the repo through it.
_migrate_directory_symlink() {
    local source_dir="$1" target_dir="$2" name="$3"
    local dest
    dest=$(readlink "${target_dir}")

    if [[ "${dest}" != "${source_dir}" ]]; then
        # Points somewhere that is not this repo. Not ours to take apart.
        local moved
        moved=$(_timestamped_backup "${target_dir}")
        echo "  ⚠ ~/.claude/${name} pointed at ${dest} — link kept as ${moved}"
        mkdir -p "${target_dir}"
        return 0
    fi

    rm -f "${target_dir}"
    mkdir -p "${target_dir}"
    echo "  ⚠ ~/.claude/${name} was a whole-directory symlink — converting to per-entry links"

    # Anything git does not track was written into the working tree by a
    # foreign installer through the link we just removed. Move it back out, or
    # the next branch switch deletes someone else's working hook.
    _repo_is_git || return 0

    local entry base
    shopt -s nullglob
    for entry in "${source_dir}"/*; do
        base=$(basename "${entry}")
        _repo_tracks "${entry}" && continue
        mv "${entry}" "${target_dir}/${base}"
        echo "    ↩ rescued ${name}/${base} out of the repo working tree"
    done
    shopt -u nullglob
}

install_managed_entries() {
    local source_dir="$1"
    local target_dir="$2"
    local name="$3"

    if [[ ! -d "${source_dir}" ]]; then
        echo "  ⊘ ~/.claude/${name} — repo has no .claude/${name}, skipping"
        return 0
    fi

    local claude_real repo_claude_real
    claude_real=$(cd "${CLAUDE_DIR}" && pwd -P)
    repo_claude_real=$(cd "${REPO_DIR}/.claude" && pwd -P)
    if [[ "${claude_real}" == "${repo_claude_real}" ]]; then
        echo "  ✓ ~/.claude/${name} (same as repo, no install needed)"
        return 0
    fi

    if [[ -L "${target_dir}" ]]; then
        _migrate_directory_symlink "${source_dir}" "${target_dir}" "${name}"
    elif [[ -e "${target_dir}" && ! -d "${target_dir}" ]]; then
        local moved
        moved=$(_timestamped_backup "${target_dir}")
        echo "  ⚠ ~/.claude/${name} was a file — kept as ${moved}"
    fi

    mkdir -p "${target_dir}"

    local linked=0 replaced=0 skipped=0
    local entry base target moved

    shopt -s nullglob
    for entry in "${source_dir}"/*; do
        base=$(basename "${entry}")
        [[ "${base}" == ".DS_Store" ]] && continue
        target="${target_dir}/${base}"

        if [[ -L "${target}" ]]; then
            if [[ "$(readlink "${target}")" == "${entry}" ]]; then
                linked=$((linked + 1))
                continue
            fi
            if _is_managed_link "${target}" "${source_dir}"; then
                rm -f "${target}" # stale link of ours — refresh it
            else
                echo "  ⊘ ~/.claude/${name}/${base} — foreign symlink, left as-is"
                skipped=$((skipped + 1))
                continue
            fi
        elif [[ -e "${target}" ]]; then
            moved=$(_timestamped_backup "${target}")
            echo "  ⚠ ~/.claude/${name}/${base} existed — kept as ${moved}"
            replaced=$((replaced + 1))
        fi

        ln -s "${entry}" "${target}"
        linked=$((linked + 1))
    done

    # Drop links of ours whose repo entry has since been deleted or renamed.
    # `-e` follows the link, so a dangling one fails it.
    local pruned=0
    for target in "${target_dir}"/*; do
        _is_managed_link "${target}" "${source_dir}" || continue
        [[ -e "${target}" ]] && continue
        rm -f "${target}"
        pruned=$((pruned + 1))
    done

    # Everything left that is not one of ours belongs to another installer.
    local foreign=0
    for target in "${target_dir}"/*; do
        _is_managed_link "${target}" "${source_dir}" && continue
        foreign=$((foreign + 1))
    done
    shopt -u nullglob

    # Built with `if`, not `((n > 0)) &&` — a false arithmetic test returns
    # non-zero, and as a bare statement under `set -e` that aborts the install.
    local summary="${linked} linked"
    if [[ ${replaced} -gt 0 ]]; then summary="${summary}, ${replaced} replaced"; fi
    if [[ ${pruned} -gt 0 ]]; then summary="${summary}, ${pruned} pruned"; fi
    if [[ ${skipped} -gt 0 ]]; then summary="${summary}, ${skipped} skipped"; fi
    if [[ ${foreign} -gt 0 ]]; then summary="${summary}, ${foreign} left untouched"; fi
    echo "  ✓ ~/.claude/${name}: ${summary}"
}

check_prerequisite() {
    local cmd="$1"
    local label="$2"
    local required="${3:-false}"
    local install_hint="${4:-}"

    if ! command -v "${cmd}" &>/dev/null; then
        echo "  ⚠ ${label} not found${install_hint:+ (${install_hint})}"
        if [[ -n "${install_hint}" ]]; then
            echo "    Install with: brew install ${cmd}  # macOS"
            echo "                  sudo apt-get install ${cmd}  # Ubuntu/Debian"
        fi
        if [[ "${required}" == "true" ]]; then
            echo "    Setup cannot continue without ${cmd}."
            exit 1
        fi
        echo ""
        # Return 0 for an absent OPTIONAL tool. setup.sh runs under `set -e`
        # and every call site is a bare statement, so returning non-zero here
        # aborted the whole install the moment fd/fzf/ccusage were missing —
        # which is the normal state on a machine that has not installed the
        # optional extras. "Optional and absent" is not a failure.
        return 0
    else
        echo "  ✓ ${label} installed"
        return 0
    fi
}
