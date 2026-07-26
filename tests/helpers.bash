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
