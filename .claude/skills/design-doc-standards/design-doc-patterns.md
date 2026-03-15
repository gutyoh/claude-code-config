# Design Doc Patterns

## When to Write a Design Doc

Write a design doc when:
- Starting a new project or major feature
- Making a decision with genuine trade-offs (multiple reasonable approaches)
- The work involves multiple people or teams
- The work has dependencies on external systems or teams
- Someone will need to understand WHY this was built this way in 6 months

Do NOT write a design doc when:
- There's one obvious approach with no meaningful alternatives
- The change is small enough to explain in a PR description
- Rapid prototyping will answer the open questions faster than planning

## Structure Template

### Major Project (10-20 pages)

```markdown
# [Project Name] — Design Doc

> **Status:** DRAFT | IN REVIEW | APPROVED | SUPERSEDED
> **Author:** [Name]
> **Created:** [Date]
> **Last Updated:** [Date]
> **Approvers:** [Name (Role), Name (Role)]

---

## 1. Context and Scope

[Objective background facts. What exists today, what problem exists,
what constraints are in play. No opinions, no solutions — just the landscape.]

---

## 2. Goals

- [Goal 1 — tied to business outcome when possible]
- [Goal 2]
- [Goal 3]

---

## 3. Non-Goals

- **NO [reasonable thing someone might expect]** — [why it's out of scope]. [When it might happen].
- **NO [another reasonable expectation]** — [reason].

---

## 4. Overview

[High-level description of the solution. 2-3 paragraphs + a system context diagram.
This is where most readers decide whether to keep reading.]

\`\`\`mermaid
C4Context
    title System Context Diagram
    Person(user, "User", "Description")
    System(system, "System Name", "What it does")
    System_Ext(ext, "External System", "Description")
    Rel(user, system, "Uses")
    Rel(system, ext, "Integrates with")
\`\`\`

---

## 5. Detailed Design

### 5.1 [Component / Subsystem]

[How it works, with emphasis on trade-offs. Include:]
- System-context diagrams
- API sketches (not verbose formal specs)
- Data storage approach (schema concepts, not complete definitions)
- Key algorithms or processing flows

### 5.2 [Component / Subsystem]

[Continue for each major component]

### 5.N Data Flow (End-to-End)

[A diagram showing how data flows through the entire system]

---

## 6. Alternatives Considered

| Decision | Alternative | Why Rejected |
|----------|-------------|--------------|
| [What was decided] | [What was considered] | [Trade-off analysis — not just "it was worse"] |

---

## 7. Cross-Cutting Concerns

### Security

| Concern | Mitigation |
|---------|-----------|
| [Threat] | [How it's addressed] |

### Privacy

| Concern | Mitigation |
|---------|-----------|
| [Data type] | [How it's protected] |

### Observability

| Component | Approach |
|-----------|---------|
| [What to monitor] | [How] |

---

## 8. Success Metrics

| KPI | Target | How to Measure |
|-----|--------|----------------|
| [Metric] | [Target value] | [Measurement method] |

---

## 9. Dependencies

| Dependency | Impact if Blocked | Mitigation | Deadline | Owner |
|------------|-------------------|-----------|----------|-------|
| [External dependency] | [What breaks] | [Fallback plan] | [Date] | [Person] |

---

## 10. Timeline

| Milestone | Date | Description |
|-----------|------|-------------|
| [Milestone 1] | [Date] | [What's delivered] |

---

## 11. Open Questions

| # | Question | Impact | Owner | Status |
|---|----------|--------|-------|--------|
| 1 | [Uncertainty] | [What it affects] | [Who resolves it] | OPEN / RESOLVED |

---

## 12. Deferred to Next Phase

| Item | Why Deferred | Earliest Phase |
|------|-------------|----------------|
| [Feature] | [Reason] | [When] |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | [Date] | [Author] | Initial design doc |
```

### Mini Design Doc (1-3 pages)

Same sections, compressed. Drop Dependencies, Timeline, and Document History. Keep Context, Goals, Non-Goals, Design, Alternatives, and Cross-Cutting Concerns.

```markdown
# [Feature] — Mini Design Doc

> **Status:** DRAFT
> **Author:** [Name]
> **Date:** [Date]

## Context

[2-3 sentences of background]

## Goals / Non-Goals

**Goals:** [bullet list]
**Non-Goals:** [bullet list]

## Design

[The solution — 1-2 paragraphs + diagram if helpful]

## Alternatives

| Option | Trade-off |
|--------|-----------|
| [Chosen approach] | [Why it wins] |
| [Rejected approach] | [Why it loses] |

## Cross-Cutting

[Security/privacy/observability in 2-3 bullets]
```

## Rules for Each Section

### Context and Scope

- Objective facts only — no opinions, no solutions
- Describe what exists today, not what you want to build
- Include enough for a new team member to understand the landscape
- Do not over-explain things the audience already knows

### Goals

- Bullet points, not paragraphs
- Tied to business outcomes when possible
- Specific enough to verify: "12 business questions answerable" not "users can ask questions"

### Non-Goals

- NOT negated goals ("shouldn't crash" is not a non-goal)
- Reasonable things someone might expect to be in scope
- Include WHEN it might happen: "Deferred to Q2" is more useful than just "out of scope"
- Each non-goal prevents scope creep on a specific front

### Detailed Design

- Lead with a high-level overview, then drill into components
- Emphasize trade-offs, not just the solution
- Include diagrams — system context, data flow, sequence diagrams
- API sketches, not formal specs — show the shape, not every field
- Minimal code — only for novel algorithms or critical logic

### Alternatives Considered

- This section gets the most scrutiny from senior engineers
- Every alternative must include WHY it was rejected — trade-off analysis, not just "it was worse"
- Table format works well for quick comparison
- Include the trade-offs of the CHOSEN approach too — nothing is free

### Cross-Cutting Concerns

- Security: authentication, authorization, data access, injection risks
- Privacy: PII handling, data retention, compliance
- Observability: logging, metrics, tracing, alerting
- Include other organizational priorities as needed (cost, reliability, compliance)

## Common Mistakes

1. **Writing the design doc after building** — the doc should drive the implementation, not describe it retroactively
2. **No non-goals** — scope will creep without explicit boundaries
3. **Perfunctory alternatives** — "we considered X but rejected it" without trade-off analysis
4. **Too much detail in the design section** — sketch APIs, don't define every field. Formal specs belong in reference docs.
5. **Missing diagrams** — a system context diagram is worth 1000 words of prose
6. **Status never updated** — DRAFT → IN REVIEW → APPROVED should be tracked
7. **No document history** — for major design docs, track what changed between versions
