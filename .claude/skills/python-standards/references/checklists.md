# Quality Checklists

Run through these checklists before completing code.

---

## Pre-Commit Checklist

### Type Safety
- [ ] All public functions have return type annotations
- [ ] All public function parameters have type hints
- [ ] No `Any` types without justification
- [ ] Enums used for fixed value sets (prefer over Literal)

### Exception Handling
- [ ] No bare `except` clauses
- [ ] No silent exception swallowing (`except: pass`)
- [ ] All raised exceptions use `from e` or `from None`
- [ ] Custom exceptions defined for domain errors

### Code Style
- [ ] Maximum 4 indentation levels
- [ ] Functions with 4+ params use keyword-only after `*`
- [ ] No mutable default arguments
- [ ] No star imports (`from x import *`)

### Path & I/O Operations
- [ ] Using `pathlib.Path`, not `os.path`
- [ ] `.exists()` checked before `.resolve()` or `.is_relative_to()`
- [ ] Encoding specified for all file operations (`encoding="utf-8"`)

### Performance
- [ ] `__len__`, `__bool__`, `__contains__` are O(1)
- [ ] Properties don't do I/O or expensive computation
- [ ] No import-time side effects (use `@cache` for deferred computation)

### Logging
- [ ] Using Loguru with `logger.bind()` for context
- [ ] Appropriate log levels (debug/info/warning/error)
- [ ] No intermediate variables for log messages

---

## LBYL Decision Checklist

**Use LBYL (check first) when:**
- [ ] Dictionary key access → `if key in mapping:`
- [ ] Path existence → `if path.exists():`
- [ ] Attribute presence → `if hasattr(obj, 'attr'):`
- [ ] Collection bounds → `if index < len(items):`

**Use EAFP (try/except) when:**
- [ ] Third-party API with no check alternative
- [ ] Race condition (file I/O where check-then-act is unsafe)
- [ ] Error boundary (CLI/API entry point)
- [ ] Adding context before re-raising

---

## Async Code Checklist

- [ ] Using `asyncio.run()`, not manual event loop
- [ ] Blocking I/O wrapped with `run_in_executor()`
- [ ] Semaphores used for resource limiting
- [ ] Tasks handle `CancelledError` properly
- [ ] No blocking calls in async functions

---

## Pydantic Model Checklist

- [ ] `ConfigDict` set appropriately (extra="forbid", etc.)
- [ ] Field validators use `@classmethod` decorator
- [ ] Computed fields use `@computed_field` + `@property`
- [ ] Model validators use `mode="after"` when validating relationships

---

## CLI Checklist

- [ ] Using `click.echo()`, never `print()`
- [ ] Errors exit via `raise SystemExit(1)`, not `sys.exit()`
- [ ] `sys.stderr.flush()` before `click.confirm()`
- [ ] Entry point defined in `pyproject.toml`

---

## Subprocess Checklist

- [ ] Always using `check=True`
- [ ] Using `capture_output=True, text=True`
- [ ] Timeout specified
- [ ] No `shell=True` with user input

---

## Interface Design Checklist

When creating abstractions:
- [ ] Only one implementation exists? → Don't abstract yet
- [ ] Control all implementations? → Use ABC
- [ ] Third-party objects? → Use Protocol
- [ ] Need `isinstance()` checks? → Use ABC

---

## Code Review Questions

Ask yourself before submitting:

1. **Would a new team member understand this code?**
2. **If this fails at 3 AM, can I debug it from the logs?**
3. **What happens when this input is None/empty/huge?**
4. **Is this the simplest solution that works?**
5. **Did I add complexity that isn't needed yet?**