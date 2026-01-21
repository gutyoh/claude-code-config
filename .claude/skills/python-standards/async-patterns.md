# Async Patterns

## asyncio Fundamentals

### Concurrent Execution with gather

```python
import asyncio

# Run multiple coroutines concurrently
results = await asyncio.gather(*tasks, return_exceptions=True)

# Process results, handling potential exceptions
for result in results:
    if isinstance(result, Exception):
        logger.error(f"Task failed: {result}")
    else:
        process(result)
```

### Semaphore for Resource Limiting

Control concurrency to avoid overwhelming resources.

```python
class DataProcessor:
    def __init__(self, max_concurrent: int = 10) -> None:
        self._semaphore = asyncio.Semaphore(max_concurrent)

    async def process_item(self, item: Item) -> Result:
        async with self._semaphore:
            return await self._do_process(item)

    async def process_batch(self, items: list[Item]) -> list[Result]:
        tasks = [self.process_item(item) for item in items]
        return await asyncio.gather(*tasks, return_exceptions=True)
```

### Timeout Wrapper

```python
try:
    result = await asyncio.wait_for(operation(), timeout=30.0)
except TimeoutError:
    logger.warning("Operation timed out after 30s")
    handle_timeout()
```

---

## ThreadPoolExecutor for Blocking I/O

Wrap blocking operations when inside async code.

```python
from concurrent.futures import ThreadPoolExecutor

class FileService:
    def __init__(self) -> None:
        self._thread_pool = ThreadPoolExecutor(max_workers=4)

    async def read_file(self, path: Path) -> bytes:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(
            self._thread_pool,
            path.read_bytes,
        )

    async def write_file(self, path: Path, data: bytes) -> None:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(
            self._thread_pool,
            path.write_bytes,
            data,
        )
```

**Note**: When using `ThreadPoolExecutor.submit()` with keyword arguments, you must wrap in a lambda:

```python
# WRONG: keyword args don't work directly
executor.submit(func, arg1=value1)  # Fails

# CORRECT: wrap in lambda
executor.submit(lambda: func(arg1=value1))
```

---

## Structured Concurrency Patterns

### Batch Processing with Controlled Concurrency

```python
async def process_in_batches(
    items: list[Item],
    *,
    batch_size: int,
    max_concurrent: int,
) -> list[Result]:
    """Process items in batches with controlled concurrency."""
    semaphore = asyncio.Semaphore(max_concurrent)
    results: list[Result] = []

    async def process_with_limit(item: Item) -> Result:
        async with semaphore:
            return await process_single(item)

    for i in range(0, len(items), batch_size):
        batch = items[i : i + batch_size]
        batch_results = await asyncio.gather(
            *[process_with_limit(item) for item in batch],
            return_exceptions=True,
        )
        results.extend(batch_results)

    return results
```

### Graceful Shutdown

```python
class AsyncService:
    def __init__(self) -> None:
        self._running = False
        self._tasks: set[asyncio.Task] = set()

    async def start(self) -> None:
        self._running = True

    async def stop(self) -> None:
        self._running = False
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
            self._tasks.clear()

    def spawn_task(self, coro: Coroutine) -> asyncio.Task:
        task = asyncio.create_task(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return task
```

---

## Common Pitfalls

### Don't Create Event Loops Manually

```python
# WRONG: Creating event loop manually
loop = asyncio.new_event_loop()
loop.run_until_complete(main())

# CORRECT: Use asyncio.run()
asyncio.run(main())
```

### Don't Block the Event Loop

```python
# WRONG: Blocking call in async function
async def fetch_data():
    response = requests.get(url)  # Blocks!
    return response.json()

# CORRECT: Use async HTTP client
async def fetch_data():
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        return response.json()
```

### Handle Task Cancellation

```python
async def cancellable_operation() -> Result:
    try:
        return await long_running_task()
    except asyncio.CancelledError:
        # Cleanup before re-raising
        await cleanup()
        raise
```
