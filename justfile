# justfile
# Path: claude-code-config/justfile
#
# Quality recipes for a bash-centric Claude Code configuration repo.
# Tools: shellcheck (lint), shfmt (format), bats-core (test), zizmor (workflows)
#
#   just install-tools    # get all of them
#   just --list           # everything available

# Every shell script we lint and format: all *.sh plus the extensionless
# executables in bin/. Resolved once per invocation.
shell_scripts := ```
    find . -name '*.sh' \
        -not -path './.git/*' \
        -not -path './node_modules/*' \
        -not -path './.venv/*' \
        -not -path './tmp-*/.venv/*' \
        | sort | tr '\n' ' '
```

bin_scripts := ```
    find ./bin -maxdepth 1 -type f ! -name '*.sh' ! -name '*.ps1' \
        | sort | tr '\n' ' '
```

bats_files := `ls tests/*.bats 2>/dev/null | sort | tr '\n' ' '`

# bats --jobs needs GNU parallel; without it bats errors out rather than
# falling back, so probe and degrade to serial ourselves.
bats_jobs := env('BATS_JOBS', '8')
bats_parallel := if `command -v parallel >/dev/null 2>&1 && echo yes || echo no` == "yes" { "--jobs " + bats_jobs } else { "" }

shfmt_flags := "-i 4 -ci -bn"
shellcheck_flags := "-s bash -S warning"

default:
    @just --list

# Lint every shell script with shellcheck.
lint:
    @echo "Running shellcheck..."
    @shellcheck {{shellcheck_flags}} {{shell_scripts}} {{bin_scripts}}
    @echo "shellcheck: all scripts pass"

# shellcheck covers the shell this repo ships; nothing covered the YAML that
# runs it, which is where the supply-chain surface lives — mutable action refs,
# credential persistence, template injection, missing Dependabot cooldown.

# Audit the GitHub Actions workflows with zizmor.
lint-workflows:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v zizmor >/dev/null 2>&1; then
        echo "zizmor not installed - run 'just install-tools'"
        exit 1
    fi
    echo "Auditing workflows with zizmor..."
    zizmor --persona=regular --collect=all --config .github/zizmor.yml .github/
    echo "zizmor: workflows clean"

# Format every shell script with shfmt (modifies files).
format:
    @echo "Formatting scripts..."
    @shfmt -w {{shfmt_flags}} {{shell_scripts}} {{bin_scripts}}
    @echo "shfmt: all scripts formatted"

# Check formatting without modifying anything.
format-check:
    @echo "Checking formatting..."
    @shfmt -d {{shfmt_flags}} {{shell_scripts}} {{bin_scripts}}
    @echo "shfmt: all scripts correctly formatted"

# Run the full bats-core suite.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    files="{{bats_files}}"
    if [ -z "${files// /}" ]; then
        echo "No .bats test files found in tests/"
        exit 1
    fi
    parallel="{{bats_parallel}}"
    if [ -n "$parallel" ]; then
        echo "Running test files with {{bats_jobs}} jobs..."
    else
        echo "Running test files serially — install GNU parallel for --jobs..."
    fi
    # shellcheck disable=SC2086 # word splitting is intended for both lists
    bats $parallel $files

# Alias for the full suite.
test-all: test

# Fast, hermetic tests only — stubbed boundaries, no network.
unit:
    @echo "Running unit lane..."
    @bats {{bats_parallel}} --filter-tags unit {{bats_files}}

# End-to-end against real scripts, still offline.
integration:
    @echo "Running integration lane..."
    @bats {{bats_parallel}} --filter-tags integration {{bats_files}}

# Drive setup.sh itself against a throwaway HOME.
smoke:
    @echo "Running smoke lane..."
    @bats {{bats_parallel}} --filter-tags smoke {{bats_files}}

# A developer machine lies in two ways CI does not: ~/.claude is installed (so
# tests that read it pass for the wrong reason) and Homebrew bash is ahead of
# /bin/bash on PATH (so `env bash` finds 5.x while the macOS runner finds
# 3.2.57). Both hid real failures until CI went red. This removes both lies.

# Run the suite as a clean machine would (empty HOME, system bash).
verify-clean-machine:
    #!/usr/bin/env bash
    set -uo pipefail
    tmp="$(mktemp -d)"
    shim="$tmp/shim"
    mkdir -p "$shim"
    if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" -lt 4 ]; then
        ln -sf /bin/bash "$shim/bash"
        echo "using system bash $(/bin/bash -c 'echo $BASH_VERSION')"
    else
        echo "no pre-4.x system bash here; running with the default bash"
    fi
    env PATH="$shim:$PATH" HOME="$tmp/home" \
        XDG_CONFIG_HOME="$tmp/home/.config" XDG_CACHE_HOME="$tmp/home/.cache" \
        just test
    rc=$?
    rm -rf "$tmp"
    exit $rc

# Everything the merge gate runs.
check: lint lint-workflows format-check test
    @echo ""
    @echo "All checks passed"

# Full CI pipeline (alias for check).
ci: check

# Remove temporary files (lock files, timestamps).
clean:
    rm -rf /tmp/brave-search-rate-limit.lock
    rm -f /tmp/brave-search-last-call
    @echo "Cleaned temporary files"

# One-time setup: pinned toolchain plus the local git hooks.
setup: install-tools
    @pre-commit install
    @echo "Hooks installed. `just --list` shows what else is available."

# Install the pinned toolchain from mise.toml, plus GNU parallel.
#
# Everything except GNU parallel comes from mise, so versions are identical on
# every machine and in CI. parallel has no mise backend (it is a Perl script,
# not a release binary), so it falls back to the system package manager — and
# it is optional: bats runs serially without it.
install-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v mise >/dev/null 2>&1; then
        echo "mise not found - install it first: https://mise.jdx.dev"
        exit 1
    fi
    echo "Installing the pinned toolchain..."
    mise install
    if ! command -v parallel >/dev/null 2>&1; then
        echo "Installing GNU parallel (optional, enables bats --jobs)..."
        if command -v brew >/dev/null 2>&1; then
            brew install parallel
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y parallel
        else
            echo "  no brew/apt - skipping parallel; tests will run serially"
        fi
    fi
    echo "All tools installed"

# Run every pre-commit hook against the whole tree.
hooks:
    @pre-commit run --all-files
