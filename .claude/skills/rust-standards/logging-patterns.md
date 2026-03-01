# Logging Patterns (tracing)

## Basic Setup

```rust
use tracing::{info, warn, error, debug, trace};
use tracing_subscriber::{fmt, EnvFilter};

fn init_logging() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(true)
        .with_file(true)
        .with_line_number(true)
        .init();
}
```

Set log level via environment variable:

```bash
RUST_LOG=info cargo run
RUST_LOG=mylib=debug,tower=warn cargo run
```

---

## Structured Logging with Fields

```rust
use tracing::{info, instrument, warn};

#[instrument(skip(password))]
fn authenticate(username: &str, password: &str) -> Result<User> {
    info!(username, "authentication attempt");

    match verify_credentials(username, password) {
        Ok(user) => {
            info!(username, user_id = user.id, "authentication successful");
            Ok(user)
        }
        Err(e) => {
            warn!(username, error = %e, "authentication failed");
            Err(e)
        }
    }
}
```

---

## Spans for Context Propagation

```rust
use tracing::{info_span, Instrument};

async fn process_request(request: Request) -> Result<Response> {
    let span = info_span!(
        "process_request",
        request_id = %request.id,
        method = %request.method,
        path = %request.path,
    );

    async {
        let data = fetch_data(&request).await?;
        let response = transform(data)?;
        Ok(response)
    }
    .instrument(span)
    .await
}
```

---

## `#[instrument]` Attribute

```rust
use tracing::instrument;

/// Process a batch of items with automatic span creation.
#[instrument(skip(items), fields(batch_size = items.len()))]
async fn process_batch(items: Vec<Item>, config: &Config) -> Result<Vec<Output>> {
    // All logs within this function are automatically scoped to a span
    // with batch_size and config fields
    info!("starting batch processing");

    let results = do_work(items).await?;

    info!(count = results.len(), "batch processing complete");
    Ok(results)
}
```

### `#[instrument]` Options

| Option | Purpose |
|--------|---------|
| `skip(field)` | Don't record a parameter (for large or sensitive data) |
| `skip_all` | Don't record any parameters |
| `fields(key = value)` | Add custom fields to the span |
| `level = "debug"` | Set the span level (default: `INFO`) |
| `name = "custom"` | Override the span name (default: function name) |
| `err` | Record the error if the function returns `Err` |
| `ret` | Record the return value |

---

## Log Levels

```rust
// TRACE: Very verbose diagnostic detail (individual iterations, raw bytes)
trace!(byte_count = data.len(), "received raw data");

// DEBUG: Diagnostic information useful during development
debug!(cache_key = %key, "cache lookup");

// INFO: Normal operation milestones
info!(workers = config.workers, "server started");

// WARN: Unexpected but handled situations
warn!(retries = count, "retrying failed request");

// ERROR: Failures that need attention
error!(error = %e, "failed to connect to database");
```

---

## JSON Output for Production

```rust
fn init_production_logging() {
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(EnvFilter::from_default_env())
        .with_current_span(true)
        .with_span_list(true)
        .init();
}
```

---

## Multiple Subscribers (Layers)

```rust
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

fn init_logging() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::fmt::layer()
                .with_filter(EnvFilter::from_default_env()),
        )
        .with(
            tracing_opentelemetry::layer()
                .with_filter(EnvFilter::new("info")),
        )
        .init();
}
```

---

## Testing with tracing

```rust
#[test]
fn logs_warning_on_invalid_input() {
    let (subscriber, handle) = tracing_mock::subscriber::mock()
        .event(tracing_mock::event::expect().at_level(tracing::Level::WARN))
        .only()
        .run_with_handle();

    tracing::subscriber::with_default(subscriber, || {
        process_invalid_input();
    });

    handle.assert_finished();
}
```

---

## Anti-Patterns

1. **Using `println!` for logging**: Use `tracing` macros — they support structured fields, levels, and filtering
2. **Logging sensitive data**: Use `skip(password)` in `#[instrument]` to exclude sensitive fields
3. **Missing context in errors**: Always add relevant fields (`error = %e, user_id = id`)
4. **`format!` in log messages**: Use structured fields — `info!(count = items.len(), "processed")` not `info!("processed {}", items.len())`
5. **No `RUST_LOG` support**: Always use `EnvFilter` for runtime-configurable log levels
