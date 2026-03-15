# Context Engineering Patterns

## What Context Engineering Means for Planning Artifacts

Context engineering is the practice of structuring information so that AI agents can consume it effectively. Every planning artifact (design doc, working doc, ADR) should be structured enough that an agent reading it understands the system as well as the engineer who wrote it.

The quality of what agents build is directly proportional to the quality of context they receive. Not the process. Not the ceremony. The context.

## The Core Principle

Design docs serve two audiences simultaneously:
1. **Humans** — who need to align on what to build, understand trade-offs, and make decisions
2. **AI agents** — who need structured context to understand the system, generate code, write tests, and debug issues

Both audiences benefit from the same qualities: explicit structure, unambiguous terminology, and complete information. Writing for AI consumption makes docs better for humans too.

## Practices

### 1. Use Explicit Section Headers

AI agents parse section headers to locate information. Use consistent, descriptive headers:

```markdown
<!-- GOOD: Agent can find this section -->
## 5. Detailed Design
### 5.1 Orchestrator Agent
### 5.2 Data Pipeline

<!-- BAD: Agent can't navigate this -->
## How It Works
### The Main Part
### The Other Part
```

### 2. Use Structured Tables Over Prose

Tables are parseable. Prose paragraphs are ambiguous.

```markdown
<!-- GOOD: Agent can extract structured data -->
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `host` | `str` | `"0.0.0.0"` | Server bind address |

<!-- BAD: Agent has to interpret natural language -->
The host field is a string that defaults to 0.0.0.0 and controls
where the server binds, though you might want to change it in production.
```

### 3. Use Mermaid Diagrams

Mermaid is machine-readable. An agent can parse a Mermaid flowchart to understand component relationships, data flow, and system boundaries.

```markdown
\`\`\`mermaid
flowchart TD
    A[User] --> B[Orchestrator]
    B --> C[RAG Agent]
    B --> D[Data Agent]
    C --> E[Search Index]
    D --> F[Database]
\`\`\`
```

Prefer:
- `flowchart TD` for system architecture and data flow
- `C4Context` / `C4Container` for formal system context diagrams
- `erDiagram` for data models
- `stateDiagram-v2` for state machines and lifecycle
- `sequenceDiagram` for request flows

### 4. Define Terminology Explicitly

Never assume the reader (human or AI) knows your acronyms or domain terms.

```markdown
<!-- GOOD: Defined on first use -->
The DGI (Direccion General de Ingresos, Panama's tax authority) portal
returns government-verified invoice data.

<!-- BAD: Assumes knowledge -->
The DGI portal returns verified data.
```

### 5. Make Dependencies Machine-Readable

```markdown
<!-- GOOD: Structured, parseable -->
| Dependency | Impact if Blocked | Owner | Deadline | Status |
|------------|-------------------|-------|----------|--------|
| OAuth federation policy | Genie API calls fail | apabilo | Feb 10 | DONE |

<!-- BAD: Buried in prose -->
We also need the OAuth federation policy from apabilo, ideally by
Feb 10, otherwise the Genie API calls won't work.
```

### 6. Use Consistent Status Labels

Pick a vocabulary and stick to it:
- Status: `DRAFT` | `IN REVIEW` | `APPROVED` | `SUPERSEDED`
- Question status: `OPEN` | `RESOLVED` | `DEFERRED`
- Dependency status: `PENDING` | `DONE` | `BLOCKED`
- Risk level: `LOW` | `MEDIUM` | `HIGH` | `CRITICAL`

### 7. Include Technical Stack Tables

An agent reading a design doc should be able to determine the full technology stack from a single structured table:

```markdown
| Component | Technology | Purpose |
|-----------|------------|---------|
| Chat UI | Chainlit | Multi-turn chat with streaming |
| Auth | Keycloak OIDC | Authentication + role extraction |
| LLM | GPT-4.1 via Azure AI Foundry | Reasoning and response generation |
| Database | PostgreSQL 16 | Config, chat history, token usage |
```

### 8. Cross-Reference with Links

Link between artifacts so agents can navigate the full context graph:

```markdown
See [Design Doc Section 5.2](design-doc.md#52-genie-subagent) for
the Genie integration design.
See [ADR-3](decisions/adr-003.md) for why we chose a single output table.
See [Working Doc](working-doc.md#open-questions) for current blockers.
```

## The Tight Loop: Intent → Build → Observe → Repeat

Traditional planning assumed a linear lifecycle: Requirements → Design → Code → Test → Review → Deploy → Monitor. With AI agents, these stages merge into a tight loop:

1. **Intent**: human describes what to build (the design doc provides this context)
2. **Build**: agent generates code, tests, and deployment artifacts
3. **Observe**: production signals and test results feed back
4. **Repeat**: agent adjusts based on observations

The design doc doesn't disappear in this loop — it becomes the **intent context** that drives step 1. The richer and more structured the design doc, the better the agent performs.

## What Makes a Design Doc Good Context

| Quality | Why It Matters for Agents |
|---------|--------------------------|
| Explicit section headers | Agents parse headers to locate information |
| Structured tables | Parseable, extractable, no ambiguity |
| Mermaid diagrams | Machine-readable architecture representation |
| Defined terminology | No guessing what acronyms mean |
| Non-goals section | Agents know what NOT to build |
| Alternatives with trade-offs | Agents understand why this approach, not another |
| Technical stack table | Agent knows the technologies without inference |
| Cross-references | Agent can navigate the full context graph |

## Anti-Patterns

1. **Prose-heavy design sections** — tables and diagrams are parseable; paragraphs are ambiguous
2. **Undefined acronyms** — agents will guess wrong
3. **Missing non-goals** — agents may build things explicitly out of scope
4. **Inconsistent status labels** — "DONE" vs "COMPLETED" vs "RESOLVED" confuses both humans and agents
5. **No tech stack table** — agents have to infer technologies from scattered mentions
6. **Buried dependencies** — agents can't extract blockers from narrative prose
