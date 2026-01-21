# CLI Patterns (Typer)

## Basic Command Structure

```python
from typing import Annotated

import typer

app = typer.Typer()


@app.command()
def main(
    input_file: Annotated[str, typer.Argument(help="Input file to process")],
    verbose: Annotated[bool, typer.Option("--verbose", "-v", help="Enable verbose output")] = False,
    config: Annotated[str | None, typer.Option("--config", "-c", help="Config file path")] = None,
) -> None:
    """Process the input file."""
    if verbose:
        typer.echo("Verbose mode enabled")

    process(input_file, config)


if __name__ == "__main__":
    app()
```

---

## Output: Rich or print(), Prefer Rich

```python
from rich.console import Console

console = Console()

# PREFERRED: Use Rich for styled output
console.print("[green]Success![/green]")
console.print("[red]Error: File not found[/red]", style="bold")
console.print("Processing complete")

# ACCEPTABLE: Plain print() for simple output
print("Processing complete")

# ACCEPTABLE: typer.echo() for Click compatibility
typer.echo("Processing complete")
typer.echo("Error: File not found", err=True)  # stderr

# LEGACY: typer.secho() for simple colors (prefer Rich)
typer.secho("Success!", fg=typer.colors.GREEN)
```

---

## Error Handling: typer.Exit, Not sys.exit()

```python
from rich.console import Console

console = Console()


@app.command()
def main() -> None:
    try:
        run_pipeline()
    except ConfigError as e:
        console.print(f"[red]Configuration error:[/red] {e}", err=True)
        raise typer.Exit(1) from e
    except ProcessingError as e:
        console.print(f"[red]Processing failed:[/red] {e}", err=True)
        raise typer.Exit(2) from e


# ALSO ACCEPTABLE: raise SystemExit for exception chaining
@app.command()
def process() -> None:
    try:
        run_pipeline()
    except PipelineError as e:
        typer.echo(f"Error: {e}", err=True)
        raise SystemExit(1) from e


# WRONG: Don't use sys.exit()
import sys
sys.exit(1)  # Don't do this
```

---

## Abort for User Cancellation

```python
@app.command()
def delete_user(username: str) -> None:
    if username == "root":
        typer.echo("The root user is reserved")
        raise typer.Abort()  # Prints "Aborted!" and exits
```

---

## Command Groups (Subcommands)

```python
from typing import Annotated

import typer

app = typer.Typer()


@app.callback()
def main(
    ctx: typer.Context,
    debug: Annotated[bool, typer.Option("--debug/--no-debug", help="Enable debug mode")] = False,
) -> None:
    """Main CLI entry point."""
    ctx.ensure_object(dict)
    ctx.obj["DEBUG"] = debug


@app.command()
def process(ctx: typer.Context) -> None:
    """Process data."""
    if ctx.obj["DEBUG"]:
        typer.echo("Debug mode enabled")


@app.command()
def greet(
    name: Annotated[str, typer.Argument(help="Name to greet")],
) -> None:
    """Greet someone."""
    typer.echo(f"Hello, {name}!")


if __name__ == "__main__":
    app()
```

---

## Nested Subcommands (add_typer)

```python
import typer

app = typer.Typer()
users_app = typer.Typer()
app.add_typer(users_app, name="users")


@users_app.command("list")
def list_users() -> None:
    """List all users."""
    typer.echo("Listing users...")


@users_app.command("create")
def create_user(
    username: Annotated[str, typer.Argument(help="Username to create")],
) -> None:
    """Create a new user."""
    typer.echo(f"Creating user: {username}")


# Usage: myapp users list
# Usage: myapp users create john
```

---

## User Interaction

### Confirmation Prompts

```python
@app.command()
def delete_files() -> None:
    """Delete files with confirmation."""
    typer.echo("About to delete files...")

    if typer.confirm("Do you want to continue?"):
        perform_deletion()
    else:
        raise typer.Abort()
```

### Progress Bars (Rich Integration)

```python
from rich.progress import track


@app.command()
def process_items() -> None:
    """Process items with progress bar."""
    items = get_items()
    for item in track(items, description="Processing..."):
        process(item)
```

### Password Input

```python
@app.command()
def login() -> None:
    """Login with password prompt."""
    password = typer.prompt("Password", hide_input=True, confirmation_prompt=True)
    authenticate(password)
```

---

## Option Types with Annotated Syntax

```python
from datetime import datetime
from pathlib import Path
from typing import Annotated

import typer


@app.command()
def cmd(
    count: Annotated[int, typer.Option("--count", "-n", help="Number of times")] = 1,
    names: Annotated[list[str] | None, typer.Option("--name", help="Names (repeatable)")] = None,
    format: Annotated[str, typer.Option(help="Output format")] = "json",
    output: Annotated[Path | None, typer.Option("--output", "-o", help="Output file")] = None,
) -> None:
    """Command with various option types."""
    ...


# For choices, use Enum (preferred) or Literal
from enum import Enum


class OutputFormat(str, Enum):
    JSON = "json"
    CSV = "csv"
    XML = "xml"


@app.command()
def export(
    format: Annotated[OutputFormat, typer.Option(help="Output format")] = OutputFormat.JSON,
) -> None:
    """Export data in specified format."""
    typer.echo(f"Exporting as {format.value}")
```

---

## Path Validation

```python
from pathlib import Path
from typing import Annotated

import typer


@app.command()
def process_file(
    input_file: Annotated[
        Path,
        typer.Argument(
            exists=True,
            file_okay=True,
            dir_okay=False,
            readable=True,
            help="Input file to process",
        ),
    ],
    output_dir: Annotated[
        Path,
        typer.Option(
            "--output",
            "-o",
            file_okay=False,
            dir_okay=True,
            help="Output directory",
        ),
    ] = Path("output"),
) -> None:
    """Process a file with path validation."""
    output_dir.mkdir(parents=True, exist_ok=True)
    # Process input_file...
```

---

## Callbacks for Validation

```python
from typing import Annotated

import typer


def validate_name(value: str) -> str:
    if not value.isalpha():
        raise typer.BadParameter("Name must contain only letters")
    return value


@app.command()
def greet(
    name: Annotated[str, typer.Option(callback=validate_name, help="Your name")],
) -> None:
    """Greet with validated name."""
    typer.echo(f"Hello, {name}!")
```

---

## Version Option Pattern

```python
from typing import Annotated

import typer

__version__ = "1.0.0"


def version_callback(value: bool) -> None:
    if value:
        typer.echo(f"My App Version: {__version__}")
        raise typer.Exit()


@app.command()
def main(
    version: Annotated[
        bool | None,
        typer.Option("--version", "-V", callback=version_callback, is_eager=True, help="Show version"),
    ] = None,
) -> None:
    """Main application."""
    typer.echo("Running app...")
```

---

## Entry Point in pyproject.toml

```toml
[project.scripts]
myapp = "myapp.cli:app"
```

For apps that need special handling (e.g., Databricks/IPython environments):

```python
def cli_entrypoint() -> None:
    """Entry point wrapper for console scripts."""
    try:
        app()
    except SystemExit as e:
        if e.code != 0:
            raise
        # Exit code 0 = success, return normally
        return


if __name__ == "__main__":
    app()
```

```toml
[project.scripts]
myapp = "myapp.cli:cli_entrypoint"
```

---

## Testing CLI Commands

```python
from typer.testing import CliRunner

from myapp.cli import app

runner = CliRunner()


def test_main_command() -> None:
    result = runner.invoke(app, ["--verbose", "input.txt"])

    assert result.exit_code == 0
    assert "Processing complete" in result.output


def test_error_handling() -> None:
    result = runner.invoke(app, ["nonexistent.txt"])

    assert result.exit_code != 0
    assert "Error" in result.output


def test_subcommand() -> None:
    result = runner.invoke(app, ["users", "create", "john"])

    assert result.exit_code == 0
    assert "Creating user: john" in result.output
```

---

## Rich Integration for Beautiful Output

```python
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

import typer

app = typer.Typer()
console = Console()


@app.command()
def status() -> None:
    """Show status with Rich formatting."""
    table = Table(title="System Status")
    table.add_column("Component", style="cyan")
    table.add_column("Status", style="green")

    table.add_row("Database", "Connected")
    table.add_row("Cache", "Active")

    console.print(table)


@app.command()
def info() -> None:
    """Show info panel."""
    console.print(
        Panel(
            "Application is running normally",
            title="Status",
            border_style="green",
        )
    )
```
