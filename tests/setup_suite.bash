# setup_suite.bash -- runs once before any test file, including files that
# never source helpers.bash.
# Path: tests/setup_suite.bash

# The installer and the statusline honor CLAUDE_CONFIG_DIR, and a developer who
# exports it for a second Claude profile would otherwise have the suite install
# into that real profile. Tests that need it set it themselves.
setup_suite() {
    unset CLAUDE_CONFIG_DIR CLAUDE_DIR_REF MCP_KEYS_ENV_FILE
}
