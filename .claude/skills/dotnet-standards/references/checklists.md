# Quality Checklists

Run through these checklists before completing code.

---

## Pre-Commit Checklist

### Safety
- [ ] Nullable reference types enabled (`<Nullable>enable</Nullable>`)
- [ ] No `null!` suppression — use proper null checks or make type nullable
- [ ] No `async void` — return `Task` or `ValueTask`
- [ ] No `.Result` or `.Wait()` — async all the way
- [ ] `CancellationToken` passed through all async method signatures

### Error Handling
- [ ] Domain exceptions for business rules (`NotFoundException`, `ForbiddenAccessException`)
- [ ] `ValidationException` wraps FluentValidation failures
- [ ] `IExceptionHandler` maps exceptions to ProblemDetails
- [ ] No swallowed exceptions — all caught exceptions are logged or rethrown

### Code Style
- [ ] File-scoped namespaces (`namespace Foo;`)
- [ ] `record` types for DTOs, commands, and queries
- [ ] Modern C# features (pattern matching, collection expressions, primary constructors)
- [ ] Naming conventions followed (PascalCase public, `_camelCase` private fields)
- [ ] Global usings in `GlobalUsings.cs`
- [ ] Imports sorted (System first)

### Architecture
- [ ] Clean Architecture layers respected (Domain → Application → Infrastructure → Web)
- [ ] Business logic in MediatR handlers, not endpoints
- [ ] DI registered via layer extension methods (`AddApplicationServices()`)
- [ ] `IApplicationDbContext` interface in Application, implementation in Infrastructure
- [ ] One class per file (command + handler co-located is the exception)

### Performance
- [ ] `.AsNoTracking()` on EF Core read queries
- [ ] `.ProjectTo<T>()` for DTO projection (not manual mapping after loading)
- [ ] No N+1 queries — use `.Include()` or projection
- [ ] `ValueTask<T>` for hot paths that often complete synchronously

### Documentation
- [ ] XML doc comments on public APIs (`<summary>`)
- [ ] Endpoint attributes (`[EndpointSummary]`, `[EndpointDescription]`)

### Project Configuration
- [ ] `TreatWarningsAsErrors` enabled in `Directory.Build.props`
- [ ] Central Package Management via `Directory.Packages.props`
- [ ] `global.json` pins SDK version
- [ ] `.editorconfig` at solution root

---

## CQRS Checklist

- [ ] Commands for writes, queries for reads — never mix
- [ ] Every command has a corresponding validator
- [ ] Validators registered via `AddValidatorsFromAssembly`
- [ ] Pipeline behaviors: Validation → Authorization → Logging → Performance
- [ ] Domain events raised in entities, handled in Application layer
- [ ] Handlers use `IApplicationDbContext`, not direct `DbContext`

---

## API Endpoint Checklist

- [ ] Endpoints grouped via `EndpointGroupBase`
- [ ] `TypedResults` used (not untyped `IResult`)
- [ ] `RequireAuthorization()` on protected endpoints
- [ ] `[EndpointSummary]` and `[EndpointDescription]` attributes
- [ ] `ISender` injected, commands/queries sent via MediatR
- [ ] Proper HTTP methods (GET for queries, POST for create, PUT for update, DELETE for delete)

---

## EF Core Checklist

- [ ] Entity configurations in `IEntityTypeConfiguration<T>` classes
- [ ] Interceptors for cross-cutting concerns (auditing, domain events)
- [ ] Migrations in Infrastructure project
- [ ] `DbContext` registered as Scoped
- [ ] Connection string from configuration, not hardcoded

---

## Testing Checklist

- [ ] Validators tested with `TestValidateAsync`
- [ ] Handlers tested with mocked dependencies
- [ ] Integration tests use `WebApplicationFactory<Program>`
- [ ] AutoMapper configuration validated (`AssertConfigurationIsValid`)
- [ ] Database reset between tests (Respawn or fresh database)
- [ ] Test names follow `Method_Scenario_Expected` pattern

---

## Code Review Questions

Ask yourself before submitting:

1. **Would a new developer understand this code from the naming and structure?**
2. **If this fails at 3 AM, can I debug it from the logs and error messages?**
3. **Am I following the clean architecture dependency rule?** (Inner layers don't reference outer)
4. **Is this the simplest solution that satisfies the requirement?**
5. **Would this code survive a code analyzer with `TreatWarningsAsErrors`?**
