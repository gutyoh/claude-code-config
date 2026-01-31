# Makefile
# Path: claude-code-config/Makefile
#
# Quality targets for a bash-centric Claude Code configuration repo.
# Tools: shellcheck (lint), shfmt (format), bats-core (test)
#
# Install dependencies:
#   brew install shellcheck shfmt bats-core   # macOS
#   sudo apt-get install shellcheck shfmt bats # Ubuntu/Debian

.PHONY: help lint format format-check test check ci clean install-tools

# --- Configuration ---

# All shell scripts in the repo (excluding node_modules, .venv, etc.)
SHELL_SCRIPTS := $(shell find . -name '*.sh' \
	-not -path './.git/*' \
	-not -path './node_modules/*' \
	-not -path './.venv/*' \
	| sort)

# shfmt flags: 4-space indent, case indent, binary ops start of line
SHFMT_FLAGS := -i 4 -ci -bn

# shellcheck: bash dialect, warning severity (style issues via .shellcheckrc)
SHELLCHECK_FLAGS := -s bash -S warning

# bats test files
BATS_FILES := $(wildcard tests/*.bats)

# --- Targets ---

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Quality targets:"
	@echo "  lint          - Lint all shell scripts with shellcheck"
	@echo "  format        - Format all shell scripts with shfmt (modifies files)"
	@echo "  format-check  - Check formatting without modifying files"
	@echo "  test          - Run bats-core test suite"
	@echo "  check         - Run lint + format-check + test"
	@echo "  ci            - Full CI pipeline (same as check)"
	@echo ""
	@echo "Utility targets:"
	@echo "  install-tools - Install shellcheck, shfmt, and bats-core"
	@echo "  clean         - Remove temporary files (lock files, timestamps)"
	@echo ""
	@echo "Shell scripts found: $(words $(SHELL_SCRIPTS))"

lint: ## Lint all shell scripts with shellcheck
	@echo "Running shellcheck on $(words $(SHELL_SCRIPTS)) scripts..."
	@shellcheck $(SHELLCHECK_FLAGS) $(SHELL_SCRIPTS)
	@echo "shellcheck: all scripts pass"

format: ## Format all shell scripts with shfmt (modifies files)
	@echo "Formatting $(words $(SHELL_SCRIPTS)) scripts..."
	@shfmt -w $(SHFMT_FLAGS) $(SHELL_SCRIPTS)
	@echo "shfmt: all scripts formatted"

format-check: ## Check formatting without modifying files
	@echo "Checking formatting on $(words $(SHELL_SCRIPTS)) scripts..."
	@shfmt -d $(SHFMT_FLAGS) $(SHELL_SCRIPTS)
	@echo "shfmt: all scripts correctly formatted"

test: ## Run bats-core test suite
	@if [ -z "$(BATS_FILES)" ]; then \
		echo "No .bats test files found in tests/"; \
		exit 1; \
	fi
	@echo "Running $(words $(BATS_FILES)) test file(s)..."
	@bats $(BATS_FILES)

check: lint format-check test ## Run lint + format-check + test
	@echo ""
	@echo "All checks passed"

ci: check ## Full CI pipeline (alias for check)

clean: ## Remove temporary files
	rm -rf /tmp/brave-search-rate-limit.lock
	rm -f /tmp/brave-search-last-call
	@echo "Cleaned temporary files"

install-tools: ## Install shellcheck, shfmt, and bats-core
	@echo "Installing bash quality tools..."
	@if command -v brew >/dev/null 2>&1; then \
		brew install shellcheck shfmt bats-core; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y shellcheck shfmt bats; \
	else \
		echo "ERROR: No supported package manager found (brew or apt-get)"; \
		exit 1; \
	fi
	@echo "All tools installed"
