# Logging Patterns

## Microsoft.Extensions.Logging (Built-in)

### Basic Setup

```csharp
var builder = WebApplication.CreateBuilder(args);

// Logging is configured by default in WebApplication.CreateBuilder
// Customize via appsettings.json or code:
builder.Logging.AddFilter("Microsoft.EntityFrameworkCore", LogLevel.Warning);
```

### Structured Logging

```csharp
public class OrderService
{
    private readonly ILogger<OrderService> _logger;

    public OrderService(ILogger<OrderService> logger)
    {
        _logger = logger;
    }

    public async Task<Order> CreateOrderAsync(CreateOrderCommand command, CancellationToken ct)
    {
        _logger.LogInformation("Creating order for customer {CustomerId}", command.CustomerId);

        var order = new Order(command.CustomerId);

        _logger.LogInformation(
            "Order {OrderId} created with {ItemCount} items, total {Total:C}",
            order.Id, order.Items.Count, order.Total);

        return order;
    }
}
```

---

## High-Performance Logging

Use `LoggerMessage.Define` or source generators for zero-allocation logging:

```csharp
// Source generator approach (.NET 6+)
public static partial class LogMessages
{
    [LoggerMessage(Level = LogLevel.Information, Message = "Order {OrderId} created for customer {CustomerId}")]
    public static partial void OrderCreated(this ILogger logger, int orderId, int customerId);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Order {OrderId} processing took {ElapsedMs}ms")]
    public static partial void SlowOrder(this ILogger logger, int orderId, long elapsedMs);

    [LoggerMessage(Level = LogLevel.Error, Message = "Failed to process order {OrderId}")]
    public static partial void OrderFailed(this ILogger logger, int orderId, Exception exception);
}

// Usage
_logger.OrderCreated(order.Id, command.CustomerId);
_logger.SlowOrder(order.Id, elapsed);
_logger.OrderFailed(order.Id, ex);
```

---

## Serilog Integration

```csharp
// Program.cs
using Serilog;

Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateLogger();

builder.Host.UseSerilog();

// appsettings.json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft.AspNetCore": "Warning",
        "Microsoft.EntityFrameworkCore": "Warning"
      }
    },
    "WriteTo": [
      { "Name": "Console" },
      {
        "Name": "File",
        "Args": {
          "path": "logs/app-.log",
          "rollingInterval": "Day"
        }
      }
    ]
  }
}
```

---

## Logging in MediatR Behaviors

```csharp
public class LoggingBehaviour<TRequest> : IRequestPreProcessor<TRequest>
    where TRequest : notnull
{
    private readonly ILogger<TRequest> _logger;
    private readonly IUser _user;

    public LoggingBehaviour(ILogger<TRequest> logger, IUser user)
    {
        _logger = logger;
        _user = user;
    }

    public Task Process(TRequest request, CancellationToken cancellationToken)
    {
        // WARNING: {@Request} destructures the full request object — may contain
        // sensitive data (passwords, tokens, PII). Configure Serilog destructuring
        // policies to mask sensitive properties, or limit to non-sensitive metadata.
        _logger.LogInformation(
            "Request: {Name} {@UserId} {@Request}",
            typeof(TRequest).Name, _user.Id, request);

        return Task.CompletedTask;
    }
}
```

---

## Log Levels

| Level | Use For |
|-------|---------|
| `Trace` | Verbose diagnostic detail (individual iterations, raw data) |
| `Debug` | Diagnostic information during development |
| `Information` | Normal operation milestones (request started, order created) |
| `Warning` | Unexpected but handled situations (retry, degraded performance) |
| `Error` | Failures that need attention (unhandled exception, external service down) |
| `Critical` | Application-level failures (startup failure, data corruption) |

---

## OpenTelemetry Integration

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing =>
    {
        tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddEntityFrameworkCoreInstrumentation()
            .AddOtlpExporter();
    })
    .WithMetrics(metrics =>
    {
        metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddRuntimeInstrumentation()
            .AddOtlpExporter();
    });
```

---

## Anti-Patterns

1. **String interpolation in log messages**: Use structured logging templates — `LogInformation("Order {Id}", id)` not `LogInformation($"Order {id}")`
2. **Logging sensitive data**: Never log passwords, tokens, or PII
3. **Missing exception parameter**: Use `LogError(ex, "message")` — exception goes as first parameter
4. **Excessive logging in hot paths**: Use `LoggerMessage.Define` or source generators for zero-allocation
5. **No log level filtering**: Configure per-namespace levels to reduce noise
6. **Console.WriteLine for logging**: Always use `ILogger<T>`
