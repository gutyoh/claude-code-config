# How to Add an Agent

Create a custom subagent that Claude delegates to for domain-specific tasks.

## Prerequisites

- Claude Code installed and working
- This repo's global config installed via `setup.sh` (agents symlinked to `~/.claude/agents/`)

## 1. Create the agent file

```bash
touch .claude/agents/my-expert.md
```

## 2. Write the frontmatter

```yaml
---
name: my-expert
description: Expert [domain] engineer for [what it does]. Use proactively when [trigger conditions].
model: inherit
color: green
skills:
  - my-standards
---
```

| Field | Required | Rules |
|-------|----------|-------|
| `name` | Yes | Lowercase, hyphens. Must match filename without `.md` |
| `description` | Yes | Include "Use proactively when..." so Claude knows when to delegate |
| `model` | Yes | Always `inherit` |
| `color` | Yes | One of: `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan` |
| `skills` | No | List of skill names to preload into the agent's context |
| `hooks` | No | Agent-scoped hooks (see databricks-expert for example) |

### Available colors

| Color | Currently used by |
|-------|------------------|
| `red` | databricks-expert |
| `blue` | d2-tala-expert, pr-manager, code-reviewer-expert |
| `green` | python-expert |
| `yellow` | kedro-expert, linus-torvalds, design-doc-expert |
| `purple` | dotnet-expert, data-scientist |
| `orange` | rust-expert, dbt-expert, sonarqube-fixer |
| `pink` | ui-designer, diataxis-expert |
| `cyan` | langfuse-expert, internet-researcher |

## 3. Write the system prompt

Below the frontmatter `---`, write the system prompt in Markdown:

```markdown
---
name: my-expert
description: ...
model: inherit
color: green
---

You are an expert [domain] engineer focused on [core skill].

You will [do work] that:

1. **[Behavior 1]**: [description]
2. **[Behavior 2]**: [description]

Your development process:

1. Read existing code first
2. [Domain-specific step]
3. Apply standards from the preloaded skill
4. Run quality checklist before completing
```

Reference existing agents for patterns:

```bash
cat .claude/agents/python-expert.md      # Simple agent with skill
cat .claude/agents/databricks-expert.md  # Agent with hooks
cat .claude/agents/linus-torvalds.md     # Persona-only (no skills)
```

## 4. Add agent-scoped hooks (optional)

```yaml
---
name: my-expert
description: ...
model: inherit
color: green
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: ".claude/hooks/my-validation.sh"
---
```

The hook script must be executable (`chmod +x`).

## 5. Verify

Start a new Claude Code session (agents load at startup):

```bash
claude
```

```
/agents
```

Your agent should be listed. Test it:

```
Use the my-expert agent to [do something]
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Agent not in `/agents` list | File not in `~/.claude/agents/` | Verify symlink: `ls -la ~/.claude/agents/` |
| Agent not triggering automatically | Missing "Use proactively" in description | Add trigger conditions to `description` |
| Skill not loading | Name mismatch in `skills:` | Verify directory exists in `.claude/skills/` |
| Hook not firing | Script not executable | `chmod +x .claude/hooks/your-hook.sh` |

## See also

- [How to Add a Skill](how-to-add-skill.md): create the standards skill your agent loads
- [Configuration](configuration.md): full reference for agent frontmatter fields and colors
- [Architecture](architecture.md): why agents and skills are separated
- [Project Structure](project-structure.md): complete list of all agents and skills
