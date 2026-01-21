# Subprocess Patterns

## Always Use check=True

```python
import subprocess

# CORRECT: check=True raises on non-zero exit
result = subprocess.run(
    ["git", "status"],
    check=True,
    capture_output=True,
    text=True,
)
print(result.stdout)

# WRONG: Silent failure without check=True
result = subprocess.run(["git", "status"])  # May silently fail
```

---

## Standard Pattern

```python
import subprocess
from pathlib import Path

def run_command(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    timeout: float | None = 30.0,
) -> str:
    """Run a command and return stdout."""
    result = subprocess.run(
        cmd,
        check=True,
        capture_output=True,
        text=True,
        cwd=cwd,
        timeout=timeout,
    )
    return result.stdout
```

---

## Error Handling

```python
from subprocess import CalledProcessError, TimeoutExpired

def safe_run(cmd: list[str]) -> tuple[bool, str]:
    """Run command, return (success, output_or_error)."""
    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
            timeout=60.0,
        )
        return True, result.stdout
    except CalledProcessError as e:
        return False, f"Command failed (exit {e.returncode}): {e.stderr}"
    except TimeoutExpired:
        return False, "Command timed out"
```

---

## Shell Commands (Use Sparingly)

```python
# Only use shell=True when necessary (pipes, globbing)
# IMPORTANT: Never use shell=True with user input

# CORRECT: Safe shell usage for static commands
result = subprocess.run(
    "ls -la | grep '.py'",
    shell=True,
    check=True,
    capture_output=True,
    text=True,
)

# WRONG: User input in shell command (SECURITY RISK)
user_input = get_user_input()
subprocess.run(f"echo {user_input}", shell=True)  # DANGEROUS
```

---

## Streaming Output

```python
import subprocess

def run_with_streaming(cmd: list[str]) -> int:
    """Run command with real-time output."""
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    for line in process.stdout:
        print(line, end="")

    process.wait()
    return process.returncode
```

---

## Environment Variables

```python
import os
import subprocess

# Inherit current environment and add/override
env = os.environ.copy()
env["MY_VAR"] = "value"

result = subprocess.run(
    ["my-command"],
    check=True,
    capture_output=True,
    text=True,
    env=env,
)
```

---

## Quick Reference

| Parameter | Purpose |
|-----------|---------|
| `check=True` | Raise CalledProcessError on non-zero exit |
| `capture_output=True` | Capture stdout and stderr |
| `text=True` | Return strings instead of bytes |
| `cwd=path` | Set working directory |
| `timeout=30` | Kill after N seconds |
| `env=dict` | Override environment variables |
| `shell=True` | Run through shell (avoid if possible) |
