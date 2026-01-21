# CLI Patterns (Click)

## Basic Command Structure

```python
import click

@click.command()
@click.option("--verbose", "-v", is_flag=True, help="Enable verbose output")
@click.option("--config", "-c", type=click.Path(exists=True), help="Config file path")
@click.argument("input_file", type=click.Path(exists=True))
def main(verbose: bool, config: str | None, input_file: str) -> None:
    """Process the input file."""
    if verbose:
        click.echo("Verbose mode enabled")

    process(input_file, config)
```

---

## Output: click.echo(), Never print()

```python
# CORRECT: Use click.echo()
click.echo("Processing complete")
click.echo("Error: File not found", err=True)  # stderr
click.echo(click.style("Success!", fg="green"))

# WRONG: Never use print() in CLI tools
print("Processing complete")  # Don't do this
```

---

## Error Handling: SystemExit, Not sys.exit()

```python
# CORRECT: Use raise SystemExit
@click.command()
def main() -> None:
    try:
        run_pipeline()
    except ConfigError as e:
        click.echo(f"Configuration error: {e}", err=True)
        raise SystemExit(1) from e
    except ProcessingError as e:
        click.echo(f"Processing failed: {e}", err=True)
        raise SystemExit(2) from e

# WRONG: Don't use sys.exit()
import sys
sys.exit(1)  # Don't do this
```

---

## Command Groups

```python
@click.group()
@click.option("--debug/--no-debug", default=False)
@click.pass_context
def cli(ctx: click.Context, debug: bool) -> None:
    """Main CLI entry point."""
    ctx.ensure_object(dict)
    ctx.obj["DEBUG"] = debug

@cli.command()
@click.pass_context
def process(ctx: click.Context) -> None:
    """Process data."""
    if ctx.obj["DEBUG"]:
        click.echo("Debug mode enabled")

@cli.command()
@click.argument("name")
def greet(name: str) -> None:
    """Greet someone."""
    click.echo(f"Hello, {name}!")

if __name__ == "__main__":
    cli()
```

---

## User Interaction

### Confirmation Prompts

```python
# IMPORTANT: Flush stderr before confirm to prevent buffering issues
import sys

click.echo("About to delete files...", err=True)
sys.stderr.flush()  # Prevent buffering hang

if click.confirm("Do you want to continue?"):
    delete_files()
```

### Progress Bars

```python
items = get_items()
with click.progressbar(items, label="Processing") as bar:
    for item in bar:
        process(item)
```

### Password Input

```python
password = click.prompt("Password", hide_input=True, confirmation_prompt=True)
```

---

## Option Types

```python
@click.command()
@click.option("--count", "-n", type=int, default=1, help="Number of times")
@click.option("--name", "-n", multiple=True, help="Names (can be repeated)")
@click.option("--format", type=click.Choice(["json", "csv", "xml"]), default="json")
@click.option("--output", "-o", type=click.Path(), help="Output file")
@click.option("--date", type=click.DateTime(formats=["%Y-%m-%d"]))
def cmd(count: int, name: tuple[str, ...], format: str, output: str, date: datetime) -> None:
    ...
```

---

## Entry Point in pyproject.toml

```toml
[project.scripts]
myapp = "myapp.cli:main"
```

---

## Testing CLI Commands

```python
from click.testing import CliRunner

def test_main_command():
    runner = CliRunner()
    result = runner.invoke(main, ["--verbose", "input.txt"])

    assert result.exit_code == 0
    assert "Processing complete" in result.output

def test_error_handling():
    runner = CliRunner()
    result = runner.invoke(main, ["nonexistent.txt"])

    assert result.exit_code != 0
    assert "Error" in result.output
```
