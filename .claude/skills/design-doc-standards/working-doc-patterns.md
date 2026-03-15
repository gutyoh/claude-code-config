# Working Doc Patterns

## What a Working Doc Is

The working doc is the **living operational tracker** for a project. It is the single "landing page" where anyone can find the most important information about the project's current state. Unlike a design doc (which is reviewed, approved, and becomes historical), the working doc is continuously updated throughout the project's lifetime.

A working doc is NOT a design doc. The design doc answers "what should we build and why?" The working doc answers "where are we now?"

## When to Create a Working Doc

- Any project with 3+ people
- Any project lasting more than 2 weeks
- Any project with external dependencies or stakeholders
- When the DRI needs to track operational state beyond what fits in their head

For solo projects under 2 weeks, a working doc is optional — the design doc may be sufficient.

## Structure Template

```markdown
# [Project Name] — Working Doc

**DRI:** [Name]
**Slack channel:** #[channel-name]
**Design doc:** [link to design doc]
**Status:** ON TRACK | AT RISK | BLOCKED

---

## Goal

[One sentence: the crisp, simple, high-level goal. If it can't fit in a
Slack message, it's not simple enough.]

---

## Plan for Victory

[Concrete steps ending with the goal achieved. Ranked. Updated as reality changes.]

- [ ] Step 1: [action] — **Owner:** [name] — **Target:** [date]
- [ ] Step 2: [action] — **Owner:** [name] — **Target:** [date]
- [x] Step 3: [completed action] — **Done:** [date]

---

## Open Questions / Risks

[Ranked by impact. The biggest uncertainties drive the priority list.]

| # | Question | Impact | Owner | Status |
|---|----------|--------|-------|--------|
| 1 | [Highest-impact uncertainty] | [What it blocks] | [Name] | OPEN |
| 2 | [Next uncertainty] | [What it affects] | [Name] | RESOLVED — [answer] |

---

## Who's Working on What

| Person | Role | Current Focus | Allocation |
|--------|------|--------------|------------|
| [Name] | DRI | [What they're doing this week] | [% time] |
| [Name] | [Role] | [Current task] | [% time] |

---

## Key Links

- Design doc: [link]
- Slack channel: [link]
- Repo: [link]
- Dashboard: [link]
- CI/CD pipeline: [link]

---

## Weekly Updates

### Week of [Date]

**Vibe:** ON TRACK | AT RISK | BLOCKED

**Accomplished:**
- [Outcome, not activity]
- [Concrete result]

**Learned:**
- [New information that changes the plan]

**Coming up:**
- [Next priorities]

**Blockers:**
- [What's stuck and who can unblock it]

---

### Week of [Previous Date]

[Previous update]
```

## Rules

### The Goal Must Be Crisp

The top-level goal should be simple enough to fit in a Slack message. If it can't, it's not clear enough. Good: "Launch multi-agent orchestrator with Genie + RAG + RBAC by March 31." Bad: "Improve the chatbot platform with multiple enhancements across various dimensions."

People running subprojects need a goal crisp enough to prioritize autonomously — if the goal is vague, they'll work on the wrong things.

### Plan for Victory Is the Core

The plan for victory is a list of steps, as concrete as possible, that end with the goal being achieved. It serves two critical purposes:

1. **Detecting divergence** — if you're not achieving the plan, things are going badly. The plan is the earliest warning system.
2. **Driving prioritization** — the next incomplete step is the current priority.

Update the plan when reality changes. Add steps discovered during execution. Remove steps that turn out to be unnecessary. The plan is a living tool, not a commitment.

### Open Questions Drive Priorities

The ranked list of open questions IS the priority list. Resolving uncertainties is usually the bottleneck — not writing code.

- Rank by impact: what does this block if unresolved?
- Parallel-path when possible: if you have enough people, work on multiple top questions simultaneously
- When a question is resolved, record the answer inline — don't just mark it "resolved"
- If there are more top priorities than you can parallel-path, that's a signal to pull in more people

### Weekly Updates Are Signal, Not Noise

The update should take 15-30 minutes to write. If it takes longer, you're including too much.

**Good update items:**
- "Auth module passes all 47 integration tests"
- "Discovered federation policy requires admin approval — new blocker"
- "Reduced cold start latency from 65s to 30s by adding warm-up job"

**Bad update items:**
- "Worked on the auth module"
- "Had meetings about the architecture"
- "Continued implementation"

### DRI Responsibilities

The DRI is not just the person who writes the working doc. They:

1. **Focus** — clear their schedule enough to make the project a top priority
2. **Run the OODA loop** — check statuses, contemplate priorities, reorient
3. **Overcommunicate** — broadcast updates to people who need ambient awareness
4. **Escalate early** — sound the alarm when reality diverges from the plan
5. **Delegate subprojects** — break off crisp goals for sub-DRIs when the project exceeds ~10 people

## Working Doc vs. Other Artifacts

| Need | Use |
|------|-----|
| What to build and why | Design Doc |
| Where are we now | **Working Doc** |
| Why was this specific decision made | ADR |
| Status update for stakeholders | Weekly Update (in Working Doc) |
| Retrospective on what went well / could improve | Retro notes (append to Working Doc) |

## Retrospectives

Every 2-4 weeks (more often for fast-moving projects), step back and ask: "How could the last N weeks have gone better?"

**Format (30 minutes):**
1. [13 min] Async brainstorm: "what went well" / "what we could improve"
2. [2 min] Dedupe and emoji-vote on items
3. [10 min] Synchronous discussion of top-voted items
4. [5 min] Action items

Append retro notes to the working doc's weekly updates section.
