# helpers.bash -- Shared test helpers for BATS test files
# Path: tests/helpers.bash
# Source from setup() in each .bats file: source "$BATS_TEST_DIRNAME/helpers.bash"
#
# Provides:
#   _PY            -- resolved python command (python3 or python, PEP 394)
#   isolate_home   -- redirect HOME/XDG_* into the per-test tmpdir
#   stub_bin       -- put a fake executable on PATH ahead of the real one
#   stub_slow_bin  -- fake executable that sleeps, for timeout tests
#   require_cmd    -- skip the test when a prerequisite is missing

# --- Portable Python (PEP 394) ---
# python3 on Unix/macOS, python on Windows Git Bash
# See: https://peps.python.org/pep-0394/
if command -v python3 &>/dev/null && python3 --version &>/dev/null; then
    _PY="python3"
elif command -v python &>/dev/null && python --version &>/dev/null; then
    _PY="python"
else
    _PY="python3" # fallback, will error if truly missing
fi

# --- Hermetic HOME ---
# Without this a test reads the developer's real ~/.claude, so results depend on
# personal state and anything scanning it (ccusage) pays for gigabytes of real
# session history. Call first in setup().
isolate_home() {
    export HOME="${BATS_TEST_TMPDIR}/home"
    export XDG_CONFIG_HOME="${HOME}/.config"
    export XDG_CACHE_HOME="${HOME}/.cache"
    export XDG_DATA_HOME="${HOME}/.local/share"
    mkdir -p "${HOME}" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}"
}

# --- Stub directory, prepended to PATH once ---
# Assigns to STUB_DIR rather than echoing: a command substitution would run the
# `export PATH` in a subshell, so the caller would never see it and every stub
# would be silently ignored.
_stub_dir() {
    STUB_DIR="${BATS_TEST_TMPDIR}/stubs"
    mkdir -p "${STUB_DIR}"
    case ":${PATH}:" in
        *":${STUB_DIR}:"*) ;;
        *) export PATH="${STUB_DIR}:${PATH}" ;;
    esac
}

# stub_bin <name> [body...]
# Body defaults to a no-op. Reads stdin when a heredoc is piped in.
stub_bin() {
    local name="$1"
    shift
    local dir
    _stub_dir
    dir="${STUB_DIR}"
    {
        printf '#!/usr/bin/env bash\n'
        if [[ $# -gt 0 ]]; then
            printf '%s\n' "$@"
        elif [[ ! -t 0 ]]; then
            cat
        else
            printf 'exit 0\n'
        fi
    } >"${dir}/${name}"
    chmod +x "${dir}/${name}"
}

# stub_slow_bin <name> <seconds> -- hangs, for exercising timeout paths.
# Closes inherited FDs so a SIGKILLed child releases the caller's pipe at once.
stub_slow_bin() {
    local name="$1" seconds="$2"
    stub_bin "${name}" "exec >/dev/null 2>&1 </dev/null" "sleep ${seconds}"
}

# require_cmd <cmd> [reason] -- skip when a prerequisite is absent.
require_cmd() {
    local cmd="$1" reason="${2:-}"
    command -v "${cmd}" >/dev/null 2>&1 || skip "${reason:-${cmd} not installed}"
}

# file_mode <path> -- octal permission bits, portably.
#
# `stat -f '%Lp' file 2>/dev/null || stat -c '%a' file` looks like a BSD-then-GNU
# fallback but is not: on GNU coreutils `-f` means --file-system, so it SUCCEEDS
# and prints filesystem info. The || never fires and the caller silently compares
# against the wrong string. Branch on the platform instead of on exit status.
file_mode() {
    local path="$1"
    case "$(uname -s)" in
        Darwin | *BSD) stat -f '%Lp' "${path}" ;;
        *) stat -c '%a' "${path}" ;;
    esac
}

# repo_hook_path <settings-command> -- resolve a `~/.claude/...` hook command to
# a real file.
#
# Hook commands are written as ~/.claude/hooks/foo.sh because that is where
# Claude Code loads them from, and setup.sh symlinks ~/.claude/hooks to this
# repo. On a machine where setup.sh has never run — every CI runner — that path
# does not exist, so tests asserting the script is present must fall back to the
# repo copy the symlink would point at.
repo_hook_path() {
    local cmd="$1"
    local repo_root="${2:-$(cd "${BATS_TEST_DIRNAME}/.." && pwd)}"
    local expanded="${cmd/#\~/${HOME}}"

    if [[ -e "${expanded}" ]]; then
        printf '%s\n' "${expanded}"
        return
    fi
    case "${cmd}" in
        '~/.claude/'*) printf '%s/.claude/%s\n' "${repo_root}" "${cmd#\~/.claude/}" ;;
        *) printf '%s\n' "${expanded}" ;;
    esac
}

# detect_test_platform -- mirror of statusline.sh's detect_platform().
# Tests that source statusline modules must set PLATFORM to the real platform;
# pinning it to one value forces the wrong stat/date branch on every other OS.
detect_test_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        MSYS* | MINGW* | CYGWIN* | *_NT*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# require_npx <package> -- skip when the npm registry cannot serve <package>.
#
# `npx -y <pkg>` is a network fetch. A dozen of them running under `bats --jobs`
# contend on the registry and fail intermittently — a flaky gate is worse than
# no gate, because people learn to re-run it instead of reading it. Probe once
# per suite, cache the verdict in BATS_SUITE_TMPDIR, and skip cleanly when the
# registry is unreachable so an offline or rate-limited run reports "skipped"
# rather than "failed".
require_npx() {
    local pkg="$1"
    local marker="${BATS_SUITE_TMPDIR:-${BATS_TEST_TMPDIR}}/.npx-probe-${pkg//[^A-Za-z0-9]/_}"

    if [[ -f "${marker}" ]]; then
        [[ "$(cat "${marker}")" == "ok" ]] || skip "npm registry unavailable for ${pkg}"
        return
    fi

    if command -v npx >/dev/null 2>&1 && npx -y "${pkg}" --help >/dev/null 2>&1; then
        echo "ok" >"${marker}"
        return
    fi
    echo "unavailable" >"${marker}"
    skip "npm registry unavailable for ${pkg}"
}

# wait_for_file <path> [timeout_s] -- poll until <path> exists.
#
# For assertions about work a script launched in the background. The producer
# returns before the child has written, so `[ -f "$f" ]` immediately after is a
# race: it wins on an idle machine and loses under `bats --jobs`, which looks
# like flakiness rather than the timing assumption it is.
wait_for_file() {
    local path="$1" timeout="${2:-10}"
    local waited=0
    while [[ "${waited}" -lt $((timeout * 10)) ]]; do
        [[ -f "${path}" ]] && return 0
        sleep 0.1
        waited=$((waited + 1))
    done
    return 1
}
