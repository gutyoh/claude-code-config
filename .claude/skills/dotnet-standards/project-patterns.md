# Project Patterns

## Directory.Build.props

Shared properties applied to all projects in the solution:

```xml
<!-- Directory.Build.props (solution root) -->
<Project>
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <ArtifactsPath>$(MSBuildThisFileDirectory)artifacts</ArtifactsPath>
  </PropertyGroup>
</Project>
```

### Property Reference

| Property | Value | Purpose |
|----------|-------|---------|
| `TargetFramework` | `net9.0` | .NET version for all projects |
| `TreatWarningsAsErrors` | `true` | Fail build on any warning |
| `ImplicitUsings` | `enable` | Auto-import common namespaces |
| `Nullable` | `enable` | Nullable reference type checking |
| `ArtifactsPath` | `$(MSBuildThisFileDirectory)artifacts` | Centralized build output |

---

## Central Package Management

Pin all NuGet versions in one file:

```xml
<!-- Directory.Packages.props (solution root) -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>

  <PropertyGroup>
    <!-- Version variables for packages that should stay in sync -->
    <AspnetVersion>9.0.0</AspnetVersion>
    <EfcoreVersion>9.0.0</EfcoreVersion>
  </PropertyGroup>

  <ItemGroup>
    <!-- Application -->
    <PackageVersion Include="MediatR" Version="14.0.0" />
    <PackageVersion Include="AutoMapper" Version="16.0.0" />
    <PackageVersion Include="FluentValidation.DependencyInjectionExtensions" Version="12.1.0" />
    <PackageVersion Include="Ardalis.GuardClauses" Version="5.0.0" />

    <!-- Infrastructure -->
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="$(EfcoreVersion)" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Tools" Version="$(EfcoreVersion)" />

    <!-- Web -->
    <PackageVersion Include="Scalar.AspNetCore" Version="2.8.0" />

    <!-- Testing -->
    <PackageVersion Include="NUnit" Version="4.5.0" />
    <PackageVersion Include="NUnit.Analyzers" Version="4.11.0" />
    <PackageVersion Include="Moq" Version="4.20.72" />
    <PackageVersion Include="Shouldly" Version="4.3.0" />
    <PackageVersion Include="Respawn" Version="7.0.0" />
    <PackageVersion Include="Microsoft.AspNetCore.Mvc.Testing" Version="$(AspnetVersion)" />
  </ItemGroup>
</Project>
```

Individual `.csproj` files reference packages without versions:

```xml
<ItemGroup>
  <PackageReference Include="MediatR" />
  <PackageReference Include="AutoMapper" />
</ItemGroup>
```

---

## global.json

Pin the SDK version for reproducible builds:

```json
{
  "sdk": {
    "version": "9.0.100",
    "rollForward": "latestFeature"
  }
}
```

---

## .editorconfig

Essential settings for C# projects:

```ini
root = true

[*]
indent_style = space

[*.{csproj,props,targets,xml}]
indent_size = 2

[*.cs]
indent_size = 4
end_of_line = lf
insert_final_newline = true

# File-scoped namespaces
csharp_style_namespace_declarations = file_scoped:warning

# Primary constructors
csharp_style_prefer_primary_constructors = true:suggestion

# Pattern matching
csharp_style_prefer_switch_expression = true:suggestion
csharp_style_pattern_matching_over_as_with_null_check = true:suggestion

# var preferences
csharp_style_var_for_built_in_types = false:silent
csharp_style_var_when_type_is_apparent = true:suggestion

# Naming
dotnet_naming_rule.private_fields_should_be__camelcase.severity = suggestion
dotnet_naming_rule.private_fields_should_be__camelcase.symbols = private_fields
dotnet_naming_rule.private_fields_should_be__camelcase.style = _camelcase

dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private
dotnet_naming_style._camelcase.required_prefix = _
dotnet_naming_style._camelcase.capitalization = camel_case

# Organization
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false
```

---

## Static Code Analyzers

Add to `Directory.Build.props` for solution-wide analysis:

```xml
<ItemGroup>
  <PackageReference Include="Meziantou.Analyzer" Version="2.0.180">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
  </PackageReference>
  <PackageReference Include="Roslynator.Analyzers" Version="4.12.0">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
  </PackageReference>
  <PackageReference Include="SonarAnalyzer.CSharp" Version="10.3.0">
    <PrivateAssets>all</PrivateAssets>
    <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
  </PackageReference>
</ItemGroup>
```

---

## CI/CD (GitHub Actions)

```yaml
name: Build

on:
  pull_request:
    branches: [main]
    paths-ignore:
      - '*.md'
      - '.gitignore'

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Cache NuGet packages
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: ${{ runner.os }}-nuget-${{ hashFiles('**/Directory.Packages.props') }}
          restore-keys: ${{ runner.os }}-nuget-

      - name: Install .NET
        uses: actions/setup-dotnet@v4

      - name: Restore
        run: dotnet restore

      - name: Build
        run: dotnet build --no-restore --configuration Release

      - name: Test
        run: dotnet test --no-build --configuration Release
```

---

## Docker

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY Directory.Build.props Directory.Packages.props global.json ./
COPY src/Domain/*.csproj src/Domain/
COPY src/Application/*.csproj src/Application/
COPY src/Infrastructure/*.csproj src/Infrastructure/
COPY src/Web/*.csproj src/Web/
RUN dotnet restore src/Web/Web.csproj

COPY src/ src/
RUN dotnet publish src/Web/Web.csproj -c Release -o /app --no-restore

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app .
EXPOSE 8080
ENTRYPOINT ["dotnet", "Web.dll"]
```

---

## Solution Structure

```
MySolution.sln
├── Directory.Build.props
├── Directory.Packages.props
├── global.json
├── .editorconfig
├── .github/
│   └── workflows/
│       └── build.yml
├── src/
│   ├── Domain/
│   ├── Application/
│   ├── Infrastructure/
│   └── Web/
├── tests/
│   ├── Application.UnitTests/
│   └── Application.FunctionalTests/
└── docker-compose.yml
```

---

## Anti-Patterns

1. **No `Directory.Build.props`**: Duplicated settings across every `.csproj`
2. **No Central Package Management**: Version conflicts across projects
3. **Missing `TreatWarningsAsErrors`**: Warnings accumulate and mask real issues
4. **No `global.json`**: Different SDK versions across developer machines
5. **No `.editorconfig`**: Inconsistent formatting across the team
6. **No analyzers**: Miss code quality issues that the compiler doesn't catch
7. **Fat Dockerfiles**: Always use multi-stage builds with separate build/runtime images
