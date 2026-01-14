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
│   │   ├── enforce-git-pull-rebase.sh
│   │   └── open-file-in-ide.sh
│   ├── skills/                  # Reusable skills
│   │   ├── internet-research/
│   │   │   └── SKILL.md
│   │   └── pr-writing/
│   │       └── SKILL.md
│   ├── agents/                  # Subagent definitions
│   │   ├── internet-researcher.md
│   │   ├── pr-manager.md
│   │   ├── data-scientist.md
│   │   └── sonarqube-fixer.md
│   ├── scripts/                 # Utility scripts
│   │   ├── file-suggestion.sh
│   │   └── file-suggestion.ps1
│   └── commands/                # Custom slash commands
│       ├── web-search.md
│       ├── brave-search.md
│       └── pr.md
├── branch_protection_rules/     # GitHub Ruleset templates
│   ├── trunk-based/             # GitHub Flow (current)
│   │   └── main-branch-protection.json
│   ├── gitflow/                 # Enterprise workflow (archived)
│   │   ├── main-branch-protection.json
│   │   └── develop-branch-protection.json
│   └── README.md
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
- **pr-manager**: Expert PR/MR manager for full lifecycle (list, view, create, review, edit, close, reopen) with automatic workflow detection (GitFlow vs Trunk-based)
- **data-scientist**: Expert data scientist for ML, deep learning, and statistical analysis
- **sonarqube-fixer**: Expert SonarQube issue fixer for cognitive complexity, code smells, and security vulnerabilities

### Commands
- `/web-search <query>`: Quick search using Claude's built-in WebSearch tool
- `/brave-search <query>`: Search using Brave Search MCP (requires `BRAVE_API_KEY`)
- `/pr [base-branch]`: Create PR/MR with Conventional Commits formatting (GitHub/GitLab/Azure DevOps)

### Hooks
- **enforce-git-pull-rebase**: Automatically adds `--rebase` to all `git pull` commands
- **ide-diagnostics-opener**: Automatically opens files in IDE before `mcp__ide__getDiagnostics` (fixes JetBrains timeout bug #3085)

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
git pull                   # becomes: git pull --rebase
```

This ensures a linear commit history without merge commits.

### Branch Strategy (Trunk-Based / GitHub Flow)

| Branch | Purpose | Protected |
|--------|---------|-----------|
| `main` | Production (single source of truth) | Yes |
| `feat/*` | New features | No |
| `fix/*` | Bug fixes | No |
| `hotfix/*` | Emergency fixes | No |

### Workflow

```
feat/*   ──► PR to main (squash merge)
fix/*    ──► PR to main (squash merge)
hotfix/* ──► PR to main (squash merge)
```

### Branch Protection Templates

See `branch_protection_rules/` for ready-to-use GitHub Ruleset configurations:
- `trunk-based/` - Current workflow (recommended for 2026)
- `gitflow/` - Enterprise/traditional workflow (archived)

## Conventions

- All MCP configs use `${VAR}` syntax for secrets
- Never commit API keys or secrets
- Skills go in `.claude/skills/<skill-name>/SKILL.md`
- Agents go in `.claude/agents/<agent-name>.md`
- Commands go in `.claude/commands/<command-name>.md`
- Hooks go in `.claude/hooks/<hook-name>.sh`
