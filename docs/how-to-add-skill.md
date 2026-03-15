# How to Add a Skill

Create a reusable standards skill that agents load for domain-specific knowledge.

## Prerequisites

- Claude Code installed and working
- This repo's global config installed via `setup.sh` (skills symlinked to `~/.claude/skills/`)

## 1. Create the skill directory

```bash
mkdir -p .claude/skills/my-standards
```

## 2. Write SKILL.md

```bash
touch .claude/skills/my-standards/SKILL.md
```

```yaml
---
name: my-standards
description: [Domain] engineering standards for [what it covers]. Use when [trigger conditions].
---

# My Standards

You are a senior [domain] engineer who [core philosophy].

**Philosophy**: [One sentence guiding principle].

## Core Knowledge

Always load [core.md](core.md) — this contains the foundational principles:
- [Principle 1]
- [Principle 2]

## Conditional Loading

Load additional files based on task context:

| Task Type | Load |
|-----------|------|
| [Category 1] | [pattern-1.md](pattern-1.md) |
| [Category 2] | [pattern-2.md](pattern-2.md) |

## Quick Reference

[Most important rules as tables or code — what the agent sees first]

## When Invoked

1. **Read existing code** — understand before modifying
2. **Follow existing style** — match conventions
3. [Domain-specific steps]
4. **Run quality checklist** — verify before completing
```

## 3. Create core.md

Core is ALWAYS loaded. Put foundational principles here:

```bash
touch .claude/skills/my-standards/core.md
```

```markdown
# Core Principles

## 1. [First Principle]

[Explanation with correct/incorrect examples]

## 2. [Second Principle]

[Explanation with examples]

## N. Anti-Patterns

1. **[Bad practice]** — [what to do instead]
```

## 4. Add pattern files

Pattern files are CONDITIONALLY loaded — only when the task matches:

```bash
touch .claude/skills/my-standards/testing-patterns.md
touch .claude/skills/my-standards/deployment-patterns.md
```

```markdown
# Testing Patterns

## When to Write Tests
[Rules]

## Structure Template
[Template with code]

## Common Mistakes
1. [Mistake] — [fix]
```

## 5. Wire the skill to an agent

In your agent's frontmatter:

```yaml
---
name: my-expert
skills:
  - my-standards
---
```

The full skill content is injected into the agent's context at startup.

## 6. Verify

```bash
claude
```

```
What skills do you have available?
```

Or invoke the agent that loads it:

```
Use the my-expert agent to review this code
```

## Complete directory structure

```
.claude/skills/my-standards/
├── SKILL.md              # Entry point (required)
├── core.md               # Always loaded
├── pattern-1.md          # Conditionally loaded
├── pattern-2.md          # Conditionally loaded
└── references/           # Optional
    └── checklists.md
```

Keep SKILL.md under 500 lines. Move detailed material to separate files.

## Existing skills as reference

| Skill | Files | Key Pattern |
|-------|-------|-------------|
| `python-standards` | 7 + refs + versions | Version detection, conditional loading |
| `databricks-standards` | 5 | CLI-first, safety guardrails |
| `dbt-standards` | 8 | Three-layer architecture, platform-aware |
| `diataxis-standards` | 8 | Four quadrants, writing style |
| `design-doc-standards` | 7 | Three-layer planning, OODA |

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Skill not found by agent | Name mismatch | Verify `.claude/skills/<name>/SKILL.md` matches `skills:` in agent |
| Pattern file not loading | Not in SKILL.md table | Add to conditional loading table with relative link |
| Too much context | All files always loaded | Use conditional loading — only `core.md` loads always |
| Works locally, not globally | Symlink missing | Run `setup.sh` or `ln -s <repo>/.claude/skills ~/.claude/skills` |

## See also

- [How to Add an Agent](how-to-add-agent.md): create the agent that loads your skill
- [Architecture](architecture.md): why conditional loading preserves context efficiency
- [Project Structure](project-structure.md): complete list of all skills and their file counts
- [Configuration](configuration.md): full reference for skill frontmatter fields
