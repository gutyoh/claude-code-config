# Review Patterns

## How to Review a Design Doc

### Before the Review

Read the entire design doc. Do not skim. Form opinions about:
1. Is the problem statement clear?
2. Do the goals make sense?
3. Are the non-goals actually reasonable deprioritizations?
4. Does the design address the stated goals?
5. Are the alternatives genuinely considered, or perfunctory?

### Review Checklist

**Structure**:
- [ ] Context describes the landscape without proposing solutions
- [ ] Goals are specific enough to verify ("12 questions answerable" not "users can ask questions")
- [ ] Non-goals are present and are NOT negated goals
- [ ] Design section emphasizes trade-offs, not just the solution
- [ ] Alternatives include trade-off analysis, not just "rejected because worse"
- [ ] Cross-cutting concerns cover security, privacy, and observability

**Operational Readiness**:
- [ ] Plan for victory exists with concrete milestones
- [ ] Open questions are ranked by impact
- [ ] Dependencies have owners and deadlines
- [ ] Success metrics are measurable
- [ ] Timeline is realistic given dependencies and team size

**Context Engineering**:
- [ ] Section headers are explicit and navigable
- [ ] Key information is in tables, not buried in prose
- [ ] Mermaid diagrams illustrate architecture and data flow
- [ ] Terminology is defined on first use
- [ ] Tech stack is in a structured table
- [ ] Status labels are consistent throughout

**Completeness**:
- [ ] A new team member could understand the system from this doc alone
- [ ] An AI agent could read this doc and understand the full system
- [ ] The doc covers what happens when things fail, not just the happy path
- [ ] Deferred items are explicit with reasons and target phases

### Review Approaches

**Lightweight review**: Share the doc, collect comments asynchronously. Best for mini design docs and incremental changes.

**Formal review**: Schedule a meeting with senior engineers. Best for major projects with complex trade-offs. Focus the meeting on the Alternatives Considered and Cross-Cutting Concerns sections — these are where the important debates happen.

### Questions to Ask During Review

1. What's the simplest version of this that could work?
2. What happens when [component X] fails?
3. How will we know if this is working?
4. What's the migration path if we're wrong?
5. What are we most uncertain about, and how do we reduce that uncertainty fastest?
6. Is there a way to validate the riskiest assumption before building everything?
7. What will the on-call engineer need to know at 3 AM?
8. Does this solve the actual problem, or a proxy for the problem?

## How to Run an OODA Review

The OODA loop (Observe, Orient, Decide, Act) is a continuous review process, not a one-time event.

### Daily (Critical Projects)

- Check the plan for victory — are we on track?
- Check the open questions list — are the top questions getting resolved?
- Check the working doc — is anyone blocked?
- Ask: are we still working on the right things?

### Weekly (Normal Projects)

- Review the plan for victory against actual progress
- Rank open questions — has the priority order changed?
- Write the weekly update
- Check if the design doc needs revision (did we learn something that changes the design?)

### At Milestones

- Review the design doc against reality — what diverged?
- Update or annotate the design doc with lessons learned
- Check success metrics — are we trending toward the targets?
- Decide: continue, pivot, or cut scope?

## Retrospective Format

Every 2-4 weeks, run a retrospective. Append notes to the working doc.

**Format (30 minutes)**:

1. **[13 min] Async brainstorm** — everyone writes items in two lists:
   - "What went well" — things to keep doing
   - "What we could improve" — things to change

2. **[2 min] Dedupe and vote** — combine similar items, everyone votes on the most important ones

3. **[10 min] Discuss top items** — focus on the highest-voted "what we could improve" items. For each: what happened, why, and what's the action item?

4. **[5 min] Action items** — assign owners and deadlines for improvements

### Retrospective Anti-Patterns

1. **Skipping retrospectives** — the only way to improve the process is to reflect on it
2. **All praise, no critique** — "what went well" without "what we could improve" is a waste of time
3. **No action items** — identifying problems without assigning fixes means they'll repeat
4. **Blame over systems** — focus on what process or information gap caused the problem, not who made the mistake
5. **Too infrequent** — every 8+ weeks is too late; problems compound

## Design Doc Lifecycle

```
DRAFT → IN REVIEW → APPROVED → [implementation] → HISTORICAL
                                                  ↓
                                          SUPERSEDED (if a new design doc replaces it)
```

After approval, the design doc should be updated only to:
- Mark resolved open questions
- Add "Lessons Learned" annotations
- Mark it as SUPERSEDED when a new design doc replaces it

Operational tracking (who's doing what, what's blocked) goes in the **working doc**, not the design doc.
