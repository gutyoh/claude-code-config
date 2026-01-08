# Claude Code Portable Configuration

A portable, Git-versioned configuration repository for Claude Code that works seamlessly across macOS, Linux, and Windows.

## What This Repository Contains

This repo provides a complete, portable Claude Code setup including:

| Component | Location | Purpose |
|-----------|----------|---------|
| **MCP Servers** | `.mcp.json` | External tool integrations (Brave Search, etc.) |
| **Skills** | `.claude/skills/` | Reusable capabilities with defined behaviors |
| **Agents** | `.claude/agents/` | Specialized subagents for complex tasks |
| **Commands** | `.claude/commands/` | Custom slash commands |
| **Hooks** | `.claude/hooks/` | Git and workflow automation |
| **Settings** | `.claude/settings.json` | Claude Code configuration with hooks |
| **Project Context** | `CLAUDE.md` | Shared project knowledge and conventions |

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-config.git
cd claude-code-config
```

### 2. Set Up Environment Variables

Create a `.env` file (gitignored) or export in your shell:

```bash
# Required for Brave Search MCP
export BRAVE_API_KEY="your-brave-api-key"

# Add other API keys as needed
```

**Get a free Brave API key:** https://api-dashboard.search.brave.com/

### 3. Start Claude Code

```bash
claude
```

That's it! All MCP servers, skills, commands, and hooks are automatically loaded.

## Prerequisites

- **jq**: Required for the git rebase hook to parse JSON
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt-get install jq`
  - Windows: `choco install jq` or `scoop install jq`

## Repository Structure

```
claude-code-config/
├── .mcp.json                      # MCP server configurations
├── .claude/
│   ├── settings.json              # Claude Code settings (hooks config)
│   ├── hooks/                     # Hook scripts
│   │   └── enforce-git-pull-rebase.sh
│   ├── skills/                    # Skills (reusable capabilities)
│   │   ├── internet-research/
│   │   │   └── SKILL.md
│   │   └── pr-writing/
│   │       └── SKILL.md
│   ├── agents/                    # Subagents for Task tool
│   │   ├── internet-researcher.md
│   │   └── pr-creator.md
│   └── commands/                  # Custom slash commands
│       ├── web-search.md
│       ├── brave-search.md
│       └── pr.md
├── CLAUDE.md                      # Project context (committed)
├── CLAUDE.local.md                # Personal notes (gitignored)
├── .gitignore                     # Comprehensive gitignore
└── README.md                      # This file
```

## Git Conventions

### Automatic `git pull --rebase`

This repository includes a **PreToolUse hook** that automatically adds `--rebase` to all `git pull` commands. This ensures a clean, linear commit history.

```bash
# What you type:
git pull origin develop

# What actually runs:
git pull --rebase origin develop
```

No configuration needed - the hook is automatically active when you run Claude Code in this repository.

## Portability: How It Works

### The Secret: Environment Variable Expansion

The `.mcp.json` supports `${VAR}` syntax for secrets:

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@brave/brave-search-mcp-server"],
      "env": {
        "BRAVE_API_KEY": "${BRAVE_API_KEY}"
      }
    }
  }
}
```

**No secrets in Git!** Each developer sets their own API keys locally.

### Project Scope vs User Scope

| Scope | Storage | Portable? | Use Case |
|-------|---------|-----------|----------|
| `--scope user` | `~/.claude.json` | No | Personal global settings |
| `--scope project` | `.mcp.json` | **Yes** | Team-shared configs |

This repository uses **project scope** for everything.

## Adding New MCP Servers

```bash
# Add with project scope (stored in .mcp.json)
claude mcp add server-name --scope project \
  -e API_KEY='${API_KEY}' \
  -- npx -y @org/mcp-server
```

## Branching Strategy (GitFlow)

This repository uses GitFlow with protected branches:

| Branch | Purpose | Protected |
|--------|---------|-----------|
| `main` | Production releases | Yes (via GitHub Rulesets) |
| `develop` | Integration | Yes (via GitHub Rulesets) |
| `feature/*` | New features | No |
| `hotfix/*` | Emergency fixes | No |

### Creating a Feature

```bash
git checkout develop
git pull origin develop          # Automatically rebases!
git checkout -b feature/my-feature
# ... make changes ...
git push -u origin feature/my-feature
# Create PR: feature/* → develop
```

### Hotfix Flow

```bash
git checkout main
git pull origin main             # Automatically rebases!
git checkout -b hotfix/critical-bug
# ... fix the bug ...
git push -u origin hotfix/critical-bug

# Step 1: Create PR from hotfix/* → main
# Step 2: After merge, create PR from main → develop to sync the fix
```

## License

MIT License - Feel free to use and modify for your own projects.
