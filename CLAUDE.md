# Claude Code Portable Configuration

This repository contains a portable Claude Code configuration with MCP servers, skills, agents, commands, and hooks.

## Project Overview

A Git-versioned, portable configuration for Claude Code that works across macOS, Linux, and Windows.

## Repository Structure

```
.
├── .mcp.json                    # MCP server configurations (portable)
├── .claude/
│   ├── settings.json            # Claude Code settings with hooks
│   ├── hooks/                   # Git and workflow hooks
│   │   └── enforce-git-pull-rebase.sh
│   ├── skills/                  # Reusable skills
│   │   ├── internet-research/
│   │   │   └── SKILL.md
│   │   └── pr-writing/
│   │       └── SKILL.md
│   ├── agents/                  # Subagent definitions
│   │   ├── internet-researcher.md
│   │   └── pr-creator.md
│   └── commands/                # Custom slash commands
│       ├── web-search.md
│       ├── brave-search.md
│       └── pr.md
├── CLAUDE.md                    # This file (shared context)
└── README.md                    # User documentation
```

## Available Capabilities

### MCP Servers
- **brave-search**: Internet search via Brave Search API

### Skills
- **internet-research**: Expert internet research capabilities using Brave Search
- **pr-writing**: Expert PR and commit message writing following Conventional Commits

### Agents
- **internet-researcher**: Deep research subagent for complex queries
- **pr-creator**: Expert PR/MR creation agent for complex pull requests

### Commands
- `/web-search <query>`: Quick search using Claude's built-in WebSearch tool
- `/brave-search <query>`: Search using Brave Search MCP (requires `BRAVE_API_KEY`)
- `/pr [base-branch]`: Create PR/MR with Conventional Commits formatting (GitHub/GitLab/Azure DevOps)

### Hooks
- **enforce-git-pull-rebase**: Automatically adds `--rebase` to all `git pull` commands

## Environment Variables Required

Set these in your shell before running Claude Code:

```bash
export BRAVE_API_KEY="your-key-here"
```

## Git Conventions

**IMPORTANT:** This project enforces clean git history via hooks.

### Automatic Rebase on Pull

The `enforce-git-pull-rebase.sh` hook automatically converts:
```bash
git pull origin main       # becomes: git pull --rebase origin main
git pull origin develop    # becomes: git pull --rebase origin develop
git pull                   # becomes: git pull --rebase
```

This ensures a linear commit history without merge commits.

### Branch Strategy (GitFlow)

| Branch | Purpose | Protected |
|--------|---------|-----------|
| `main` | Production releases | Yes |
| `develop` | Integration | Yes |
| `feature/*` | New features | No |
| `hotfix/*` | Emergency fixes | No |

### Workflow

```
feature/* → PR to develop → PR to main
hotfix/*  → PR to main → then PR main to develop
```

## Conventions

- All MCP configs use `${VAR}` syntax for secrets
- Never commit API keys or secrets
- Skills go in `.claude/skills/<skill-name>/SKILL.md`
- Agents go in `.claude/agents/<agent-name>.md`
- Commands go in `.claude/commands/<command-name>.md`
- Hooks go in `.claude/hooks/<hook-name>.sh`
