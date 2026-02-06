# Layout Patterns (TALA-Specific)

TALA is a proprietary layout engine by Terrastruct that produces superior results for software architecture diagrams. These patterns document TALA-specific behaviors from the TALA User Manual.

---

## 1. Symmetry

TALA weights symmetry heavily in its layout algorithm. When shapes have similar connection patterns, TALA places them symmetrically.

```d2
# TALA will arrange service-a, service-b, service-c symmetrically around the load-balancer
lb: Load Balancer
service-a: Service A
service-b: Service B
service-c: Service C

lb -> service-a
lb -> service-b
lb -> service-c
```

**Tip**: If you want symmetric placement, give shapes similar connection structures. TALA detects and enforces symmetry automatically.

---

## 2. Clusters

TALA groups sibling shapes with similar connection patterns into visual clusters, even without explicit containers.

```d2
# TALA will cluster the databases together and the services together
api: API
db-1: PostgreSQL
db-2: Redis
db-3: MongoDB
svc-1: Auth Service
svc-2: User Service

api -> svc-1
api -> svc-2
svc-1 -> db-1
svc-1 -> db-2
svc-2 -> db-1
svc-2 -> db-3
```

---

## 3. Hierarchy

TALA supports multi-level hierarchy. Shapes at different levels of a hierarchy are placed at different vertical positions.

```d2
# Multi-level hierarchy with containers
org: Organization {
  team-a: Team A {
    service-1: Service 1
    service-2: Service 2
  }
  team-b: Team B {
    service-3: Service 3
  }
}
```

### Hierarchy Shape

The special `shape: hierarchy` renders org-chart style trees:

```d2
tree: {
  shape: hierarchy
  ceo: CEO
  cto: CTO
  cfo: CFO
  eng: Engineering
  fin: Finance

  ceo -> cto
  ceo -> cfo
  cto -> eng
  cfo -> fin
}
```

---

## 4. Direction (Per-Container)

Direction controls the primary flow axis within a container. TALA treats direction as a **suggestion** — it may deviate for better overall layout.

```d2
direction: down  # Root level: top-to-bottom

pipeline: CI/CD Pipeline {
  direction: right  # This container flows left-to-right
  build: Build
  test: Test
  deploy: Deploy
  build -> test -> deploy
}

monitoring: Monitoring {
  direction: down  # This container flows top-to-bottom
  prometheus: Prometheus
  grafana: Grafana
  alertmanager: Alertmanager
  prometheus -> grafana
  prometheus -> alertmanager
}
```

Valid directions: `up`, `down`, `left`, `right`

Default: `down` (with right-leaning bias)

**Key insight**: Unlike dagre/ELK which enforce direction strictly, TALA uses direction as one of many inputs to its optimization. This produces more natural-looking layouts but means you cannot force exact positioning with direction alone — use `top:`/`left:` pixel values for precise control.

---

## 5. Near Positioning

`near` attaches a shape to a constant position or near another shape. Used for legends, labels, annotations.

### Near Constants

```d2
legend: |md
  **Legend**
  - Blue: HTTP traffic
  - Green: AI services
| {
  near: bottom-right
  style.font-size: 11
  style.fill: "#f9f9f9"
  style.stroke: "#ddd"
}
```

Available constants:
- `top-left`, `top-center`, `top-right`
- `center-left`, `center-right`
- `bottom-left`, `bottom-center`, `bottom-right`

### Near Another Shape

```d2
server: Web Server
annotation: "High availability\nzone" {
  near: server
  style.font-size: 10
  style.fill: "#ffffcc"
}
```

When using `near` with another shape, the annotation is placed close to the target shape. The target must be referenced by its **absolute ID** (fully qualified from root).

---

## 6. Pixel Positioning (top/left)

For precise placement, use `top:` and `left:` pixel values. Values are relative to the parent container.

```d2
region: Region {
  # Position a shape at exact coordinates within the container
  db: Database {
    top: 200
    left: 50
  }
}
```

**Use sparingly** — pixel positioning defeats the purpose of automatic layout. Reserve it for cases where TALA's automatic placement isn't sufficient.

---

## 7. Dimensions (width/height)

Set explicit dimensions on shapes that need more space for connections.

```d2
# Hub node with many connections — make it larger
api-gateway: API Gateway {
  width: 200
  height: 80
}
```

TALA's **port space scaling** automatically increases node size when many connections attach, but explicit dimensions give you direct control.

---

## 8. Seed System

TALA uses a randomized optimization algorithm. Different seeds produce different layouts. By default, TALA tries seeds 1, 2, and 3, picking the best result.

```bash
# Default behavior (tries seeds 1,2,3)
d2 --layout tala diagram.d2 output.svg

# Custom seeds — try more for potentially better layouts
d2 --layout tala --tala-seeds 1,2,3,42,99,999 diagram.d2 output.svg

# Single specific seed for reproducibility
d2 --layout tala --tala-seeds 42 diagram.d2 output.svg
```

**When to re-roll seeds**:
- Overlapping labels or connections
- Asymmetric placement that should be symmetric
- Suboptimal edge routing (connections crossing unnecessarily)
- Shapes placed far from their container siblings

**Tip**: Try 5-10 seeds first. If none produce a good layout, the issue is likely in the diagram structure (too many connections, deep nesting), not the seed.

---

## 9. Balanced Connections (Port Targeting)

TALA distributes connection ports along shape edges at 1/3 intervals rather than center-to-center. This produces cleaner parallel connections.

```d2
# Three connections from the same source — TALA spreads them across the edge
lb: Load Balancer
s1: Service 1
s2: Service 2
s3: Service 3

lb -> s1
lb -> s2
lb -> s3
# Ports will be at ~1/3, ~1/2, and ~2/3 of the edge rather than all from center
```

---

## 10. Self Connections

TALA reserves corner space for self-connections (loops). Each connection type (directed, bidirectional) gets its own corner.

```d2
service: Service {
  # Self-loop
}
service -> service: retry
```

---

## 11. Edge Routing

TALA has its own edge router that avoids obstacles and maintains clean paths. Key differences from dagre/ELK:

- Routes around shapes and containers (not through them)
- Maintains consistent spacing between parallel edges
- Prefers horizontal routing when 3+ connections share a labeled edge
- Uses orthogonal routing (right angles) by default

---

## 12. Square Aspect Ratio

For non-connected subgraphs (disconnected components), TALA uses bin-packing with a near-square aspect ratio. This produces compact, balanced layouts when you have multiple independent diagrams in one file.

---

## 13. Dynamic Label Positioning

TALA automatically positions connection labels to avoid overlapping with shapes and other labels. Labels are placed along the edge at the position with least obstruction.
