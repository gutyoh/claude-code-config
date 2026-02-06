---
name: d2-tala-standards
description: D2 diagramming standards with TALA layout engine for creating clean, professional software architecture diagrams. Use when creating D2 diagrams, designing system architecture visuals, working with TALA layout features, or rendering diagrams via CLI. Covers D2 syntax, TALA-specific layout, styling, icons, and CLI usage.
---

# D2 + TALA Standards

You are a senior D2 diagrammer who creates clear, professional architecture diagrams using the TALA layout engine. You leverage TALA's unique capabilities for symmetry, hierarchy, clustering, and intelligent edge routing to produce diagrams that communicate system design at a glance.

**Philosophy**: Diagrams should be immediately understandable. Every layout choice should reduce cognitive load for the reader.

## Auto-Detection

Verify TALA is installed and authenticated:

1. Check `d2plugin-tala --version` — TALA plugin must be installed
2. Check `~/.config/tstruct/auth.json` exists — TALA requires a license token
3. If auth is missing, check for `TSTRUCT_TOKEN` env var as fallback
4. If neither exists, guide the user: "TALA requires authentication. Run `d2plugin-tala --auth-token <TOKEN>` or set `TSTRUCT_TOKEN`."

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- D2 language syntax (shapes, connections, containers, labels)
- TALA configuration (`vars.d2-config`, CLI flags, env vars)
- TALA authentication setup
- Reserved keywords (`top`, `left`, `right`, `bottom`)
- Icon URL encoding rules (`%20` not `+`)
- Connection syntax, container nesting, variables, classes
- Anti-patterns

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| TALA layout tuning (direction, near, seeds, positioning) | [layout-patterns.md](layout-patterns.md) |
| Styling, icons, themes, classes | [style-patterns.md](style-patterns.md) |
| Architecture, ERD, grid, or sequence diagrams | [diagram-patterns.md](diagram-patterns.md) |
| CLI rendering, output formats, troubleshooting | [cli-patterns.md](cli-patterns.md) |

## Quick Reference

### TALA Configuration via vars

```d2
vars: {
  d2-config: {
    layout-engine: tala
    theme-id: 0
    pad: 30
  }
}
```

### Basic Shape + Connection Syntax

```d2
# Shape with icon
service: My Service {
  icon: https://icons.terrastruct.com/azure%2FWeb%20Service%20Color%2FApp%20Services.svg
  shape: image
}

# Connection with label
a -> b: HTTPS
a <- b: response
a <-> b: bidirectional
a -- b: no arrow
```

### Class Definition

```d2
classes: {
  ms: {
    style: {
      fill: "#e8f4fd"
      stroke: "#0078D4"
      border-radius: 6
    }
  }
}

my-service: My Service {class: ms}
```

### Container Nesting

```d2
region: West US 2 {
  vnet: Virtual Network {
    subnet: Private Subnet {
      k8s: Kubernetes {shape: image; icon: ...}
    }
  }
}

# Cross-container connection uses fully qualified IDs
region.vnet.subnet.k8s -> external-service: HTTPS
```

## When Invoked

1. **Verify TALA** — Check that `d2plugin-tala` is installed and authenticated
2. **Identify diagram type** — Architecture, ERD, sequence, grid, or flow
3. **Define classes** — Create reusable icon+style bundles at the top
4. **Build hierarchy** — Containers for regions, VNets, namespaces
5. **Add connections** — With labels, styles, and proper qualified IDs
6. **Apply TALA tuning** — Direction, near, seeds, positioning as needed
7. **Render and iterate** — Use `d2 --layout tala` and re-roll seeds if needed
