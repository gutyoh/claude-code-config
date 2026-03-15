# Core Principles

## 1. The Three-Layer Planning System

Every planning artifact operates on three layers simultaneously. Ignoring any layer produces an incomplete plan.

### Layer 1: Structure

The design doc is the primary artifact. It answers: what should we build, why, and how?

**Required sections**:
- **Context and Scope**: objective background facts. No opinions, no solutions — just the landscape the reader needs to understand. Focus on what's relevant; don't over-explain things the reader already knows.
- **Goals**: a short list of bullet points describing what the system should achieve. Tie goals to business outcomes when possible.
- **Non-Goals**: explicitly deprioritized possibilities. A non-goal is NOT a negated goal ("shouldn't crash"). It is a reasonable thing someone might expect this project to do, but which is explicitly out of scope. Example: "NO client-facing chatbot for Q1 — all users are internal."
- **Detailed Design**: the actual solution with emphasis on trade-offs. Include system-context diagrams, API sketches, data storage approach, and analysis of constraints. Avoid verbose formal specs — sketch the APIs, don't define every field.
- **Alternatives Considered**: rejected designs with focus on their trade-offs versus the selected approach. This is one of the most valuable sections — it shows WHY the chosen solution is better, not just THAT it was chosen.
- **Cross-Cutting Concerns**: security, privacy, observability, and similar organizational priorities. These are often the sections that get the most scrutiny from senior engineers.

**Length guidelines**:
- Major projects: 10-20 pages. If longer, extract reference material to appendices.
- Incremental improvements: 1-3 pages ("mini design docs"). Same sections, proportional detail.

### Layer 2: Operational Tracking

The working doc is the living companion to the design doc. It answers: where are we now?

**Key components**:
- **DRI (Directly Responsible Individual)**: one person who owns the project's execution. Not just the strongest IC — the person who is highly organized and laser-focused on end goals. Being DRI unavoidably adds overhead; the goal is to keep process/paperwork minimal.
- **Plan for Victory**: a list of steps, as concrete as possible, that end with the goal being achieved. Whether you're achieving the plan is the best way to figure out how well or badly things are going. Having a concrete plan is the best antidote to not freaking out soon enough.
- **Open Questions and Risks**: a ranked list of the biggest uncertainties. Resolving these uncertainties drives the project's priority list. If there are more top priorities than you can parallel-path, that's a signal to pull in more people.
- **Staffing**: who's working on what, with their role and time allocation.
- **Weekly Updates**: signal-to-noise optimized broadcasts. "We accomplished Y" not "we worked on X."

### Layer 3: Context Engineering

Every planning artifact is simultaneously context for AI agents. The quality of what agents build is directly proportional to the quality of context they receive.

**Principles**:
- Design docs should be structured enough that an AI agent can read them and understand the system without human interpretation.
- Use explicit section headers, structured tables, and Mermaid diagrams — not prose-heavy narratives.
- Terminology should be unambiguous. Define acronyms on first use. Use consistent names for the same concept.
- The design doc IS the spec. If an agent reads it, it should know: what the system does, how the components connect, what constraints exist, and what decisions were made and why.

---

## 2. When to Use Each Artifact

| Situation | Artifact | Why |
|-----------|----------|-----|
| Starting a new project or major feature | Design Doc | Align the team on what to build, surface risks, get buy-in |
| Tracking a project's operational state | Working Doc | Living doc for staffing, updates, open questions |
| Recording a decision after the fact | ADR | Permanent record — context, decision, alternatives, consequences |
| Proposing a change and soliciting feedback | RFC | Short-lived proposal — accepted or rejected |
| Updating stakeholders on progress | Weekly Update | Signal-to-noise optimized status in the working doc |
| Small change with no real trade-offs | Nothing | Skip the doc. Not everything needs a design doc. |

**When NOT to write a design doc**: Skip for obvious solutions lacking genuine trade-offs, or when rapid prototyping outweighs documentation overhead. If there's only one reasonable approach and no meaningful alternatives, a design doc adds overhead without value.

---

## 3. The OODA Loop

OODA stands for Observe, Orient, Decide, Act. It is the process by which you update plans based on new information.

Most projects are characterized by incomplete information. Getting complete information is usually the hard part — and takes up a substantial fraction of the overall timeline. Information processing, not coding, is the bottleneck.

**Practices**:
- **Spend time on it**: running OODA loops is time-intensive. For critical projects, the DRI should spend dedicated time daily checking statuses, contemplating priorities, and broadcasting updates.
- **Communicate frequently**: reduce round-trip time on information. Multiple check-ins per day for critical projects.
- **Track and prioritize open questions**: the biggest uncertainties become the priority list. Ideally, parallel-path work on multiple top uncertainties.
- **Reorient frequently**: review priorities multiple times a day during critical phases. Ask: are we still working on the right things?
- **Sound the alarm early**: the plan exists to detect when things go off-track. If reality diverges from the plan, escalate immediately — don't wait.

---

## 4. Overcommunication

Everyone on the project needs ambient awareness of:
- What else is going on around them (so they can coordinate and update quickly)
- How their goal fits into the overall project (so they can make correct local decisions)

**Weekly update rules**:
- State the overall vibe (on track, behind, blocked)
- What changed since last update
- What's coming up next
- Optimize for signal-to-noise — err towards concision
- No "we worked on X" — say "we accomplished Y" or "we learned Z"
- State things concretely: "X improves eval Y by Z points" not "we got X working"
- Leave out anything that's not actionable
- Remember the audience is people not deeply familiar with the project

---

## 5. Breaking Off Subprojects

Once a project exceeds ~10 people, delegate project management, not just execution.

**Delegation principles**:
- The ideal unit of delegation is a crisp, simple, high-level goal with limited overlap with other workstreams. Good: "get identical evals between implementations A and B." Bad: "follow this 10-step checklist."
- The best sub-DRIs are highly organized and laser-focused on end goals, not necessarily the strongest ICs.
- People running subprojects take a substantial hit to IC productivity — this is expected and worth it. Direction is more important than magnitude.
- Keep goals simple enough to fit in a short message while still crisply describing the desired end state.

---

## 6. Scaling from Startup to Enterprise

The same principles apply at every scale. The weight changes.

| Aspect | Startup / Small Team | Enterprise / Large Team |
|--------|---------------------|------------------------|
| Design doc length | 1-3 pages | 10-20 pages |
| OODA frequency | Daily or faster | Weekly with async updates |
| Approvers | 1-2 senior engineers | Formal review with senior staff |
| Cross-cutting concerns | Lightweight (security basics) | Detailed (security, privacy, compliance, observability) |
| Dependencies | Few, mostly internal | Many, often cross-team or cross-org |
| Working doc | Optional (small enough to track in heads) | Essential (too many moving parts) |
| ADRs | Embedded in design doc | Standalone files in a decision log |
| Timeline | Weeks | Months with sprint-level milestones |
| Ceremony | Minimal — just write the doc and share it | Review meetings, approval gates, stakeholder sign-off |

---

## 7. Anti-Patterns

1. **No non-goals section** — without explicit non-goals, scope creeps silently. Someone will assume a reasonable feature is in scope because it wasn't called out.
2. **Alternatives Considered is empty or perfunctory** — "we considered X but rejected it" without explaining the trade-offs. This is the most valuable section for future engineers.
3. **Design doc is also the project tracker** — the design doc should be stable after approval. Operational state (who's doing what, what's blocked) belongs in the working doc.
4. **No plan for victory** — without concrete steps ending with the goal achieved, you can't detect when things go off-track.
5. **Open questions not ranked** — a flat list of questions doesn't drive prioritization. Rank by impact and urgency.
6. **Writing the design doc after building** — the design doc should be written and reviewed BEFORE implementation. Post-hoc documentation is explanation, not planning.
7. **Over-documenting small changes** — not everything needs a design doc. If there's one obvious approach, just build it.
8. **Prose-heavy design sections** — use tables, diagrams, and structured formats. Prose is hard for humans to scan and impossible for AI agents to parse reliably.
9. **Weekly updates that describe activity, not outcomes** — "we worked on the auth module" tells the reader nothing. "Auth module now passes all 47 integration tests" tells them everything.
10. **Not sounding the alarm early enough** — the most common megaproject failure mode. The plan exists to detect divergence. Use it.
