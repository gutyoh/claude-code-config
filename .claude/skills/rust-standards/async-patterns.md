# Async Patterns (tokio)

## Async Function Basics

### Prefer `async fn` Over Manual Futures

```rust
// CORRECT: async fn
async fn fetch_data(url: &str) -> Result<Response> {
    let response = reqwest::get(url).await?;
    Ok(response)
}

// WRONG: Manual future construction (unless you need it)
fn fetch_data(url: &str) -> impl Future<Output = Result<Response>> { ... }
```

### Tokio Runtime

```rust
// Application entry point
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let config = load_config().await?;
    run_server(config).await
}

// Tests
#[tokio::test]
async fn test_fetch() {
    let result = fetch_data("https://example.com").await;
    assert!(result.is_ok());
}
```

---

## Concurrent Execution

### `join!` for Known Tasks

```rust
use tokio::join;

async fn fetch_all(urls: &[&str]) -> Result<(Response, Response)> {
    let (a, b) = join!(
        fetch_data(urls[0]),
        fetch_data(urls[1]),
    );
    Ok((a?, b?))
}
```

### `JoinSet` for Dynamic Task Spawning

```rust
use tokio::task::JoinSet;

async fn process_batch(items: Vec<Item>) -> Vec<Result<Output>> {
    let mut set = JoinSet::new();

    for item in items {
        set.spawn(async move { process_item(item).await });
    }

    let mut results = Vec::with_capacity(set.len());
    while let Some(result) = set.join_next().await {
        results.push(result.expect("task panicked"));
    }
    results
}
```

### Semaphore for Concurrency Limiting

```rust
use std::sync::Arc;
use tokio::sync::Semaphore;

struct RateLimitedClient {
    semaphore: Arc<Semaphore>,
    client: reqwest::Client,
}

impl RateLimitedClient {
    fn new(max_concurrent: usize) -> Self {
        Self {
            semaphore: Arc::new(Semaphore::new(max_concurrent)),
            client: reqwest::Client::new(),
        }
    }

    async fn fetch(&self, url: &str) -> Result<Response> {
        let _permit = self.semaphore.acquire().await?;
        self.client.get(url).send().await.map_err(Into::into)
    }
}
```

---

## Timeouts

```rust
use anyhow::Context;
use tokio::time::{timeout, Duration};

async fn fetch_with_timeout(url: &str) -> Result<Response> {
    timeout(Duration::from_secs(30), fetch_data(url))
        .await
        .context("request timed out")?
}
```

---

## Channels

### `mpsc` for Producer-Consumer

```rust
use tokio::sync::mpsc;

async fn pipeline() -> Result<()> {
    let (tx, mut rx) = mpsc::channel(100);

    // Producer
    tokio::spawn(async move {
        for item in generate_items() {
            if tx.send(item).await.is_err() {
                // Receiver dropped; stop producing
                break;
            }
        }
    });

    // Consumer
    while let Some(item) = rx.recv().await {
        process(item).await?;
    }
    Ok(())
}
```

### `oneshot` for Single Response

```rust
use tokio::sync::oneshot;

async fn request_response() -> Result<Output> {
    let (tx, rx) = oneshot::channel();

    tokio::spawn(async move {
        let result = expensive_computation().await;
        let _ = tx.send(result);
    });

    rx.await.context("computation task dropped")
}
```

---

## Graceful Shutdown

```rust
use tokio::signal;
use tokio_util::sync::CancellationToken;

async fn run_server(config: Config) -> Result<()> {
    let cancel = CancellationToken::new();
    let cancel_clone = cancel.clone();

    // Spawn shutdown listener
    tokio::spawn(async move {
        signal::ctrl_c().await.expect("failed to listen for ctrl+c");
        cancel_clone.cancel();
    });

    // Run until cancellation
    tokio::select! {
        result = serve(config) => result,
        () = cancel.cancelled() => {
            tracing::info!("shutting down gracefully");
            Ok(())
        }
    }
}
```

---

## Common Pitfalls

### Don't Hold Locks Across `.await`

```rust
// WRONG: MutexGuard held across await point
let guard = mutex.lock().await;
do_async_work().await;  // guard still held — deadlock risk!
drop(guard);

// CORRECT: Release lock before awaiting
let data = {
    let guard = mutex.lock().await;
    guard.clone()
};
do_async_work().await;
```

### Don't Block the Runtime

```rust
// WRONG: Blocking call in async context
async fn read_file(path: &Path) -> Result<String> {
    std::fs::read_to_string(path).map_err(Into::into)  // Blocks runtime thread!
}

// CORRECT: Use tokio's async fs
async fn read_file(path: &Path) -> Result<String> {
    tokio::fs::read_to_string(path).await.map_err(Into::into)
}

// CORRECT: Spawn blocking for CPU-heavy work
async fn compress(data: Vec<u8>) -> Result<Vec<u8>> {
    tokio::task::spawn_blocking(move || {
        zstd::encode_all(&data[..], 3).map_err(Into::into)
    }).await?
}
```

### Use `Send + 'static` Bounds for Spawned Tasks

```rust
// Tasks spawned with tokio::spawn must be Send + 'static
tokio::spawn(async move {
    // All captured variables must be Send + 'static
    process(owned_data).await
});
```
