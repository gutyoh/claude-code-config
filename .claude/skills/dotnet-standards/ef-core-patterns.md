# Entity Framework Core Patterns

## DbContext Interface

Define a thin interface in the Application layer — the Infrastructure layer implements it:

```csharp
// Application/Common/Interfaces/IApplicationDbContext.cs
public interface IApplicationDbContext
{
    DbSet<Order> Orders { get; }
    DbSet<Customer> Customers { get; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken);
}
```

```csharp
// Infrastructure/Data/ApplicationDbContext.cs
public class ApplicationDbContext : DbContext, IApplicationDbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options) { }

    public DbSet<Order> Orders => Set<Order>();
    public DbSet<Customer> Customers => Set<Customer>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        builder.ApplyConfigurationsFromAssembly(Assembly.GetExecutingAssembly());
        base.OnModelCreating(builder);
    }
}
```

---

## Entity Configuration (Fluent API)

```csharp
// Infrastructure/Data/Configurations/OrderConfiguration.cs
public class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.HasKey(o => o.Id);

        builder.Property(o => o.CustomerName)
            .HasMaxLength(200)
            .IsRequired();

        builder.Property(o => o.Total)
            .HasPrecision(18, 2);

        builder.HasMany(o => o.Items)
            .WithOne()
            .HasForeignKey(i => i.OrderId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(o => o.CreatedAt);
    }
}
```

---

## Query Patterns

### Read Queries — AsNoTracking

```csharp
// CORRECT: No tracking for read-only queries
public async Task<OrderDto?> Handle(GetOrderQuery request, CancellationToken cancellationToken)
{
    return await _context.Orders
        .AsNoTracking()
        .Where(o => o.Id == request.Id)
        .ProjectTo<OrderDto>(_mapper.ConfigurationProvider)
        .FirstOrDefaultAsync(cancellationToken);
}
```

### Pagination

```csharp
public static class QueryableExtensions
{
    public static async Task<PaginatedList<T>> PaginatedListAsync<T>(
        this IQueryable<T> source, int pageNumber, int pageSize,
        CancellationToken cancellationToken)
    {
        var count = await source.CountAsync(cancellationToken);
        var items = await source
            .Skip((pageNumber - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(cancellationToken);

        return new PaginatedList<T>(items, count, pageNumber, pageSize);
    }
}
```

### Projection with AutoMapper

```csharp
// CORRECT: Project at the database level — only selects needed columns
var dtos = await _context.Orders
    .AsNoTracking()
    .ProjectTo<OrderDto>(_mapper.ConfigurationProvider)
    .ToListAsync(cancellationToken);

// WRONG: Load full entities then map in memory
var orders = await _context.Orders.ToListAsync(cancellationToken);
var dtos = _mapper.Map<List<OrderDto>>(orders);
```

---

## Write Patterns

### Interceptors for Cross-Cutting Concerns

```csharp
// Auditable entity interceptor — auto-sets CreatedBy, LastModified
public class AuditableEntityInterceptor : SaveChangesInterceptor
{
    private readonly IUser _user;
    private readonly TimeProvider _timeProvider;

    public AuditableEntityInterceptor(IUser user, TimeProvider timeProvider)
    {
        _user = user;
        _timeProvider = timeProvider;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result,
        CancellationToken cancellationToken)
    {
        UpdateEntities(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    private void UpdateEntities(DbContext? context)
    {
        if (context is null) return;

        foreach (var entry in context.ChangeTracker.Entries<BaseAuditableEntity>())
        {
            if (entry.State is EntityState.Added)
            {
                entry.Entity.CreatedBy = _user.Id;
                entry.Entity.Created = _timeProvider.GetUtcNow();
            }

            if (entry.State is EntityState.Added or EntityState.Modified)
            {
                entry.Entity.LastModifiedBy = _user.Id;
                entry.Entity.LastModified = _timeProvider.GetUtcNow();
            }
        }
    }
}
```

---

## Migrations

```bash
# Add a migration (from the Web project directory)
dotnet ef migrations add InitialCreate --project src/Infrastructure --startup-project src/Web

# Update database
dotnet ef database update --project src/Infrastructure --startup-project src/Web
```

---

## Database Initialization

```csharp
public class ApplicationDbContextInitialiser
{
    private readonly ApplicationDbContext _context;
    private readonly ILogger<ApplicationDbContextInitialiser> _logger;

    public ApplicationDbContextInitialiser(
        ApplicationDbContext context,
        ILogger<ApplicationDbContextInitialiser> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task InitialiseAsync()
    {
        try
        {
            await _context.Database.MigrateAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "An error occurred while migrating the database");
            throw;
        }
    }

    public async Task SeedAsync()
    {
        if (!await _context.Orders.AnyAsync())
        {
            // Seed initial data
        }
    }
}
```

---

## Anti-Patterns

1. **Missing `.AsNoTracking()`**: Always use for read-only queries — saves memory and CPU
2. **Loading full entities for DTOs**: Use `.ProjectTo<T>()` to select only needed columns
3. **N+1 queries**: Use `.Include()` or `.ProjectTo<T>()` to load related data in one query
4. **DbContext as Singleton**: DbContext must be Scoped (one per request)
5. **Business logic in DbContext**: Keep domain logic in entities and handlers
6. **Raw SQL without parameters**: Always use parameterized queries to prevent SQL injection
7. **Missing entity configuration**: Use `IEntityTypeConfiguration<T>` — never configure in `OnModelCreating` directly
