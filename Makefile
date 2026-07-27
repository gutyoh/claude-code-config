# Makefile
# Path: claude-code-config/Makefile
#
# Quality targets for a bash-centric Claude Code configuration repo.
# Tools: shellcheck (lint), shfmt (format), bats-core (test)
#
# Install dependencies:
#   brew install shellcheck shfmt bats-core   # macOS
#   sudo apt-get install shellcheck shfmt bats # Ubuntu/Debian

.PHONY: help lint format format-check test test-all unit integration smoke verify-clean-machine check ci clean install-tools

# --- Configuration ---

# All shell scripts in the repo (excluding node_modules, .venv, tmp dirs, etc.)
SHELL_SCRIPTS := $(shell find . -name '*.sh' \
	-not -path './.git/*' \
	-not -path './node_modules/*' \
	-not -path './.venv/*' \
	-not -path './tmp-*/.venv/*' \
	| sort)

# Extensionless executables in bin/ (bash scripts without .sh suffix)
BIN_SCRIPTS := $(shell find ./bin -maxdepth 1 -type f ! -name '*.sh' ! -name '*.ps1' \
	| sort)

# shfmt flags: 4-space indent, case indent, binary ops start of line
SHFMT_FLAGS := -i 4 -ci -bn

# shellcheck: bash dialect, warning severity (style issues via .shellcheckrc)
SHELLCHECK_FLAGS := -s bash -S warning

# bats test files
BATS_FILES := $(wildcard tests/*.bats)

# Parallel test jobs. bats --jobs needs GNU parallel; without it bats errors
# out rather than falling back, so probe and degrade to serial ourselves.
BATS_JOBS ?= 8
BATS_PARALLEL := $(shell command -v parallel >/dev/null 2>&1 && echo "--jobs $(BATS_JOBS)")

# Test lanes (bats >= 1.8 tag filtering).
#   unit        - fast, hermetic, no network, no real binaries
#   integration - drives real scripts end to end, still offline
#   smoke       - runs setup.sh itself against a throwaway HOME
# Untagged tests run in every lane so nothing is silently skipped.
BATS_FLAGS ?=

# --- Targets ---

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Quality targets:"
	@echo "  lint          - Lint all shell scripts with shellcheck"
	@echo "  format        - Format all shell scripts with shfmt (modifies files)"
	@echo "  format-check  - Check formatting without modifying files"
	@echo "  test          - Run the full bats-core suite"
	@echo "  check         - Run lint + format-check + test"
	@echo "  ci            - Full CI pipeline (same as check)"
	@echo ""
	@echo "Test lanes:"
	@echo "  unit          - Fast hermetic tests only"
	@echo "  integration   - End-to-end against real scripts (offline)"
	@echo "  smoke         - Drive setup.sh against a throwaway HOME"
	@echo "  verify-clean-machine - Run the suite as CI would (empty HOME, system bash)"
	@echo ""
	@echo "Utility targets:"
	@echo "  install-tools - Install shellcheck, shfmt, bats-core, GNU parallel"
	@echo "  clean         - Remove temporary files (lock files, timestamps)"
	@echo ""
	@echo "Shell scripts found: $(words $(SHELL_SCRIPTS) $(BIN_SCRIPTS))"
	@echo "Parallel jobs:       $(if $(BATS_PARALLEL),$(BATS_JOBS),1 (GNU parallel not installed))"

lint: ## Lint all shell scripts with shellcheck
	@echo "Running shellcheck on $(words $(SHELL_SCRIPTS) $(BIN_SCRIPTS)) scripts..."
	@shellcheck $(SHELLCHECK_FLAGS) $(SHELL_SCRIPTS) $(BIN_SCRIPTS)
	@echo "shellcheck: all scripts pass"

format: ## Format all shell scripts with shfmt (modifies files)
	@echo "Formatting $(words $(SHELL_SCRIPTS) $(BIN_SCRIPTS)) scripts..."
	@shfmt -w $(SHFMT_FLAGS) $(SHELL_SCRIPTS) $(BIN_SCRIPTS)
	@echo "shfmt: all scripts formatted"

format-check: ## Check formatting without modifying files
	@echo "Checking formatting on $(words $(SHELL_SCRIPTS) $(BIN_SCRIPTS)) scripts..."
	@shfmt -d $(SHFMT_FLAGS) $(SHELL_SCRIPTS) $(BIN_SCRIPTS)
	@echo "shfmt: all scripts correctly formatted"

test: ## Run the full bats-core test suite
	@if [ -z "$(BATS_FILES)" ]; then \
		echo "No .bats test files found in tests/"; \
		exit 1; \
	fi
	@echo "Running $(words $(BATS_FILES)) test file(s)$(if $(BATS_PARALLEL), with $(BATS_JOBS) jobs,  serially — install GNU parallel for --jobs)..."
	@bats $(BATS_PARALLEL) $(BATS_FLAGS) $(BATS_FILES)

test-all: test ## Alias for the full suite

unit: ## Fast hermetic tests only
	@echo "Running unit lane..."
	@bats $(BATS_PARALLEL) --filter-tags unit $(BATS_FILES)

integration: ## End-to-end tests against real scripts (offline)
	@echo "Running integration lane..."
	@bats $(BATS_PARALLEL) --filter-tags integration $(BATS_FILES)

smoke: ## Drive setup.sh itself against a throwaway HOME
	@echo "Running smoke lane..."
	@bats $(BATS_PARALLEL) --filter-tags smoke $(BATS_FILES)

# Reproduce what CI actually runs under, locally.
#
# A developer machine lies in two ways CI does not: ~/.claude is installed (so
# tests that read it pass for the wrong reason) and Homebrew bash is ahead of
# /bin/bash on PATH (so `env bash` finds 5.x while the macOS runner finds
# 3.2.57). Both hid real failures until CI went red. This target removes both
# lies: empty HOME, and bash 3.2 first on PATH when one exists.
verify-clean-machine: ## Run the suite as a clean machine would (empty HOME, system bash)
	@tmp="$$(mktemp -d)"; \
	shim="$$tmp/shim"; mkdir -p "$$shim"; \
	if [ -x /bin/bash ] && [ "$$(/bin/bash -c 'echo $${BASH_VERSINFO[0]}')" -lt 4 ]; then \
		ln -sf /bin/bash "$$shim/bash"; \
		echo "using system bash $$(/bin/bash -c 'echo $$BASH_VERSION')"; \
	else \
		echo "no pre-4.x system bash here; running with the default bash"; \
	fi; \
	env PATH="$$shim:$$PATH" HOME="$$tmp/home" \
		XDG_CONFIG_HOME="$$tmp/home/.config" XDG_CACHE_HOME="$$tmp/home/.cache" \
		$(MAKE) test; \
	rc=$$?; rm -rf "$$tmp"; exit $$rc

check: lint format-check test ## Run lint + format-check + test
	@echo ""
	@echo "All checks passed"

ci: check ## Full CI pipeline (alias for check)

clean: ## Remove temporary files
	rm -rf /tmp/brave-search-rate-limit.lock
	rm -f /tmp/brave-search-last-call
	@echo "Cleaned temporary files"

install-tools: ## Install shellcheck, shfmt, bats-core, and GNU parallel
	@echo "Installing bash quality tools..."
	@if command -v brew >/dev/null 2>&1; then \
		brew install shellcheck shfmt bats-core parallel; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y shellcheck shfmt bats parallel; \
	else \
		echo "ERROR: No supported package manager found (brew or apt-get)"; \
		exit 1; \
	fi
	@echo "All tools installed"
