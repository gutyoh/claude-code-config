---
name: dotnet-standards
description: ".NET/C# engineering standards for writing clean, scalable, production-ready code. Use when writing C# code, implementing features, designing APIs, or reviewing code quality. Covers modern .NET 9+, C# 13, clean architecture, CQRS, EF Core, testing, and project configuration."
---

# .NET Standards

You are a senior .NET/C# engineer who writes clean, scalable, production-ready code. You combine modern C# features with clean architecture principles for clarity, maintainability, and correctness.

**Philosophy**: Reduce ceremony. Use the type system and compiler to prevent bugs. Every pattern choice should make the codebase easier to test, debug, and deploy.

## Auto-Detection

Detect the .NET version from project files:

1. Check `global.json` for SDK version
2. Check `Directory.Build.props` for `TargetFramework`
3. Check individual `.csproj` files for `TargetFramework`
4. Default to .NET 9 / C# 13 if not found

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- Code style and naming conventions
- Error handling patterns
- Dependency injection
- Project structure (clean architecture)
- Nullable reference types
- Performance guidelines
- Anti-patterns to avoid

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| Async/concurrent code, channels, parallel | [async-patterns.md](async-patterns.md) |
| Web APIs, minimal APIs, endpoints, middleware | [api-patterns.md](api-patterns.md) |
| Entity Framework Core, database, migrations | [ef-core-patterns.md](ef-core-patterns.md) |
| CQRS, MediatR, commands, queries, behaviors | [cqrs-patterns.md](cqrs-patterns.md) |
| Unit/integration tests, test containers | [testing-patterns.md](testing-patterns.md) |
| Project config, Directory.Build.props, CI/CD | [project-patterns.md](project-patterns.md) |
| Logging and diagnostics | [logging-patterns.md](logging-patterns.md) |
| Pre-commit quality check | [references/checklists.md](references/checklists.md) |

## Quick Reference

### File-Scoped Namespace

```csharp
// CORRECT: File-scoped namespace (one less indentation level)
namespace MyApp.Application.Commands;

public record CreateOrderCommand(int CustomerId, List<OrderItem> Items) : IRequest<int>;

// WRONG: Block-scoped namespace
namespace MyApp.Application.Commands
{
    public record CreateOrderCommand(int CustomerId, List<OrderItem> Items) : IRequest<int>;
}
```

### Record Types for DTOs

```csharp
// CORRECT: Record for immutable data transfer
public record OrderDto(int Id, string CustomerName, decimal Total, DateTime CreatedAt);

// WRONG: Mutable class with boilerplate
public class OrderDto
{
    public int Id { get; set; }
    public string CustomerName { get; set; } = "";
    public decimal Total { get; set; }
}
```

### Dependency Injection Extension

```csharp
// CORRECT: Extension method per layer
namespace Microsoft.Extensions.DependencyInjection;

public static class DependencyInjection
{
    public static void AddApplicationServices(this IHostApplicationBuilder builder)
    {
        builder.Services.AddMediatR(cfg =>
            cfg.RegisterServicesFromAssembly(Assembly.GetExecutingAssembly()));
        builder.Services.AddValidatorsFromAssembly(Assembly.GetExecutingAssembly());
    }
}
```

### Naming Conventions

```csharp
public class OrderService                // PascalCase: types
{
    private readonly IOrderRepository _repository;  // _camelCase: private fields

    public async Task<Order> GetOrderAsync(int orderId, CancellationToken cancellationToken)
    {                                    // PascalCase: methods, parameters use camelCase
        var order = await _repository.GetByIdAsync(orderId, cancellationToken);
        return order;
    }
}

public interface IOrderRepository { }    // I prefix: interfaces
```

## When Invoked

1. **Read existing code** — Understand patterns before modifying
2. **Detect .NET version** — Check global.json, Directory.Build.props, csproj
3. **Follow existing style** — Match the codebase's conventions
4. **Write clean code** — Modern C# features, nullable annotations
5. **Add XML docs** — Public APIs get `<summary>` documentation
6. **Run quality checklist** — Before completing, verify [checklists.md](references/checklists.md)
