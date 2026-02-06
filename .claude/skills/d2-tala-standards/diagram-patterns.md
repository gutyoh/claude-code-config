# Diagram Patterns

## 1. Software Architecture (Primary TALA Use Case)

Architecture diagrams are TALA's strength. The typical pattern involves cloud regions, VNets, subnets, and services.

### Azure Cloud Architecture Pattern

```d2
direction: down

vars: {
  d2-config: {
    layout-engine: tala
    theme-id: 0
    pad: 30
  }
}

classes: {
  svc-icon: {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FWeb%20Service%20Color%2FApp%20Services.svg
  }
  k8s-icon: {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FContainer%20Service%20Color%2FKubernetes%20Services.svg
  }
  db-icon: {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FDatabases%20Service%20Color%2FAzure%20Database%20for%20PostgreSQL%20servers.svg
  }
  ms: {
    style: {
      fill: "#e8f4fd"
      stroke: "#0078D4"
      stroke-width: 2
      border-radius: 6
      font-size: 13
    }
  }
}

# External entry point
users: Users {shape: person; style.fill: "#0078D4"}
front-door: Front Door {
  shape: image
  icon: https://icons.terrastruct.com/azure%2FNetworking%20Service%20Color%2FFront%20Doors.svg
}

users -> front-door: HTTPS

# Region container
region: West US 2 {
  style.stroke: "#ccc"
  style.fill: "#f0f5fb"
  style.stroke-width: 2

  entra: Entra ID {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FIdentity%20Service%20Color%2FActive%20Directory.svg
  }

  vnet: Virtual Network {
    style.stroke: "#0078D4"
    style.fill: "#eaf1fb"

    subnet: Private Subnet {
      style.stroke: "#999"
      style.stroke-dash: 4
      style.fill: "#f7f9fc"

      k8s: Kubernetes {class: k8s-icon}
      service-a: Service A {class: ms}
      service-b: Service B {class: ms}
    }

    db: PostgreSQL {class: db-icon}
  }
}

front-door -> region.entra
region.entra -> region.vnet.subnet.k8s
region.vnet.subnet.service-a -> region.vnet.db
```

### Key Architecture Patterns

**Region containers**: Use visible borders with muted fill colors. Each cloud region gets its own container.

**VNet nesting**: Region > VNet > Subnet is the standard hierarchy. Keep it at 3 levels when possible.

**Microservice namespaces**: Group related services in a namespace container inside the subnet.

**Cross-container connections**: Always use fully qualified IDs: `region.vnet.subnet.service-a -> region.vnet.db`

**External entry flow**: Users -> Front Door/CDN -> WAF -> Entra/Auth -> Ingress -> Services

---

## 2. CI/CD Pipeline Diagrams

Use `direction: right` for horizontal pipeline flows.

```d2
pipeline: CI/CD {
  direction: right
  style.stroke: transparent
  style.fill: transparent

  developer: Developer {shape: person}
  devops: Azure DevOps {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FDevOps%20Service%20Color%2FAzure%20DevOps.svg
  }
  pipelines: Pipelines {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FDevOps%20Service%20Color%2FAzure%20Pipelines.svg
  }
  registry: Container Registry {
    shape: image
    icon: https://icons.terrastruct.com/azure%2FContainer%20Service%20Color%2FContainer%20Registries.svg
  }

  developer -> devops: Push
  devops -> pipelines: Trigger
  pipelines -> registry: Build & Push
}

# Connect CI/CD to the infrastructure
pipeline.registry -> region.vnet.subnet.k8s: Pull {style.stroke-dash: 3}
```

---

## 3. Grid Diagrams

Grids arrange shapes in a fixed row/column layout. Useful for dashboards, comparison tables, and service catalogs.

```d2
services: Microservices {
  grid-columns: 3
  grid-gap: 8
  style.stroke: "#0078D4"
  style.fill: "#fff"

  auth: Auth Service {class: ms}
  users: User Service {class: ms}
  billing: Billing Service {class: ms}
  orders: Order Service {class: ms}
  inventory: Inventory Service {class: ms}
  notifications: Notification Service {class: ms}
}
```

### Grid Properties

| Property | Description |
|----------|-------------|
| `grid-columns` | Number of columns (shapes wrap to next row) |
| `grid-rows` | Number of rows (shapes wrap to next column) |
| `grid-gap` | Spacing between grid cells in pixels |

**Tip**: Use transparent spacer shapes to control grid placement:

```d2
grid: {
  grid-columns: 3
  a: Shape A
  b: Shape B
  _spacer: "" {style.stroke: transparent; style.fill: transparent}
  c: Shape C
}
```

---

## 4. SQL Table / ERD Diagrams

Use `shape: sql_table` for database entity diagrams. TALA aligns tables and routes connections between matching columns.

```d2
users: users {
  shape: sql_table
  id: int {constraint: primary_key}
  name: varchar(255)
  email: varchar(255) {constraint: unique}
  created_at: timestamp
}

orders: orders {
  shape: sql_table
  id: int {constraint: primary_key}
  user_id: int {constraint: foreign_key}
  total: decimal(10,2)
  status: varchar(50)
  created_at: timestamp
}

# Connection from column to column
users.id -> orders.user_id
```

### ERD Conventions

- Use snake_case for table and column names
- Mark constraints: `primary_key`, `foreign_key`, `unique`
- TALA's column matching aligns foreign key connections to the correct column edge

---

## 5. Sequence Diagrams

Use `shape: sequence_diagram` for UML-style interaction diagrams.

```d2
auth-flow: Authentication {
  shape: sequence_diagram

  client: Client
  gateway: API Gateway
  auth: Auth Service
  db: Database

  client -> gateway: POST /login
  gateway -> auth: Validate credentials
  auth -> db: Query user
  db -> auth: User record
  auth -> gateway: JWT token
  gateway -> client: 200 OK + token
}
```

Sequence diagrams are self-contained — TALA handles their internal layout automatically. They can be placed alongside other shapes in the same file.

---

## 6. Legends

Use `near` positioning with markdown labels for diagram legends.

```d2
legend: |md
  **Legend**
  - Blue: HTTP traffic
  - Green: AI/ML services
  - Orange: File storage
  - Purple: Replication
  - Dashed: Async / managed identity
| {
  near: bottom-right
  style: {
    font-size: 11
    fill: "#f9f9f9"
    stroke: "#ddd"
    border-radius: 4
  }
}
```

### Legend with Dimensions

For precise legend sizing:

```d2
legend: |md
  **Connection Types**
  - Solid blue: Synchronous HTTP
  - Dashed grey: Async messaging
| {
  near: bottom-right
  width: 250
  height: 80
  style.font-size: 11
}
```

---

## 7. Step Shapes (Pipeline Flows)

Step shapes (`shape: step`) render as arrow-shaped boxes that connect tail-to-head, ideal for pipeline flows.

```d2
extract: Extract {shape: step}
transform: Transform {shape: step}
load: Load {shape: step}

extract -> transform -> load
```

Steps arranged in sequence create a visual pipeline effect. TALA aligns them naturally in the `direction` of the container.

---

## 8. On-Premises Connectivity

Pattern for showing on-prem to cloud connections:

```d2
# On-prem resources (outside cloud regions)
fileshare: "M:/Department1/\nCOMPANY_AZURE/" {
  shape: image
  icon: https://icons.terrastruct.com/azure%2FStorage%20Service%20Color%2FStorage%20Accounts.svg
}

# Connection via VPN/Gateway
fileshare -> region.vnet-gateway: IPSEC VPN {
  style.stroke: "#FF9800"
  style.stroke-dash: 5
}
```

---

## 9. Multi-Region Diagrams

Show failover and replication between regions:

```d2
primary: West US 2 {
  style.stroke: "#ccc"
  style.fill: "#f0f5fb"
  db: PostgreSQL {class: db-icon}
}

secondary: WestCentral US {
  style.stroke: "#ccc"
  style.fill: "#f0f5fb"
  db-replica: "PostgreSQL\nReplica" {class: db-icon}
}

primary.db -> secondary.db-replica: Replication {
  style.stroke: "#9C27B0"
  style.stroke-dash: 5
}
```
