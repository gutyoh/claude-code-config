# Testing Patterns

## Unit Tests

### Test Naming Convention

```csharp
// Pattern: MethodName_Scenario_ExpectedResult
[Test]
public async Task Handle_ValidCommand_ReturnsCreatedId() { ... }

[Test]
public async Task Handle_InvalidCustomerId_ThrowsValidationException() { ... }

[Test]
public void Validate_EmptyTitle_HasValidationError() { ... }
```

### Testing Validators

```csharp
public class CreateOrderCommandValidatorTests
{
    private readonly CreateOrderCommandValidator _validator = new();

    [Test]
    public async Task Validate_ValidCommand_HasNoErrors()
    {
        var command = new CreateOrderCommand(CustomerId: 1, Items: [new(1, 2, 10.00m)]);
        var result = await _validator.TestValidateAsync(command);
        result.ShouldNotHaveAnyValidationErrors();
    }

    [Test]
    public async Task Validate_EmptyItems_HasValidationError()
    {
        var command = new CreateOrderCommand(CustomerId: 1, Items: []);
        var result = await _validator.TestValidateAsync(command);
        result.ShouldHaveValidationErrorFor(c => c.Items);
    }

    [Test]
    public async Task Validate_ZeroCustomerId_HasValidationError()
    {
        var command = new CreateOrderCommand(CustomerId: 0, Items: [new(1, 1, 5.00m)]);
        var result = await _validator.TestValidateAsync(command);
        result.ShouldHaveValidationErrorFor(c => c.CustomerId);
    }
}
```

### Testing Handlers with Mocks

```csharp
public class GetOrdersQueryHandlerTests
{
    private readonly Mock<IApplicationDbContext> _context;
    private readonly IMapper _mapper;
    private readonly GetOrdersQueryHandler _handler;

    public GetOrdersQueryHandlerTests()
    {
        _context = new Mock<IApplicationDbContext>();
        var configurationProvider = new MapperConfiguration(cfg =>
            cfg.AddMaps(Assembly.GetAssembly(typeof(GetOrdersQuery))));
        _mapper = configurationProvider.CreateMapper();
        _handler = new GetOrdersQueryHandler(_context.Object, _mapper);
    }
}
```

---

## Integration Tests with WebApplicationFactory

### Base Test Class

```csharp
[TestFixture]
public abstract class BaseIntegrationTest
{
    private static WebApplicationFactory<Program> _factory = null!;
    private static IServiceScopeFactory _scopeFactory = null!;

    [OneTimeSetUp]
    public void OneTimeSetUp()
    {
        _factory = new CustomWebApplicationFactory();
        _scopeFactory = _factory.Services.GetRequiredService<IServiceScopeFactory>();
    }

    protected static async Task<TResponse> SendAsync<TResponse>(IRequest<TResponse> request)
    {
        using var scope = _scopeFactory.CreateScope();
        var mediator = scope.ServiceProvider.GetRequiredService<ISender>();
        return await mediator.Send(request);
    }

    protected static async Task<TEntity?> FindAsync<TEntity>(params object[] keyValues)
        where TEntity : class
    {
        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        return await context.FindAsync<TEntity>(keyValues);
    }
}
```

### Custom WebApplicationFactory

```csharp
public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services =>
        {
            // Replace real database with shared in-memory SQLite connection
            // IMPORTANT: SQLite in-memory DBs are per-connection — a shared open
            // connection ensures all DbContext instances see the same database
            services.RemoveAll<DbContextOptions<ApplicationDbContext>>();
            services.RemoveAll<DbConnection>();

            services.AddSingleton<DbConnection>(_ =>
            {
                var connection = new SqliteConnection("DataSource=:memory:");
                connection.Open();
                return connection;
            });

            services.AddDbContext<ApplicationDbContext>((sp, options) =>
                options.UseSqlite(sp.GetRequiredService<DbConnection>()));
        });
    }
}
```

### Testcontainers for Real Database Testing

```csharp
public class PostgresTestFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public string ConnectionString => _container.GetConnectionString();

    public async Task InitializeAsync() => await _container.StartAsync();
    public async Task DisposeAsync() => await _container.DisposeAsync();
}
```

---

## Database Reset with Respawn

```csharp
private static Respawner _respawner = null!;

public static async Task ResetDatabaseAsync()
{
    using var scope = _scopeFactory.CreateScope();
    var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    var connection = context.Database.GetDbConnection();
    await connection.OpenAsync();
    _respawner ??= await Respawner.CreateAsync(connection);
    await _respawner.ResetAsync(connection);
}
```

---

## Test Project Structure

```
tests/
├── Application.UnitTests/
│   ├── Common/
│   │   └── Mappings/
│   │       └── MappingTests.cs
│   └── Orders/
│       ├── Commands/
│       │   └── CreateOrderValidatorTests.cs
│       └── Queries/
│           └── GetOrdersTests.cs
├── Application.FunctionalTests/
│   ├── BaseIntegrationTest.cs
│   ├── CustomWebApplicationFactory.cs
│   └── Orders/
│       ├── Commands/
│       │   └── CreateOrderTests.cs
│       └── Queries/
│           └── GetOrdersTests.cs
└── Web.AcceptanceTests/
    └── Orders/
        └── OrderEndpointTests.cs
```

---

## Mapping Tests

```csharp
public class MappingTests
{
    private readonly IMapper _mapper;

    public MappingTests()
    {
        var configuration = new MapperConfiguration(cfg =>
            cfg.AddMaps(Assembly.GetAssembly(typeof(DependencyInjection))));
        _mapper = configuration.CreateMapper();
    }

    [Test]
    public void ShouldHaveValidConfiguration()
    {
        _mapper.ConfigurationProvider.AssertConfigurationIsValid();
    }

    [Test]
    public void ShouldMapOrderToOrderDto()
    {
        var order = new Order { Id = 1, CustomerName = "Test" };
        var dto = _mapper.Map<OrderDto>(order);
        dto.Id.ShouldBe(1);
    }
}
```

---

## Anti-Patterns

1. **No integration tests**: Unit tests alone miss DI, EF Core, and middleware issues
2. **Shared mutable state between tests**: Use `Respawn` to reset database per test
3. **Testing implementation details**: Test behavior through the public API (MediatR handlers)
4. **Hardcoded connection strings**: Use Testcontainers or in-memory databases
5. **Missing `[OneTimeSetUp]`**: Expensive setup (WebApplicationFactory) should run once
6. **No mapping validation**: Always test `AssertConfigurationIsValid()` for AutoMapper
