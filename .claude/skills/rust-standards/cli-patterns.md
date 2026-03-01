# CLI Patterns (clap)

## Basic Command with Derive

```rust
use std::path::PathBuf;

use clap::Parser;

/// A tool for processing data files.
#[derive(Parser)]
#[command(version, about)]
struct Cli {
    /// Input file to process
    input: PathBuf,

    /// Output file (defaults to stdout)
    #[arg(short, long)]
    output: Option<PathBuf>,

    /// Enable verbose output
    #[arg(short, long)]
    verbose: bool,

    /// Number of worker threads
    #[arg(short, long, default_value_t = 4)]
    workers: usize,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    run(cli)
}
```

---

## Subcommands

```rust
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(version, about)]
struct Cli {
    #[command(subcommand)]
    command: Command,

    /// Enable debug output
    #[arg(long, global = true)]
    debug: bool,
}

#[derive(Subcommand)]
enum Command {
    /// Run a pipeline
    Run {
        /// Pipeline file to execute
        file: PathBuf,

        /// Environment to run in
        #[arg(short, long, default_value = "local")]
        env: String,
    },

    /// Check configuration validity
    Check {
        /// Config file to validate
        #[arg(short, long, default_value = "config.toml")]
        config: PathBuf,
    },

    /// Start interactive REPL
    Repl,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Run { file, env } => run_pipeline(&file, &env),
        Command::Check { config } => check_config(&config),
        Command::Repl => start_repl(),
    }
}
```

---

## Value Enums for Choices

```rust
use clap::ValueEnum;

#[derive(Clone, ValueEnum)]
enum OutputFormat {
    Json,
    Csv,
    Table,
}

#[derive(Parser)]
struct Cli {
    /// Output format
    #[arg(short, long, value_enum, default_value_t = OutputFormat::Table)]
    format: OutputFormat,
}
```

---

## Argument Validation

```rust
use clap::Parser;

#[derive(Parser)]
struct Cli {
    /// Port to listen on (1024-65535)
    #[arg(short, long, value_parser = clap::value_parser!(u16).range(1024..))]
    port: u16,

    /// Input files (at least one required)
    #[arg(required = true, num_args = 1..)]
    files: Vec<PathBuf>,
}
```

---

## Error Handling in CLI

```rust
use anyhow::{Context, Result};

fn main() -> Result<()> {
    let cli = Cli::parse();

    if let Err(err) = run(cli) {
        // Print user-friendly error chain
        eprintln!("error: {err}");
        for cause in err.chain().skip(1) {
            eprintln!("  caused by: {cause}");
        }
        std::process::exit(1);
    }

    Ok(())
}
```

---

## Colored Output with Stdout/Stderr

```rust
use std::io::{self, Write};

/// Write informational output to stdout.
fn print_info(msg: &str) {
    println!("{msg}");
}

/// Write errors to stderr.
fn print_error(msg: &str) {
    eprintln!("error: {msg}");
}

/// Check if output is a terminal (for color support).
fn is_terminal() -> bool {
    std::io::stdout().is_terminal()
}
```

---

## Resource Limits (Inspired by Monty)

```rust
#[derive(Parser)]
struct Cli {
    /// Maximum number of allocations
    #[arg(long)]
    max_allocations: Option<u64>,

    /// Maximum execution time in milliseconds
    #[arg(long)]
    max_duration: Option<u64>,

    /// Maximum memory usage in bytes
    #[arg(long)]
    max_memory: Option<usize>,
}
```

---

## Testing CLI Commands

```rust
use assert_cmd::Command;

#[test]
fn test_help_flag() {
    Command::cargo_bin("myapp")
        .unwrap()
        .arg("--help")
        .assert()
        .success()
        .stdout(predicates::str::contains("Usage:"));
}

#[test]
fn test_invalid_input() {
    Command::cargo_bin("myapp")
        .unwrap()
        .arg("nonexistent.txt")
        .assert()
        .failure()
        .stderr(predicates::str::contains("error"));
}
```

---

## Anti-Patterns

1. **Parsing args manually**: Use `clap` derive macros — they generate help text and validation
2. **`std::process::exit()` deep in code**: Return `Result` and let `main()` handle exit codes
3. **Panicking on bad input**: Use clap's validation or `anyhow` for user-facing errors
4. **Hardcoded paths**: Accept paths as CLI arguments with defaults via `#[arg(default_value)]`
5. **No `--version` flag**: Always include `#[command(version)]`
