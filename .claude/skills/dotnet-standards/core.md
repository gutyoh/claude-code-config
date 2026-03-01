# Core Principles

## 1. Reduce Ceremony

Use modern C# features to minimize boilerplate. The code that isn't there can't have bugs.

```csharp
// CORRECT: File-scoped namespace, record, primary constructor
namespace MyApp.Domain.Entities;

public class Order
{
    public int Id { get; private set; }
    public string CustomerName { get; private set; } = null!;
    public decimal Total { get; private set; }
    public DateTime CreatedAt { get; private set; } = DateTime.UtcNow;

    private readonly List<OrderItem> _items = [];
    public IReadOnlyList<OrderItem> Items => _items;

    public void AddItem(OrderItem item)
    {
        _items.Add(item);
        Total += item.Price * item.Quantity;
    }
}
```

## 2. Code Style

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Types (class, struct, record, enum) | PascalCase | `OrderService`, `PaymentStatus` |
| Interfaces | `I` + PascalCase | `IOrderRepository`, `IPaymentGateway` |
| Methods, properties | PascalCase | `GetOrderAsync`, `TotalAmount` |
| Parameters, local variables | camelCase | `orderId`, `customerName` |
| Private fields | `_camelCase` | `_repository`, `_logger` |
| Private static fields | `s_camelCase` | `s_instance` |
| Constants (public) | PascalCase | `MaxRetryCount` |
| Constants (private/local) | camelCase | `defaultTimeout` |
| Type parameters | `T` + PascalCase | `TRequest`, `TResponse` |
| Async methods | Suffix with `Async` | `GetOrderAsync`, `SaveChangesAsync` |

### File Organization

One class per file. File name matches type name.

```
src/
├── Domain/
│   ├── Common/
│   │   └── BaseEntity.cs
│   ├── Entities/
│   │   └── Order.cs
│   ├── Events/
│   │   └── OrderCreatedEvent.cs
│   └── Enums/
│       └── OrderStatus.cs
├── Application/
│   ├── Common/
│   │   ├── Behaviours/
│   │   │   ├── ValidationBehaviour.cs
│   │   │   └── LoggingBehaviour.cs
│   │   ├── Exceptions/
│   │   │   └── ValidationException.cs
│   │   ├── Interfaces/
│   │   │   └── IApplicationDbContext.cs
│   │   └── Models/
│   │       └── Result.cs
│   ├── Orders/
│   │   ├── Commands/
│   │   │   └── CreateOrder/
│   │   │       ├── CreateOrder.cs         # Command record + handler
│   │   │       └── CreateOrderValidator.cs
│   │   └── Queries/
│   │       └── GetOrders/
│   │           ├── GetOrders.cs           # Query record + handler
│   │           └── OrderDto.cs
│   ├── DependencyInjection.cs
│   └── GlobalUsings.cs
├── Infrastructure/
│   ├── Data/
│   │   ├── ApplicationDbContext.cs
│   │   ├── Configurations/
│   │   │   └── OrderConfiguration.cs
│   │   └── Migrations/
│   ├── DependencyInjection.cs
│   └── Services/
└── Web/
    ├── Endpoints/
    │   └── Orders.cs
    ├── Infrastructure/
    │   ├── EndpointGroupBase.cs
    │   └── CustomExceptionHandler.cs
    ├── DependencyInjection.cs
    └── Program.cs
```

### Global Usings

Declare frequently-used namespaces in `GlobalUsings.cs` per project:

```csharp
// src/Application/GlobalUsings.cs
global using AutoMapper;
global using AutoMapper.QueryableExtensions;
global using FluentValidation;
global using MediatR;
global using Microsoft.EntityFrameworkCore;
```

### Import Organization

System namespaces first, then third-party, then project:

```csharp
using System.Reflection;
using Microsoft.EntityFrameworkCore;
using FluentValidation;
using MyApp.Application.Common.Interfaces;
using MyApp.Domain.Entities;
```

---

## 3. Error Handling

### Domain Exceptions

```csharp
namespace MyApp.Application.Common.Exceptions;

public class NotFoundException : Exception
{
    public NotFoundException() : base() { }

    public NotFoundException(string message) : base(message) { }

    public NotFoundException(string message, Exception innerException)
        : base(message, innerException) { }

    public NotFoundException(string name, object key)
        : base($"Entity \"{name}\" ({key}) was not found.") { }
}

public class ForbiddenAccessException : Exception
{
    public ForbiddenAccessException() : base() { }
}
```

### Validation Exception with FluentValidation

```csharp
public class ValidationException : Exception
{
    public IDictionary<string, string[]> Errors { get; }

    public ValidationException() : base("One or more validation failures have occurred.")
    {
        Errors = new Dictionary<string, string[]>();
    }

    public ValidationException(IEnumerable<ValidationFailure> failures) : this()
    {
        Errors = failures
            .GroupBy(e => e.PropertyName, e => e.ErrorMessage)
            .ToDictionary(g => g.Key, g => g.ToArray());
    }
}
```

### ProblemDetails for API Errors

Map exceptions to RFC 9457 ProblemDetails via `IExceptionHandler`:

```csharp
public class CustomExceptionHandler : IExceptionHandler
{
    private readonly Dictionary<Type, Func<HttpContext, Exception, Task>> _handlers;

    public CustomExceptionHandler()
    {
        _handlers = new()
        {
            { typeof(ValidationException), HandleValidationException },
            { typeof(NotFoundException), HandleNotFoundException },
            { typeof(UnauthorizedAccessException), HandleUnauthorized },
            { typeof(ForbiddenAccessException), HandleForbidden },
        };
    }

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        if (_handlers.TryGetValue(exception.GetType(), out var handler))
        {
            await handler(httpContext, exception);
            return true;
        }
        return false;
    }

    private static async Task HandleValidationException(HttpContext context, Exception ex)
    {
        var exception = (ValidationException)ex;
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsJsonAsync(new ValidationProblemDetails(exception.Errors)
        {
            Status = StatusCodes.Status400BadRequest,
            Type = "https://tools.ietf.org/html/rfc9110#section-15.5.1"
        });
    }

    private static async Task HandleNotFoundException(HttpContext context, Exception ex)
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        await context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Status = StatusCodes.Status404NotFound,
            Title = "The specified resource was not found.",
            Detail = ex.Message
        });
    }
}
```

### Error Handling Rules

| Rule | Detail |
|------|--------|
| Never swallow exceptions | Always log or rethrow |
| Use `ProblemDetails` for APIs | RFC 9457 standard error format |
| Domain exceptions for business rules | `NotFoundException`, `ForbiddenAccessException` |
| `ValidationException` for input errors | Map `FluentValidation.ValidationFailure` to error dict |
| `IExceptionHandler` for global handling | Register in DI, maps exception types to HTTP responses |
| Never catch `Exception` broadly | Catch specific types or use exception handler middleware |

---

## 4. Dependency Injection

### Extension Method Pattern

Each layer registers its own services via an extension method:

```csharp
// Application layer
namespace Microsoft.Extensions.DependencyInjection;

public static class DependencyInjection
{
    public static void AddApplicationServices(this IHostApplicationBuilder builder)
    {
        builder.Services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(Assembly.GetExecutingAssembly());
            cfg.AddOpenBehavior(typeof(ValidationBehaviour<,>));
            cfg.AddOpenBehavior(typeof(PerformanceBehaviour<,>));
        });

        builder.Services.AddValidatorsFromAssembly(Assembly.GetExecutingAssembly());
        builder.Services.AddAutoMapper(Assembly.GetExecutingAssembly());
    }
}
```

```csharp
// Program.cs — compose all layers
var builder = WebApplication.CreateBuilder(args);
builder.AddApplicationServices();
builder.AddInfrastructureServices();
builder.AddWebServices();

var app = builder.Build();
app.MapEndpoints();
app.Run();
```

### Service Lifetime Rules

| Lifetime | Use For |
|----------|---------|
| Singleton | Stateless services, `HttpClient` factories, configuration |
| Scoped | `DbContext`, unit of work, per-request services |
| Transient | Lightweight stateless services, validators |

---

## 5. Nullable Reference Types

Always enable nullable reference types:

```xml
<!-- Directory.Build.props -->
<PropertyGroup>
    <Nullable>enable</Nullable>
</PropertyGroup>
```

```csharp
// CORRECT: Nullable annotations
public async Task<Order?> GetByIdAsync(int id, CancellationToken cancellationToken)
{
    return await _context.Orders.FindAsync([id], cancellationToken);
}

// CORRECT: Guard clause
public void Process(Order order)
{
    Guard.Against.Null(order);
    // ...
}

// WRONG: No null check, suppressed warnings
public void Process(Order order)
{
    var name = order.Customer!.Name;  // Null suppression hides bugs
}
```

---

## 6. Modern C# Features

### Records for Immutable Data

```csharp
// Command — immutable request
public record CreateOrderCommand(int CustomerId, List<OrderItem> Items) : IRequest<int>;

// DTO — immutable data transfer
public record OrderBriefDto(int Id, string Title, bool Done);

// Query with defaults
public record GetOrdersQuery : IRequest<PaginatedList<OrderBriefDto>>
{
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 10;
}
```

### Pattern Matching

```csharp
// CORRECT: Pattern matching for control flow
return exception switch
{
    ValidationException => StatusCodes.Status400BadRequest,
    NotFoundException => StatusCodes.Status404NotFound,
    UnauthorizedAccessException => StatusCodes.Status401Unauthorized,
    _ => StatusCodes.Status500InternalServerError,
};
```

### Extension Members (C# 14)

```csharp
// CORRECT: C# 14 extension block syntax — properties, methods, operators
public static class StringExtensions
{
    extension(string input)
    {
        public bool IsNullOrEmpty => string.IsNullOrEmpty(input);
        public string Cleaned => input.Trim().ToLowerInvariant();
        public string Truncate(int maxLength) =>
            input.Length <= maxLength ? input : input[..maxLength] + "...";
    }
}

// Usage — feels like native members
var name = "  Hello World  ";
bool empty = name.IsNullOrEmpty;     // Extension property
string clean = name.Cleaned;         // Extension property
string short_ = name.Truncate(5);    // Extension method

// WRONG: Old C# 13 extension method syntax (still works but prefer extension blocks)
public static class StringExtensions
{
    public static bool IsNullOrEmpty(this string input) => string.IsNullOrEmpty(input);
}
```

### `field` Keyword — Semi-Auto Properties (C# 14)

```csharp
// CORRECT: field keyword eliminates manual backing fields
public string Name
{
    get;
    set => field = value ?? throw new ArgumentNullException(nameof(value));
}

public int Age
{
    get;
    set => field = value >= 0 ? value : throw new ArgumentOutOfRangeException(nameof(value));
}

// WRONG: Manual backing field (pre-C# 14)
private string _name = null!;
public string Name
{
    get => _name;
    set => _name = value ?? throw new ArgumentNullException(nameof(value));
}
```

### Null-Conditional Assignment (C# 14)

```csharp
// CORRECT: Assign only if receiver is not null
customer?.Name = "Updated Name";
order?.Items?.Add(newItem);

// WRONG: Verbose null check (pre-C# 14)
if (customer is not null)
{
    customer.Name = "Updated Name";
}
```

### Other C# 14 Features

```csharp
// nameof on unbound generics — no dummy type arguments needed
string name = nameof(List<>);          // "List"
string dict = nameof(Dictionary<,>);   // "Dictionary"

// Partial constructors and events — for source generators
public partial class MyService
{
    public partial MyService(ILogger logger);
    public partial event EventHandler<DataEventArgs> DataReceived;
}

// ref/in/out in lambdas without explicit parameter types
Span<int> span = stackalloc int[] { 1, 2, 3 };
span.Sort((ref readonly x, ref readonly y) => x.CompareTo(y));
```

### Collection Expressions (C# 12+)

```csharp
// CORRECT: Collection expressions
List<string> names = ["Alice", "Bob", "Charlie"];
int[] numbers = [1, 2, 3, 4, 5];
private readonly List<OrderItem> _items = [];

// WRONG: Old syntax
var names = new List<string> { "Alice", "Bob", "Charlie" };
```

---

## 7. Performance Guidelines

| Guideline | Detail |
|-----------|--------|
| Async all the way | Never `.Result` or `.Wait()` on async — deadlock risk |
| `CancellationToken` everywhere | Pass through all async method signatures |
| `.AsNoTracking()` for reads | EF Core read queries don't need change tracking |
| `ValueTask<T>` for hot paths | When result is often synchronously available |
| `IAsyncEnumerable<T>` for streaming | Don't load entire result sets into memory |
| `StringBuilder` for string concatenation | In loops, not for 2-3 concatenations |
| Avoid LINQ in hot paths | Allocates enumerators and closures |
| `Span<T>` / `ReadOnlySpan<T>` | For high-performance memory operations |

---

## Anti-Patterns to Avoid

1. **Block-scoped namespaces**: Use file-scoped namespaces — one less indentation level
2. **Mutable DTOs**: Use `record` types for data transfer objects
3. **`async void`**: Only for event handlers — all other async methods return `Task` or `Task<T>`
4. **`.Result` or `.Wait()` on async**: Causes deadlocks — async all the way
5. **Missing `CancellationToken`**: Every async method signature should accept it
6. **`null!` suppression**: Use proper null checks or make the type nullable
7. **Service locator pattern**: Use constructor injection, not `IServiceProvider.GetService<T>()`
8. **Fat controllers/endpoints**: Business logic goes in MediatR handlers, not endpoints
9. **Missing `TreatWarningsAsErrors`**: Always enable in `Directory.Build.props`
10. **No Central Package Management**: Use `Directory.Packages.props` for version pinning
