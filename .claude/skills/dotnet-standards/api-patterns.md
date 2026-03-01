# API Patterns (Minimal APIs)

## Endpoint Group Pattern

```csharp
// Infrastructure/EndpointGroupBase.cs
namespace MyApp.Web.Infrastructure;

public abstract class EndpointGroupBase
{
    public virtual string? GroupName { get; }
    public abstract void Map(RouteGroupBuilder groupBuilder);
}
```

```csharp
// Infrastructure/WebApplicationExtensions.cs
public static class WebApplicationExtensions
{
    public static RouteGroupBuilder MapGroup(this WebApplication app, EndpointGroupBase group)
    {
        var groupName = group.GroupName ?? group.GetType().Name;
        return app.MapGroup($"/api/{groupName}")
            .WithTags(groupName)
            .WithOpenApi();
    }

    public static WebApplication MapEndpoints(this WebApplication app)
    {
        var endpointGroups = typeof(Program).Assembly
            .GetExportedTypes()
            .Where(t => t.IsSubclassOf(typeof(EndpointGroupBase)) && !t.IsAbstract)
            .Select(Activator.CreateInstance)
            .Cast<EndpointGroupBase>();

        foreach (var group in endpointGroups)
        {
            group.Map(app.MapGroup(group));
        }

        return app;
    }
}
```

---

## Endpoint Implementation

```csharp
namespace MyApp.Web.Endpoints;

public class Orders : EndpointGroupBase
{
    public override void Map(RouteGroupBuilder group)
    {
        group.MapGet(GetOrders).RequireAuthorization();
        group.MapGet(GetOrder, "{id}").RequireAuthorization();
        group.MapPost(CreateOrder).RequireAuthorization();
        group.MapPut(UpdateOrder, "{id}").RequireAuthorization();
        group.MapDelete(DeleteOrder, "{id}").RequireAuthorization();
    }

    [EndpointSummary("Get paginated orders")]
    public async Task<Ok<PaginatedList<OrderDto>>> GetOrders(
        ISender sender,
        [AsParameters] GetOrdersQuery query)
    {
        return TypedResults.Ok(await sender.Send(query));
    }

    [EndpointSummary("Get order by ID")]
    public async Task<Results<Ok<OrderDto>, NotFound>> GetOrder(
        ISender sender, int id)
    {
        var result = await sender.Send(new GetOrderQuery(id));
        return result is not null
            ? TypedResults.Ok(result)
            : TypedResults.NotFound();
    }

    [EndpointSummary("Create a new order")]
    public async Task<Created<int>> CreateOrder(
        ISender sender, CreateOrderCommand command)
    {
        var id = await sender.Send(command);
        return TypedResults.Created($"/api/Orders/{id}", id);
    }

    [EndpointSummary("Update an order")]
    public async Task<Results<NoContent, BadRequest>> UpdateOrder(
        ISender sender, int id, UpdateOrderCommand command)
    {
        if (id != command.Id) return TypedResults.BadRequest();
        await sender.Send(command);
        return TypedResults.NoContent();
    }

    [EndpointSummary("Delete an order")]
    public async Task<NoContent> DeleteOrder(ISender sender, int id)
    {
        await sender.Send(new DeleteOrderCommand(id));
        return TypedResults.NoContent();
    }
}
```

---

## Typed Results

Use `TypedResults` for compile-time safety and OpenAPI schema generation:

```csharp
// CORRECT: Typed results — OpenAPI knows the response types
public async Task<Results<Ok<OrderDto>, NotFound, BadRequest<ValidationProblemDetails>>> GetOrder(...)

// WRONG: Untyped IResult — OpenAPI can't infer response schema
public async Task<IResult> GetOrder(...)
```

---

## OpenAPI / Scalar

```csharp
// Program.cs
app.MapOpenApi();              // Built-in OpenAPI 3.1 support (.NET 9+)
app.MapScalarApiReference();   // Scalar UI (replaces Swagger UI)
```

---

## Middleware Pipeline (Program.cs)

```csharp
var builder = WebApplication.CreateBuilder(args);

// Register services per layer
builder.AddApplicationServices();
builder.AddInfrastructureServices();
builder.AddWebServices();

var app = builder.Build();

// Middleware order matters
if (app.Environment.IsDevelopment())
{
    await app.InitialiseDatabaseAsync();
}
else
{
    app.UseHsts();
}

app.UseHealthChecks("/health");
app.UseHttpsRedirection();
app.UseStaticFiles();

app.MapOpenApi();
app.MapScalarApiReference();

app.UseExceptionHandler(options => { });

app.MapEndpoints();

app.Run();

public partial class Program { }  // For integration test WebApplicationFactory
```

---

## API Versioning

```csharp
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
})
.AddApiExplorer(options =>
{
    options.GroupNameFormat = "'v'VVV";
    options.SubstituteApiVersionInUrl = true;
});
```

---

## Anti-Patterns

1. **Fat endpoints**: Business logic goes in MediatR handlers, not endpoint methods
2. **Untyped `IResult`**: Use `TypedResults` for OpenAPI schema generation
3. **Missing `RequireAuthorization()`**: Endpoints are anonymous by default — always add auth
4. **Hardcoded routes**: Use endpoint group pattern for consistent `/api/{GroupName}` routing
5. **No `public partial class Program`**: Required for `WebApplicationFactory<Program>` in tests
6. **Swagger instead of Scalar**: Use `.MapScalarApiReference()` (modern, .NET 9+ aligned)
