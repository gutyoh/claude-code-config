# Style Patterns

## 1. Shape Types

D2 supports these shape types via the `shape:` property:

| Shape | Usage |
|-------|-------|
| `rectangle` | Default. Services, components, generic boxes |
| `square` | Equal-sided box |
| `page` | Document/page shape |
| `parallelogram` | Data transformation, I/O |
| `document` | Document with curved bottom |
| `cylinder` | Databases, storage |
| `queue` | Message queues |
| `package` | Packages, modules |
| `step` | Pipeline steps (arrow-shaped, tail-to-head) |
| `callout` | Annotations, notes |
| `stored_data` | Stored data (disk shape) |
| `person` | Users, actors |
| `diamond` | Decisions, conditionals |
| `oval` | Start/end in flowcharts |
| `circle` | Events, status indicators |
| `hexagon` | Process nodes |
| `cloud` | Cloud services, external systems |
| `text` | Plain text label (no border) |
| `code` | Code block |
| `class` | UML class diagram |
| `sql_table` | Database table with columns |
| `image` | Icon-only (renders just the `icon:` URL) |
| `sequence_diagram` | UML sequence diagram |
| `hierarchy` | Org-chart / tree layout |

```d2
db: PostgreSQL {shape: cylinder}
user: End User {shape: person}
gateway: Cloud Gateway {shape: cloud}
decision: Approved? {shape: diamond}
step-1: Build {shape: step}
```

---

## 2. Style Properties

All style properties are set under `style:` block or inline with `style.<property>`.

```d2
# Block syntax
service: Service {
  style: {
    fill: "#e8f4fd"
    stroke: "#0078D4"
    stroke-width: 2
    stroke-dash: 5
    border-radius: 8
    opacity: 0.9
    shadow: true
    3d: false
    multiple: false
    font-size: 14
    font-color: "#333"
    bold: true
    italic: false
    underline: false
    text-transform: uppercase
  }
}

# Inline syntax
service: Service {style.fill: "#e8f4fd"; style.stroke: "#0078D4"}
```

### Style Property Reference

| Property | Type | Description |
|----------|------|-------------|
| `fill` | Color | Background color |
| `stroke` | Color | Border color |
| `stroke-width` | Number | Border width in pixels |
| `stroke-dash` | Number | Dash pattern (0 = solid) |
| `border-radius` | Number | Corner radius in pixels |
| `opacity` | Float (0-1) | Transparency |
| `shadow` | Boolean | Drop shadow |
| `3d` | Boolean | 3D effect |
| `multiple` | Boolean | Stacked appearance (multiple instances) |
| `font` | String | Font family |
| `font-size` | Number | Font size in pixels |
| `font-color` | Color | Text color |
| `bold` | Boolean | Bold text |
| `italic` | Boolean | Italic text |
| `underline` | Boolean | Underlined text |
| `text-transform` | String | `uppercase`, `lowercase`, `capitalize`, `none` |
| `animated` | Boolean | Animated connection (SVG only) |
| `filled` | Boolean | Whether shape is filled |

### Connection Style Properties

Connections support: `stroke`, `stroke-width`, `stroke-dash`, `font-size`, `font-color`, `bold`, `italic`, `animated`, `opacity`.

```d2
a -> b: HTTPS {
  style: {
    stroke: "#0078D4"
    stroke-width: 2
    stroke-dash: 0
    animated: true
    font-size: 12
  }
}
```

---

## 3. Icons

### Icon on a Shaped Node

The icon appears inside the shape alongside the label:

```d2
api: API Gateway {
  icon: https://icons.terrastruct.com/azure%2FNetworking%20Service%20Color%2FFront%20Doors.svg
  style.fill: "#e8f4fd"
}
```

### Icon-Only Node (shape: image)

No shape border — renders just the icon with a label below:

```d2
k8s: Kubernetes {
  icon: https://icons.terrastruct.com/azure%2FContainer%20Service%20Color%2FKubernetes%20Services.svg
  shape: image
}
```

### Terrastruct Icon URL Patterns

All Terrastruct icons follow this pattern:
```
https://icons.terrastruct.com/<category>%2F<icon-name>.svg
```

Spaces in category and icon names use `%20`, path separators use `%2F`.

**Common Azure categories:**
- `azure%2FContainer%20Service%20Color%2F` — AKS, Container Registries
- `azure%2FNetworking%20Service%20Color%2F` — Front Door, VNet Gateway, Load Balancer
- `azure%2FSecurity%20Service%20Color%2F` — Key Vaults, Security Center
- `azure%2FDatabases%20Service%20Color%2F` — PostgreSQL, Cosmos DB, SQL
- `azure%2FAI%20and%20ML%20Service%20Color%2F` — Cognitive Services, ML
- `azure%2FStorage%20Service%20Color%2F` — Blob Storage, Storage Accounts
- `azure%2FIdentity%20Service%20Color%2F` — Active Directory, Managed Identities
- `azure%2FDevOps%20Service%20Color%2F` — Azure DevOps, Pipelines
- `azure%2FWeb%20Service%20Color%2F` — App Services, API Management
- `azure%2FOther%20Category%20Service%20Icon%2F` — WAF, etc.

**General icons:**
- `essentials%2F` — Users, documents, general shapes
- `aws%2F` — AWS service icons
- `gcp%2F` — GCP service icons

---

## 4. Classes

Classes bundle icon, shape type, and style into reusable definitions. Define them once at the top, apply everywhere.

```d2
classes: {
  # Icon-only class
  blob: {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FStorage%20Service%20Color%2FBlob%20Storage.svg
  }

  # Styled service class
  ms: {
    style: {
      fill: "#e8f4fd"
      stroke: "#0078D4"
      stroke-width: 2
      border-radius: 6
      font-size: 13
    }
  }

  # Container style class
  region: {
    style: {
      stroke: "#ccc"
      fill: "#f0f5fb"
      stroke-width: 2
      bold: true
    }
  }
}

# Apply classes
storage: Blob Storage {class: blob}
api: API Service {class: ms}
west-us: West US 2 {class: region}
```

**Best practice**: Define 3-5 classes for a diagram — icon-only classes for infrastructure icons, styled rectangle classes for services, container classes for regions/VNets.

---

## 5. Theme System

D2 includes built-in themes. Set via `vars.d2-config.theme-id`:

```d2
vars: {
  d2-config: {
    layout-engine: tala
    theme-id: 0    # Default light theme
  }
}
```

Common theme IDs:
- `0` — Default (light)
- `1` — Neutral grey
- `200` — Dark theme

Themes set base colors for shapes, connections, and text. Your explicit `style` properties override theme defaults.

---

## 6. Glob Patterns for Bulk Styling

Apply styles to multiple shapes at once using glob patterns:

```d2
# Style all shapes at root level
*.style.fill: "#f0f5fb"

# Style all shapes inside a specific container
region.*.style.stroke: "#0078D4"

# Style all connections
(* -> *)[*].style.stroke: "#666"
```

**Use sparingly** — glob styles are powerful but can make diagrams harder to reason about. Prefer classes for most bulk styling.

---

## 7. Label Styling

### Multiline Labels

```d2
# Use \n in quoted strings
gateway: "Virtual Network\nGateway"

# Or use |md for rich text
info: |md
  **Title**: Bold text
  - Bullet 1
  - Bullet 2
|
```

### Connection Labels

```d2
a -> b: HTTPS {
  style.font-size: 11
  style.font-color: "#666"
  style.bold: true
}
```

---

## 8. Transparent Containers (Layout Helpers)

Use invisible containers to group shapes for layout purposes without visual borders:

```d2
# Invisible grouping container
row: {
  direction: right
  style.stroke: transparent
  style.fill: transparent

  item-1: Item 1
  item-2: Item 2
  item-3: Item 3
}
```

This pattern is useful for creating horizontal rows of shapes inside a vertical-flow diagram.
