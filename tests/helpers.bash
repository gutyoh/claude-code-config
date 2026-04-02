# helpers.bash -- Shared test helpers for BATS test files
# Path: tests/helpers.bash
# Source from setup() in each .bats file: source "$BATS_TEST_DIRNAME/helpers.bash"
#
# Provides:
#   _PY  -- resolved python command (python3 or python, PEP 394)

# --- Portable Python (PEP 394) ---
# python3 on Unix/macOS, python on Windows Git Bash
# See: https://peps.python.org/pep-0394/
if command -v python3 &>/dev/null && python3 --version &>/dev/null; then
    _PY="python3"
elif command -v python &>/dev/null && python --version &>/dev/null; then
    _PY="python"
else
    _PY="python3"  # fallback, will error if truly missing
fi
