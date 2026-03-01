# Async Patterns

## Async All the Way

```csharp
// CORRECT: Async from endpoint to database
public async Task<Order> GetOrderAsync(int id, CancellationToken cancellationToken)
{
    return await _context.Orders
        .AsNoTracking()
        .FirstOrDefaultAsync(o => o.Id == id, cancellationToken)
        ?? throw new NotFoundException(nameof(Order), id);
}

// WRONG: Blocking on async — causes deadlocks
public Order GetOrder(int id)
{
    return _context.Orders.FirstOrDefaultAsync(o => o.Id == id).Result;  // DEADLOCK!
}
```

---

## CancellationToken Everywhere

```csharp
// CORRECT: CancellationToken flows through the entire call chain
public async Task<IResult> GetOrders(
    ISender sender,
    [AsParameters] GetOrdersQuery query,
    CancellationToken cancellationToken)
{
    var result = await sender.Send(query, cancellationToken);
    return TypedResults.Ok(result);
}

public async Task<PaginatedList<OrderDto>> Handle(
    GetOrdersQuery request, CancellationToken cancellationToken)
{
    return await _context.Orders
        .ProjectTo<OrderDto>(_mapper.ConfigurationProvider)
        .PaginatedListAsync(request.PageNumber, request.PageSize, cancellationToken);
}
```

---

## Task.WhenAll for Concurrent Operations

```csharp
public async Task<DashboardDto> GetDashboardAsync(CancellationToken cancellationToken)
{
    var ordersTask = _orderService.GetRecentOrdersAsync(cancellationToken);
    var statsTask = _statsService.GetSummaryAsync(cancellationToken);
    var alertsTask = _alertService.GetActiveAlertsAsync(cancellationToken);

    await Task.WhenAll(ordersTask, statsTask, alertsTask);

    return new DashboardDto(
        Orders: ordersTask.Result,
        Stats: statsTask.Result,
        Alerts: alertsTask.Result);
}
```

---

## Channels for Producer-Consumer

```csharp
public class BackgroundTaskQueue
{
    private readonly Channel<Func<CancellationToken, ValueTask>> _queue;

    public BackgroundTaskQueue(int capacity)
    {
        _queue = Channel.CreateBounded<Func<CancellationToken, ValueTask>>(
            new BoundedChannelOptions(capacity) { FullMode = BoundedChannelFullMode.Wait });
    }

    public async ValueTask EnqueueAsync(
        Func<CancellationToken, ValueTask> workItem, CancellationToken cancellationToken)
    {
        await _queue.Writer.WriteAsync(workItem, cancellationToken);
    }

    public async ValueTask<Func<CancellationToken, ValueTask>> DequeueAsync(
        CancellationToken cancellationToken)
    {
        return await _queue.Reader.ReadAsync(cancellationToken);
    }
}
```

---

## IAsyncEnumerable for Streaming

```csharp
// CORRECT: Stream results without loading all into memory
public async IAsyncEnumerable<OrderDto> GetAllOrdersAsync(
    [EnumeratorCancellation] CancellationToken cancellationToken)
{
    await foreach (var order in _context.Orders.AsAsyncEnumerable()
        .WithCancellation(cancellationToken))
    {
        yield return _mapper.Map<OrderDto>(order);
    }
}
```

---

## SemaphoreSlim for Concurrency Limiting

```csharp
public class RateLimitedService
{
    private readonly SemaphoreSlim _semaphore = new(maxCount: 10);

    public async Task<T> ExecuteAsync<T>(
        Func<CancellationToken, Task<T>> operation,
        CancellationToken cancellationToken)
    {
        await _semaphore.WaitAsync(cancellationToken);
        try
        {
            return await operation(cancellationToken);
        }
        finally
        {
            _semaphore.Release();
        }
    }
}
```

---

## ValueTask for Hot Paths

```csharp
// CORRECT: ValueTask when result is often cached/synchronous
public ValueTask<User?> GetCachedUserAsync(int id, CancellationToken cancellationToken)
{
    if (_cache.TryGetValue(id, out var user))
    {
        return ValueTask.FromResult<User?>(user);
    }
    return GetUserFromDbAsync(id, cancellationToken);
}

private async ValueTask<User?> GetUserFromDbAsync(int id, CancellationToken cancellationToken)
{
    var user = await _context.Users.FindAsync([id], cancellationToken);
    if (user is not null) _cache[id] = user;
    return user;
}
```

---

## Common Pitfalls

### Never Use `async void`

```csharp
// WRONG: async void — exceptions are unobservable
async void ProcessOrder(Order order) { ... }

// CORRECT: async Task
async Task ProcessOrderAsync(Order order, CancellationToken cancellationToken) { ... }

// EXCEPTION: Event handlers (only place async void is acceptable)
async void OnButtonClick(object sender, EventArgs e) { ... }
```

### Don't Capture Context Unnecessarily

```csharp
// CORRECT: ConfigureAwait(false) in library code
public async Task<string> FetchDataAsync(CancellationToken cancellationToken)
{
    var response = await _httpClient.GetAsync(url, cancellationToken).ConfigureAwait(false);
    return await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
}

// NOTE: In ASP.NET Core, ConfigureAwait(false) is not needed (no SynchronizationContext)
// but is good practice in libraries that may be used outside ASP.NET Core
```

---

## Anti-Patterns

1. **`.Result` or `.Wait()`**: Causes deadlocks — async all the way
2. **`async void`**: Exceptions are unobservable — return `Task` or `ValueTask`
3. **Missing `CancellationToken`**: Every async method should accept and forward it
4. **`Task.Run` in ASP.NET Core**: Don't wrap async calls in `Task.Run` — already async
5. **Fire and forget**: Use `IHostedService` or background queues instead
6. **Returning `new Task`**: Use `Task.FromResult` or `ValueTask.FromResult` for synchronous results
