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
 
## Installation Options
 
You have **two options** for using this configuration:
 
| Option | Use Case | Scope |
|--------|----------|-------|
| **[Global Install](#global-installation-recommended)** | Use across ALL your projects | User scope (`~/.claude/`) |
| **[Project Install](#project-installation)** | Use only in this directory | Project scope (`.claude/`) |
 
---
 
## Global Installation (Recommended)
 
Follow these steps to make this configuration available across **all projects** on your machine. This is ideal if you want your Claude Code setup to follow you everywhere.
 
### Prerequisites
 
1. **Claude Code installed** (via any method):
   ```bash
   # macOS/Linux (recommended)
   curl -fsSL https://claude.ai/install.sh | bash
 
   # Or via Homebrew
   brew install --cask claude-code
 
   # Or via npm (requires Node.js 18+)
   npm install -g @anthropic-ai/claude-code
   ```
 
2. **jq installed** (required for hooks):
   ```bash
   # macOS
   brew install jq
 
   # Ubuntu/Debian
   sudo apt-get install jq
 
   # Windows (via Chocolatey)
   choco install jq
   ```
 
3. **Git installed** (to clone this repo)
 
### Step 1: Clone This Repository
 
Choose a location to store your centralized config. We recommend `~/repos/` or `~/projects/`:
 
```bash
# Create a repos directory if you don't have one
mkdir -p ~/repos
 
# Clone this repository
cd ~/repos
git clone https://github.com/YOUR_USERNAME/claude-code-config.git
 
# Enter the directory
cd claude-code-config
```
 
### Step 2: Run the Setup Script
 
The setup script creates symlinks and **automatically configures MCP servers** in user scope. Safe to re-run if you move the repo.
 
**macOS / Linux / WSL / Git Bash:**
 
```bash
./setup.sh
```
 
**Windows (PowerShell as Administrator):**
 
```powershell
.\setup.ps1
```
 
The script will:
- Create `~/.claude/` if it doesn't exist
- Symlink `commands/`, `skills/`, `agents/`, `hooks/` to your global config
- **Add Brave Search MCP server to user scope** (available in all projects)
- Check for required environment variables
 
> **Note:** Symlinks keep everything in sync. When you `git pull` updates, your global config updates automatically.
 
### Step 3: Set Environment Variables

Add your API keys to your shell profile (`~/.bashrc`, `~/.zshrc`, or `~/.profile`):

```bash
# Required for Brave Search
export BRAVE_API_KEY="your-brave-api-key-here"

# Optional for SonarQube integration
export SONARQUBE_TOKEN="your-sonarqube-token-here"
export SONARQUBE_URL="https://your-sonarqube-server.com"
```

Then reload: `source ~/.zshrc`

---

## API Keys Setup

### Brave Search API (Required for `/brave-search`)

| | |
|---|---|
| **Free tier** | 2,000 searches/month |
| **Sign up** | https://api-dashboard.search.brave.com/ |

**Steps:**
1. Go to https://api-dashboard.search.brave.com/
2. Sign up or log in with your account
3. Click **"Create API Key"**
4. Copy the key and add to your shell profile

### SonarQube API (Optional for `sonarqube-fixer`)

| | |
|---|---|
| **Required for** | Fetching issues directly from SonarQube server |
| **Works without** | Yes - just paste issue details to the agent |

**Steps:**
1. Log in to your SonarQube instance (e.g., `https://sonarqube.yourcompany.com`)
2. Click your profile → **My Account** → **Security**
3. Under **Generate Tokens**, enter a name and click **Generate**
4. Copy the token immediately (it won't be shown again!)
5. Add both variables to your shell profile:
   ```bash
   export SONARQUBE_TOKEN="squ_xxxxxxxxxxxxxxxxxxxx"
   export SONARQUBE_URL="https://sonarqube.yourcompany.com"
   ```

> **Tip:** The `sonarqube-fixer` agent can also work without API access. It automatically reads SonarLint issues from your IDE (PyCharm/VSCode/Cursor) via diagnostics.

---

**Windows (System Environment Variables):**

1. Open **System Properties** → **Advanced** → **Environment Variables**
2. Under **User variables**, click **New**
3. Add each variable (`BRAVE_API_KEY`, `SONARQUBE_TOKEN`, `SONARQUBE_URL`)
 
### Step 4: Verify Installation
 
Start Claude Code in **any project** and verify everything works:
 
```bash
cd ~/some-other-project
claude
```
 
**Check MCP servers:**
```bash
claude mcp list
```

You should see `brave-search` listed with scope `user`.

**Check available commands:**
```
> /help
```

You should see:
- `/web-search` (user)
- `/brave-search` (user)
- `/pr` (user)

**Check available agents:**
```
> /agents
```

You should see:
- `internet-researcher` - Deep research using Brave Search
- `pr-creator` - PR/MR creation with GitFlow/Trunk detection
- `data-scientist` - ML, deep learning, statistical analysis
- `sonarqube-fixer` - Fix SonarQube/SonarLint issues (auto-reads from IDE)
 
**Test the Brave Search MCP:**
```
> /brave-search latest Claude Code features
```
 
### Step 5: Keep Your Config Updated
 
Since you cloned a Git repo, pull updates regularly:
 
```bash
cd ~/repos/claude-code-config
git pull origin main
```
 
If you used symlinks, your global config updates automatically!
 
---
 
## Project Installation
 
Use this method if you only want the configuration in a specific project directory.
 
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
 
That's it! All MCP servers, skills, commands, and hooks are automatically loaded for this project.
 
---
 
## Repository Structure
 
```
claude-code-config/
├── setup.sh                       # Setup script for macOS/Linux
├── setup.ps1                      # Setup script for Windows
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
│   │   ├── pr-creator.md
│   │   ├── sonarqube-fixer.md
│   │   └── data-scientist.md
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

## Hooks

This configuration includes several PreToolUse hooks in `.claude/settings.json`:

### 1. Git Pull Rebase Hook

Automatically adds `--rebase` to `git pull` commands for linear history.

**Location:** `.claude/hooks/enforce-git-pull-rebase.sh`

### 2. IDE Diagnostics Hook (JetBrains/VSCode Workaround)

Automatically opens files in your IDE before calling `mcp__ide__getDiagnostics`. This solves a known bug ([#3085](https://github.com/anthropics/claude-code/issues/3085)) where JetBrains IDEs (PyCharm, IntelliJ, WebStorm) timeout on diagnostics if the file is not the currently active tab.

**How it works (3-tier fallback system):**
1. **Tier 1 - User Preference**: If `CLAUDE_IDE` env var is set, use that IDE
2. **Tier 2 - Auto-detect Running IDE**: Check which IDE is currently running (via `pgrep`)
3. **Tier 3 - Fallback**: Use first available IDE command

This ensures the hook opens files in the IDE you're actually using, not just the first one installed.

**Supported IDEs:**
- VSCode (`code`)
- VSCode Insiders (`code-insiders`)
- Cursor (`cursor`)
- Windsurf (`windsurf`)
- Antigravity (`antigravity`)
- PyCharm (`pycharm`)
- IntelliJ IDEA (`idea`)
- WebStorm (`webstorm`)
- PhpStorm (`phpstorm`)
- GoLand (`goland`)
- Rider (`rider`)
- CLion (`clion`)
- RubyMine (`rubymine`)

**Manual IDE Selection:**

If you want to force a specific IDE (overriding auto-detection), set the `CLAUDE_IDE` environment variable:

```bash
# In ~/.zshrc or ~/.bashrc
export CLAUDE_IDE="code-insiders"   # Force VSCode Insiders
export CLAUDE_IDE="cursor"          # Force Cursor
export CLAUDE_IDE="pycharm"         # Force PyCharm
export CLAUDE_IDE="windsurf"        # Force Windsurf
```

**How Auto-Detection Works:**

1. **Multiple IDEs installed?** → Opens file in whichever IDE is currently running
2. **No IDE running?** → Opens in first available (priority: code-insiders → cursor → windsurf → code → pycharm → idea)
3. **Want to override?** → Set `CLAUDE_IDE` environment variable

**Examples:**

```bash
# Scenario 1: Both PyCharm and VSCode Insiders installed, VSCode Insiders is running
# → Opens in VSCode Insiders (auto-detected)

# Scenario 2: Both PyCharm and VSCode installed, nothing is running
# → Opens in VSCode (higher priority in fallback list)

# Scenario 3: Both installed, but you want to always use PyCharm
# → export CLAUDE_IDE="pycharm" (manual override)
```

This hook benefits **all agents** that use `getDiagnostics`, especially the `sonarqube-fixer` agent.

## Syncing Across Machines
 
The main benefit of this repo is **portability**. Here's how to sync your config across Mac, Linux, and Windows:
 
### Initial Setup (First Machine)
 
1. Fork this repo to your GitHub account
2. Follow the [Global Installation](#global-installation-recommended) steps
3. Customize commands, skills, and agents as needed
4. Commit and push your changes
 
### Setting Up Additional Machines
 
1. Clone your forked repo:
   ```bash
   cd ~/repos
   git clone https://github.com/YOUR_USERNAME/claude-code-config.git
   cd claude-code-config
   ```
 
2. Run the setup script:
   ```bash
   ./setup.sh        # macOS/Linux
   .\setup.ps1       # Windows (as Admin)
   ```
 
3. Add MCP servers and environment variables (Steps 3-4 from Global Installation)
 
4. Done! Your config is now synced.
 
### Keeping Everything in Sync
 
```bash
# On any machine, pull the latest changes
cd ~/repos/claude-code-config
git pull origin main
 
# If using symlinks, you're done!
# If you copied files, re-run the copy commands from Step 3
```
 
---
 
## How It Works
 
### Configuration Scopes
 
Claude Code supports multiple configuration scopes:
 
| Scope | Location | Use Case |
|-------|----------|----------|
| **User** | `~/.claude/` and `~/.claude.json` | Personal config across all projects |
| **Project** | `.claude/` and `.mcp.json` | Team-shared config for one repo |
| **Local** | `.claude/settings.local.json` | Per-machine overrides (gitignored) |
 
### What Goes Where
 
| Component | User Scope | Project Scope |
|-----------|------------|---------------|
| Commands | `~/.claude/commands/` | `.claude/commands/` |
| Skills | `~/.claude/skills/` | `.claude/skills/` |
| Agents | `~/.claude/agents/` | `.claude/agents/` |
| Settings | `~/.claude/settings.json` | `.claude/settings.json` |
| MCP Servers | `~/.claude.json` | `.mcp.json` |
| Context | `~/.claude/CLAUDE.md` | `CLAUDE.md` |
 
### Environment Variable Expansion
 
MCP configs support `${VAR}` syntax for secrets:
 
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
 
**No secrets in Git!** Each machine sets its own API keys locally.
 
### Scope Precedence
 
When the same item exists at multiple scopes, Claude Code uses this priority:
 
1. **Project** overrides **User** (for project-specific needs)
2. **User** provides defaults (for personal preferences)
 
---
 
## Adding New MCP Servers
 
**For global use (user scope):**
 
```bash
claude mcp add server-name --scope user \
  -e API_KEY='${API_KEY}' \
  -- npx -y @org/mcp-server
```
 
**For project use (stored in .mcp.json):**
 
```bash
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
 
## Official Documentation
 
This configuration follows the official Claude Code documentation:
 
- [Claude Code Settings](https://code.claude.com/docs/en/settings) - Configuration scopes and file locations
- [MCP Servers](https://code.claude.com/docs/en/mcp) - Adding and configuring MCP integrations
- [Slash Commands](https://code.claude.com/docs/en/slash-commands) - Creating custom commands
- [Subagents](https://code.claude.com/docs/en/sub-agents) - Defining specialized agents
- [Agent Skills](https://code.claude.com/docs/en/skills) - Creating reusable skills
- [Common Workflows](https://code.claude.com/docs/en/common-workflows) - Best practices and examples
 
## License
 
MIT License - Feel free to use and modify for your own projects.