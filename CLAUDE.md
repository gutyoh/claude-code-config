# Claude Code Portable Configuration

This repository contains a portable Claude Code configuration with MCP servers, skills, agents, and commands.

## Project Overview

A Git-versioned, portable configuration for Claude Code that works across macOS, Linux, and Windows.

## Repository Structure

```
.
├── .mcp.json                    # MCP server configurations (portable)
├── .claude/
│   ├── skills/                  # Reusable skills
│   │   └── internet-research/   # Brave Search skill
│   ├── agents/                  # Subagent definitions
│   │   └── internet-researcher.md
│   └── commands/                # Custom slash commands
│       └── search.md
├── CLAUDE.md                    # This file (shared context)
├── README.md                    # User documentation
└── BRANCH_PROTECTION.md         # Git workflow guide
```

## Available Capabilities

### MCP Servers
- **brave-search**: Internet search via Brave Search API

### Skills
- **internet-research**: Expert internet research capabilities

### Agents
- **internet-researcher**: Deep research subagent for complex queries

### Commands
- `/search <query>`: Quick internet search

## Environment Variables Required

Set these in your shell before running Claude Code:

```bash
export BRAVE_API_KEY="your-key-here"
```

## Development Workflow

This project uses GitFlow:
- `main`: Production-ready releases
- `develop`: Integration branch
- `feature/*`: New features (branch from develop)
- `hotfix/*`: Emergency fixes (branch from main)

## Conventions

- All MCP configs use `${VAR}` syntax for secrets
- Never commit API keys or secrets
- Skills go in `.claude/skills/<skill-name>/SKILL.md`
- Agents go in `.claude/agents/<agent-name>.md`
- Commands go in `.claude/commands/<command-name>.md`
