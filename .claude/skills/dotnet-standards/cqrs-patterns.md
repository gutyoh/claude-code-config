# CQRS Patterns (MediatR)

## Command (Write Operation)

```csharp
// Application/Orders/Commands/CreateOrder/CreateOrder.cs
namespace MyApp.Application.Orders.Commands.CreateOrder;

public record CreateOrderCommand(int CustomerId, List<OrderItemDto> Items) : IRequest<int>;

public class CreateOrderCommandHandler : IRequestHandler<CreateOrderCommand, int>
{
    private readonly IApplicationDbContext _context;

    public CreateOrderCommandHandler(IApplicationDbContext context)
    {
        _context = context;
    }

    public async Task<int> Handle(CreateOrderCommand request, CancellationToken cancellationToken)
    {
        var entity = new Order
        {
            CustomerId = request.CustomerId,
        };

        foreach (var item in request.Items)
        {
            entity.AddItem(new OrderItem(item.ProductId, item.Quantity, item.Price));
        }

        entity.AddDomainEvent(new OrderCreatedEvent(entity));

        _context.Orders.Add(entity);
        await _context.SaveChangesAsync(cancellationToken);

        return entity.Id;
    }
}
```

---

## Command Validator

```csharp
// Application/Orders/Commands/CreateOrder/CreateOrderValidator.cs
public class CreateOrderCommandValidator : AbstractValidator<CreateOrderCommand>
{
    public CreateOrderCommandValidator()
    {
        RuleFor(v => v.CustomerId)
            .GreaterThan(0)
            .WithMessage("Customer ID must be a positive number.");

        RuleFor(v => v.Items)
            .NotEmpty()
            .WithMessage("Order must contain at least one item.");

        RuleForEach(v => v.Items).ChildRules(item =>
        {
            item.RuleFor(i => i.Quantity)
                .GreaterThan(0)
                .WithMessage("Item quantity must be positive.");
        });
    }
}
```

---

## Query (Read Operation)

```csharp
// Application/Orders/Queries/GetOrders/GetOrders.cs
namespace MyApp.Application.Orders.Queries.GetOrders;

public record GetOrdersQuery : IRequest<PaginatedList<OrderBriefDto>>
{
    public int PageNumber { get; init; } = 1;
    public int PageSize { get; init; } = 10;
}

public class GetOrdersQueryHandler : IRequestHandler<GetOrdersQuery, PaginatedList<OrderBriefDto>>
{
    private readonly IApplicationDbContext _context;
    private readonly IMapper _mapper;

    public GetOrdersQueryHandler(IApplicationDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<PaginatedList<OrderBriefDto>> Handle(
        GetOrdersQuery request, CancellationToken cancellationToken)
    {
        return await _context.Orders
            .AsNoTracking()
            .OrderByDescending(o => o.CreatedAt)
            .ProjectTo<OrderBriefDto>(_mapper.ConfigurationProvider)
            .PaginatedListAsync(request.PageNumber, request.PageSize, cancellationToken);
    }
}
```

---

## Pipeline Behaviors

### Validation Behavior

```csharp
public class ValidationBehaviour<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehaviour(IEnumerable<IValidator<TRequest>> validators)
    {
        _validators = validators;
    }

    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        if (_validators.Any())
        {
            var results = await Task.WhenAll(
                _validators.Select(v =>
                    v.ValidateAsync(new ValidationContext<TRequest>(request), cancellationToken)));

            var failures = results
                .Where(r => r.Errors.Count != 0)
                .SelectMany(r => r.Errors)
                .ToList();

            if (failures.Count != 0)
                throw new ValidationException(failures);
        }

        return await next();
    }
}
```

### Performance Behavior

```csharp
public class PerformanceBehaviour<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly ILogger<TRequest> _logger;
    private readonly Stopwatch _timer = new();

    public PerformanceBehaviour(ILogger<TRequest> logger)
    {
        _logger = logger;
    }

    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        _timer.Start();
        var response = await next();
        _timer.Stop();

        var elapsedMs = _timer.ElapsedMilliseconds;

        if (elapsedMs > 500)
        {
            // WARNING: {@Request} destructures the full request — may expose PII.
            // Use Serilog destructuring policies to mask sensitive properties.
            _logger.LogWarning(
                "Long running request: {Name} ({ElapsedMs} ms) {@Request}",
                typeof(TRequest).Name, elapsedMs, request);
        }

        return response;
    }
}
```

---

## Domain Events

```csharp
// Domain/Common/BaseEntity.cs
public abstract class BaseEntity
{
    public int Id { get; set; }

    private readonly List<BaseEvent> _domainEvents = [];
    public IReadOnlyCollection<BaseEvent> DomainEvents => _domainEvents.AsReadOnly();

    public void AddDomainEvent(BaseEvent domainEvent) => _domainEvents.Add(domainEvent);
    public void RemoveDomainEvent(BaseEvent domainEvent) => _domainEvents.Remove(domainEvent);
    public void ClearDomainEvents() => _domainEvents.Clear();
}

// Domain/Events/OrderCreatedEvent.cs
public class OrderCreatedEvent : BaseEvent
{
    public OrderCreatedEvent(Order order) => Order = order;
    public Order Order { get; }
}

// Application/Orders/EventHandlers/OrderCreatedEventHandler.cs
public class OrderCreatedEventHandler : INotificationHandler<OrderCreatedEvent>
{
    private readonly ILogger<OrderCreatedEventHandler> _logger;

    public OrderCreatedEventHandler(ILogger<OrderCreatedEventHandler> logger)
    {
        _logger = logger;
    }

    public Task Handle(OrderCreatedEvent notification, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Order created: {OrderId}", notification.Order.Id);
        return Task.CompletedTask;
    }
}
```

---

## Registration

```csharp
public static void AddApplicationServices(this IHostApplicationBuilder builder)
{
    builder.Services.AddMediatR(cfg =>
    {
        cfg.RegisterServicesFromAssembly(Assembly.GetExecutingAssembly());
        cfg.AddOpenRequestPreProcessor(typeof(LoggingBehaviour<>));
        cfg.AddOpenBehavior(typeof(UnhandledExceptionBehaviour<,>));
        cfg.AddOpenBehavior(typeof(AuthorizationBehaviour<,>));
        cfg.AddOpenBehavior(typeof(ValidationBehaviour<,>));
        cfg.AddOpenBehavior(typeof(PerformanceBehaviour<,>));
    });

    builder.Services.AddValidatorsFromAssembly(Assembly.GetExecutingAssembly());
}
```

---

## File Organization

```
Application/
├── Orders/
│   ├── Commands/
│   │   ├── CreateOrder/
│   │   │   ├── CreateOrder.cs           # Command record + handler (co-located)
│   │   │   └── CreateOrderValidator.cs
│   │   └── DeleteOrder/
│   │       └── DeleteOrder.cs
│   ├── Queries/
│   │   └── GetOrders/
│   │       ├── GetOrders.cs             # Query record + handler (co-located)
│   │       └── OrderBriefDto.cs
│   └── EventHandlers/
│       └── OrderCreatedEventHandler.cs
```

---

## Anti-Patterns

1. **Business logic in endpoints**: Move to command/query handlers
2. **Fat handlers**: Handlers should orchestrate, not contain complex logic — push to domain
3. **Missing validators**: Every command should have a corresponding validator
4. **Mixing reads and writes**: Commands return minimal data (IDs), queries never mutate
5. **Missing `CancellationToken`**: Always pass through handlers
6. **Direct `DbContext` in endpoints**: Use `ISender` to send commands/queries
