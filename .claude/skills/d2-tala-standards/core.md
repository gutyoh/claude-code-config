# Core Principles

## 1. Always Use TALA

Every diagram must use the TALA layout engine. TALA produces superior layouts for software architecture diagrams compared to dagre or ELK, with better symmetry, edge routing, and container handling.

```d2
# CORRECT: TALA via vars block (preferred — embedded in the .d2 file)
vars: {
  d2-config: {
    layout-engine: tala
  }
}

# CORRECT: TALA via CLI flag
# d2 --layout tala input.d2 output.svg

# CORRECT: TALA via env var
# D2_LAYOUT=tala d2 input.d2 output.svg

# WRONG: No layout engine specified (defaults to dagre)
vars: {
  d2-config: {
    theme-id: 0
  }
}
```

## 2. TALA Authentication

TALA requires a valid license token. Authentication is checked in this order:

1. `~/.config/tstruct/auth.json` — persistent token file (created by `d2plugin-tala --auth-token`)
2. `TSTRUCT_TOKEN` environment variable — session-level override

```bash
# Set up persistent auth
d2plugin-tala --auth-token <TOKEN>

# Or use env var for CI/CD
export TSTRUCT_TOKEN="your-token-here"

# Verify auth
d2plugin-tala --version  # Should not error about auth
```

If neither auth method is configured, TALA will fail with an authentication error. Guide the user to obtain a token from https://app.terrastruct.com.

---

# D2 Language Fundamentals

## 3. Shapes

Shapes are declared by assigning a label. The default shape is `rectangle`.

```d2
# Simple shape (rectangle by default)
server: Web Server

# Shape with explicit type
db: Database {shape: cylinder}
user: User {shape: person}
decision: Choose? {shape: diamond}
queue: Task Queue {shape: queue}

# Shape with icon only (no border, just the icon image)
k8s: Kubernetes {
  icon: https://icons.terrastruct.com/azure%2FContainer%20Service%20Color%2FKubernetes%20Services.svg
  shape: image
}

# Shape with icon AND label (icon appears inside the shape)
api: API Gateway {
  icon: https://icons.terrastruct.com/azure%2FNetworking%20Service%20Color%2FFront%20Doors.svg
}
```

## 4. Connections

Connections link shapes with optional labels and styles.

```d2
# Directional
a -> b: request
b -> a: response

# Bidirectional
a <-> b: sync

# Undirected (no arrows)
a -- b: associated

# Multiple connections between same shapes create parallel edges
a -> b: HTTP
a -> b: gRPC
```

## 5. Containers

Containers group related shapes. Any shape with children becomes a container.

```d2
# Container with children
region: West US 2 {
  vnet: Virtual Network {
    subnet: Private Subnet {
      service-a: Service A
      service-b: Service B
    }
  }
}

# Cross-container connections use fully qualified IDs
region.vnet.subnet.service-a -> external: HTTPS
```

**Nesting guideline**: Keep nesting to 3 levels when practical. Deep nesting (4+) makes diagrams harder to read and gives TALA less room to optimize layout.

## 6. Labels

Labels are the text after the colon in shape and connection declarations.

```d2
# Shape label
my-service: My Service Name

# Multiline label (use \n)
gateway: "Virtual Network\nGateway"

# Connection label
a -> b: HTTPS {style.stroke: "#0078D4"}

# Markdown label (for rich text blocks)
explanation: |md
  **Title**: Description here
  - Item 1
  - Item 2
|
```

## 7. Comments

```d2
# This is a comment — ignored by the parser
server: Web Server  # Inline comments also work
```

---

# TALA Configuration

## 8. vars Block

The `vars` block configures D2 and TALA at the file level.

```d2
vars: {
  d2-config: {
    layout-engine: tala
    theme-id: 0          # 0 = default, 1 = neutral grey, etc.
    pad: 30              # Padding around the diagram in pixels
  }
}
```

The `vars` block must appear at the top level of the file (not inside containers).

## 9. Direction

Direction controls the flow of connections within a container. TALA treats direction as a **suggestion**, not a hard constraint — it may override it for better overall layout.

```d2
# Global direction (applies to root level)
direction: down

# Per-container direction
region: Region {
  direction: right

  services: Services {
    direction: down
    a: Service A
    b: Service B
  }
}
```

Valid values: `up`, `down`, `left`, `right`

Default: `down` (top-to-bottom with right-leaning bias)

---

# Reserved Keywords

## 10. TALA Positioning Keywords

**CRITICAL**: The following words are reserved by TALA for the `near` positioning system. **Never use them as node IDs**.

| Reserved Word | TALA Meaning |
|---------------|-------------|
| `top-left` | Near constant position |
| `top-center` | Near constant position |
| `top-right` | Near constant position |
| `center-left` | Near constant position |
| `center-right` | Near constant position |
| `bottom-left` | Near constant position |
| `bottom-center` | Near constant position |
| `bottom-right` | Near constant position |

Additionally, avoid using bare `top`, `left`, `right`, `bottom` as node IDs — while not all are `near` constants, they are used by TALA's pixel-positioning system (`top:` and `left:` properties) and can cause ambiguity.

```d2
# WRONG: "top" and "bottom" as node IDs
top: Header
bottom: Footer

# CORRECT: Use descriptive names
header: Header
footer: Footer
```

---

# Icon URL Encoding

## 11. Always Use %20 for Spaces

Terrastruct icon URLs use `%20` for spaces in path segments. Using `+` will result in 404 errors.

```d2
# CORRECT: %20 encoding
icon: https://icons.terrastruct.com/azure%2FWeb%20Service%20Color%2FApp%20Services.svg

# WRONG: + encoding (will 404)
icon: https://icons.terrastruct.com/azure%2FWeb+Service+Color%2FApp+Services.svg

# WRONG: Unencoded spaces (will fail to parse)
icon: https://icons.terrastruct.com/azure%2FWeb Service Color%2FApp Services.svg
```

Common icon URL patterns:

```
# Azure services
https://icons.terrastruct.com/azure%2F<Category>%2F<ServiceName>.svg

# Examples
https://icons.terrastruct.com/azure%2FContainer%20Service%20Color%2FKubernetes%20Services.svg
https://icons.terrastruct.com/azure%2FSecurity%20Service%20Color%2FKey%20Vaults.svg
https://icons.terrastruct.com/azure%2FDatabases%20Service%20Color%2FAzure%20Database%20for%20PostgreSQL%20servers.svg
https://icons.terrastruct.com/azure%2FNetworking%20Service%20Color%2FFront%20Doors.svg
https://icons.terrastruct.com/azure%2FAI%20and%20ML%20Service%20Color%2FCognitive%20Services.svg
https://icons.terrastruct.com/azure%2FStorage%20Service%20Color%2FBlob%20Storage.svg
https://icons.terrastruct.com/azure%2FIdentity%20Service%20Color%2FManaged%20Identities.svg
https://icons.terrastruct.com/azure%2FDevOps%20Service%20Color%2FAzure%20Pipelines.svg

# General icons
https://icons.terrastruct.com/essentials%2F359-users.svg
```

---

# Variables

## 12. Variable Syntax

Variables are defined in the `vars` block and referenced with `${varname}`.

```d2
vars: {
  primary-color: "#0078D4"
  region-name: West US 2
}

region: ${region-name} {
  style.stroke: ${primary-color}
}
```

Note: `vars.d2-config` is special — it configures D2 itself and is not available for interpolation.

---

# Classes

## 13. Class Definitions

Classes define reusable bundles of shape type, icon, and style properties. Define them at the top of the file.

```d2
classes: {
  # Icon-only class (no border, just the SVG)
  k8s: {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FContainer%20Service%20Color%2FKubernetes%20Services.svg
  }

  # Styled rectangle class
  ms: {
    style: {
      fill: "#e8f4fd"
      stroke: "#0078D4"
      stroke-width: 2
      border-radius: 6
      font-size: 13
    }
  }

  # Icon + style class (icon inside a styled shape)
  database: {
    icon: https://icons.terrastruct.com/azure%2FDatabases%20Service%20Color%2FAzure%20Database%20for%20PostgreSQL%20servers.svg
    style: {
      fill: "#f0f5fb"
      stroke: "#0078D4"
    }
  }
}

# Apply a class
service: My Service {class: ms}
cluster: Kubernetes {class: k8s}
```

---

# Anti-Patterns to Avoid

1. **Missing TALA**: Never forget `layout-engine: tala` — dagre produces inferior layouts for architecture diagrams
2. **`+` in icon URLs**: Always use `%20` — `+` causes 404 errors on Terrastruct's CDN
3. **Reserved keyword node IDs**: Never use `top`, `left`, `right`, `bottom`, `top-left`, `top-center`, etc. as shape IDs
4. **Deep nesting (4+ levels)**: Flatten the hierarchy where possible — deep nesting reduces TALA's ability to optimize
5. **Inline styles on every shape**: Use classes for repeated icon+style combinations
6. **Unquoted multiline labels**: Use `"Line 1\nLine 2"` with quotes for multiline labels
7. **Missing fully qualified IDs**: Cross-container connections must use the full path (`region.vnet.subnet.service`)
8. **Hardcoded TALA auth tokens in files**: Use `~/.config/tstruct/auth.json` or `TSTRUCT_TOKEN` env var
9. **Guessing icon URLs**: Verify URLs exist — Terrastruct's icon library uses specific naming. Check https://icons.terrastruct.com for available icons
10. **vars block inside containers**: The `vars` block must be at the root level of the file
