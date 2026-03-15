# ADR Patterns

## What an ADR Is

An Architecture Decision Record (ADR) is a short document that captures a single decision, its context, and its consequences. ADRs are permanent records — once written, they are never updated (if a decision is reversed, write a new ADR that supersedes the old one).

## When to Write an ADR

**Embedded in a design doc**: When you're writing a design doc and the Alternatives Considered section contains major decisions, each alternative IS an embedded ADR.

**Standalone ADR file**: When a decision is made AFTER the design doc is approved, or when no design doc exists for the project.

**Do NOT write an ADR for**:
- Trivial decisions with no meaningful alternatives
- Temporary decisions that will be revisited next sprint
- Implementation details that don't affect architecture

## ADR Format

```markdown
## ADR-[N]: [Decision Title]

### Context

[The situation and constraints that motivated the decision.
What forces are at play? What problem needs solving?
Objective facts only — no opinions yet.]

### Decision

[What was decided and how it works.
Specific enough that someone could implement it.]

### Alternatives Considered

- **[Alternative 1]**: [How it works]. [Why it was rejected — trade-off analysis].
- **[Alternative 2]**: [How it works]. [Why it was rejected — trade-off analysis].

### Consequences

[What follows from this decision — BOTH benefits AND trade-offs.
Every decision has costs. Acknowledging them builds trust and helps
future engineers understand the full picture.]
```

## Rules

### Context Is Objective

The Context section describes the situation, not the solution. It should contain only facts and constraints. A reader should be able to understand the context without knowing the decision.

### Alternatives Must Include Trade-Off Analysis

"We considered X but rejected it" is not useful. Every alternative must explain:
- What the alternative would look like
- What trade-offs it presents versus the chosen approach
- Why those trade-offs make it the worse choice for THIS situation

### Consequences Include Costs

Every decision has trade-offs. The Consequences section must include:
- Benefits (why this decision is good)
- Costs / trade-offs (what you give up)
- Risks (what could go wrong)

Omitting costs makes the ADR look like advocacy, not analysis.

### ADRs Are Numbered

Use sequential numbering: ADR-1, ADR-2, etc. This makes cross-referencing easy and provides a chronological record of decisions.

### ADRs Are Immutable

Never edit an existing ADR. If a decision is reversed:
1. Write a new ADR with the new decision
2. Reference the old ADR: "Supersedes ADR-3"
3. Mark the old ADR: "Superseded by ADR-7"

This preserves the full history of how thinking evolved.

## Embedded vs. Standalone ADRs

### Embedded (in design doc)

When writing a design doc, the Alternatives Considered section naturally contains ADRs. Each row in the alternatives table IS a decision record. For design docs, this is sufficient — no separate files needed.

### Standalone (post-design-doc decisions)

For decisions made after the design doc is approved, create standalone ADR files:

```
docs/
├── design-doc.md
└── decisions/
    ├── adr-001-use-genie-over-direct-sql.md
    ├── adr-002-replace-role-config-with-acl-discovery.md
    └── adr-003-single-denormalized-output-table.md
```

## Common Mistakes

1. **No alternatives** — an ADR without alternatives is not a decision record, it's a description
2. **No trade-offs in consequences** — if there are no costs, you haven't thought hard enough
3. **Editing old ADRs** — write a new one that supersedes the old one
4. **Too many ADRs** — only record decisions that affect architecture or have meaningful alternatives
5. **Mixing context with decision** — context is the problem; decision is the solution. Keep them separate.
