# common.sh -- Shared portable helpers for cross-platform scripts
# Path: lib/common.sh
# Sourced by scripts and tests that need cross-platform compatibility.
#
# Provides:
#   PYTHON  -- resolved path to python3 or python (PEP 394 fallback)

# --- Portable Python resolver (PEP 394) ---
# Unix/macOS: python3 is standard
# Windows Git Bash: python3 is a broken Microsoft Store alias; python works
# See: https://peps.python.org/pep-0394/
if command -v python3 &>/dev/null && python3 --version &>/dev/null; then
    PYTHON="python3"
elif command -v python &>/dev/null && python --version &>/dev/null; then
    PYTHON="python"
else
    PYTHON=""
fi
