# filesystem.sh -- Symlink creation and prerequisite checking
# Path: lib/setup/filesystem.sh
# Sourced by setup.sh — do not execute directly.

create_symlink() {
    local source="$1"
    local target="$2"
    local name="$3"

    local claude_real
    claude_real=$(cd "${CLAUDE_DIR}" && pwd -P)
    local repo_claude_real
    repo_claude_real=$(cd "${REPO_DIR}/.claude" && pwd -P)

    if [[ "${claude_real}" == "${repo_claude_real}" ]]; then
        echo "  ✓ ~/.claude/${name} (same as repo, no symlink needed)"
        return 0
    fi

    if [[ -L "${target}" ]]; then
        local current_target
        current_target=$(readlink "${target}")
        if [[ "${current_target}" == "${source}" ]]; then
            echo "  ✓ ~/.claude/${name} -> ${source} (already configured)"
            return 0
        fi
        # Existing symlink points elsewhere — safe to replace
        rm -f "${target}"
    elif [[ -d "${target}" ]]; then
        # Real directory exists — back it up before replacing with symlink
        local backup="${target}.bak"
        if [[ -e "${backup}" ]]; then
            rm -rf "${backup}"
        fi
        mv "${target}" "${backup}"
        echo "  ⚠ ~/.claude/${name} was a directory — backed up to ${name}.bak"
    elif [[ -e "${target}" ]]; then
        # Regular file — remove it
        rm -f "${target}"
    fi

    ln -s "${source}" "${target}"
    echo "  ✓ ~/.claude/${name} -> ${source}"
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
        return 1
    else
        echo "  ✓ ${label} installed"
        return 0
    fi
}
