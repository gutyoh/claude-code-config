# Claude Code Portable Configuration

[![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?logo=claude&logoColor=fff)](https://docs.anthropic.com/en/docs/claude-code)
[![macOS](https://img.shields.io/badge/macOS-000?logo=apple&logoColor=fff)](#)
[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=000)](#)
[![Windows](https://img.shields.io/badge/Windows-0078D4?logo=windows&logoColor=fff)](#)
[![GitHub last commit](https://img.shields.io/github/last-commit/gutyoh/claude-code-config)](https://github.com/gutyoh/claude-code-config/commits)

A portable, Git-versioned configuration repository for Claude Code that works seamlessly across macOS, Linux, and Windows.

<details>
<summary><strong>Table of Contents</strong></summary>

- [What This Repository Contains](#what-this-repository-contains)
- [Installation Options](#installation-options)
- [Global Installation (Recommended)](#global-installation-recommended)
- [API Keys Setup](#api-keys-setup)
- [Project Installation](#project-installation)
- [Repository Structure](#repository-structure)
- [Git Conventions](#git-conventions)
- [Hooks](#hooks)
  - [Git Pull Rebase Hook](#1-git-pull-rebase-hook)
  - [IDE Diagnostics Hook](#2-ide-diagnostics-hook-jetbrainsvscode-workaround)
  - [Unified Database Guardrail](#3-unified-database-guardrail)
  - [Fast File Suggestion](#4-fast-file-suggestion-optional-performance-enhancement)
  - [Statusline with Billing Tracking](#5-statusline-with-billing-tracking)
- [Proxy Launcher](#proxy-launcher)
  - [How It Works](#how-the-proxy-launcher-works)
  - [Quick Start](#proxy-quick-start)
  - [Available Profiles](#available-profiles)
  - [CLI Reference](#cli-reference)
  - [Creating Custom Profiles](#creating-custom-profiles)
  - [Troubleshooting](#proxy-troubleshooting)
- [Syncing Across Machines](#syncing-across-machines)
- [How It Works](#how-it-works)
- [Adding New MCP Servers](#adding-new-mcp-servers)
- [Branching Strategy](#branching-strategy-trunk-based--github-flow)
- [Testing and Portability](#testing-and-portability)
- [Official Documentation](#official-documentation)

</details>

## What This Repository Contains
 
This repo provides a complete, portable Claude Code setup including:
 
| Component | Location | Purpose |
|-----------|----------|---------|
| **MCP Servers** | `.mcp.json` | External tool integrations (Brave Search, etc.) |
| **Skills** | `.claude/skills/` | Reusable capabilities with defined behaviors |
| **Agents** | `.claude/agents/` | Specialized subagents for complex tasks |
| **Hooks** | `.claude/hooks/` | Git and workflow automation |
| **Scripts** | `.claude/scripts/` | Utility scripts (file suggestion, etc.) |
| **Settings** | `.claude/settings.json` | Claude Code configuration with hooks |
| **Proxy Launcher** | `bin/` | Route Claude Code through alternative model providers |
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
- Symlink `skills/`, `agents/`, `hooks/` to your global config
- Add `bin/` to PATH and install `claude` / `clp` shell shortcuts
- **Add Brave Search MCP server to user scope** (available in all projects)
- **Install in parallel for OpenCode** if `opencode` is detected on PATH (translates agents, generates `~/.config/opencode/opencode.json`, symlinks `AGENTS.md`)
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
| **Free tier** | 1,000 searches/month ($5 free credits) |
| **Sign up** | https://api-dashboard.search.brave.com/ |

**Steps:**
1. Go to https://api-dashboard.search.brave.com/
2. Sign up or log in with your account
3. Click **"Create API Key"**
4. Copy the key and add to your shell profile

### Tavily API (Required for `/tavily-search`)

| | |
|---|---|
| **Free tier** | 1,000 credits/month |
| **Sign up** | https://tavily.com |

**Steps:**
1. Go to https://tavily.com
2. Sign up or log in with your account
3. Copy your API key from the dashboard
4. Add to your shell profile

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
- `data-scientist` - ML, deep learning, statistical analysis
- `databricks-expert` - Query data, explore Unity Catalog, audit permissions, monitor jobs
- `design-doc-expert` - Engineering planning: design docs, DRI working docs, ADRs, weekly updates
- `diataxis-expert` - Documentation framework: tutorials, how-to guides, reference, explanation
- `internet-researcher` - Deep research using Brave Search
- `kedro-expert` - Build data pipelines, manage catalogs, configure environments
- `pr-manager` - Full PR/MR lifecycle (list, view, create, review, edit) with workflow detection
- `python-expert` - Clean, type-safe, production-ready Python code
- `sonarqube-fixer` - Fix SonarQube/SonarLint issues (auto-reads from IDE)
- `ui-designer` - UI components, styling, design systems, accessibility
 
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
├── bin/                                # Proxy launcher scripts
│   ├── claude-proxy                    # Single entry point for all proxy profiles
│   ├── proxy-start-codex.sh            # Profile: CLIProxyAPI + OpenAI Codex
│   └── proxy-start-antigravity.sh      # Profile: Antigravity (Google Cloud Code)
├── .claude/
│   ├── settings.json              # Claude Code settings (hooks config)
│   ├── hooks/                     # Hook scripts
│   │   ├── enforce-git-pull-rebase.sh
│   │   ├── open-file-in-ide.sh
│   │   └── sql-guardrail.sh       # Unified DB guardrail (STRICT/STANDARD/MONGO)
│   ├── skills/                    # Skills (reusable capabilities)
│   │   ├── brave-search/          # Brave Search MCP skill
│   │   ├── d2-tala-standards/     # D2 + TALA diagramming standards
│   │   ├── databricks-standards/  # Databricks engineering standards
│   │   ├── dbt-standards/         # dbt engineering standards
│   │   ├── design-doc-standards/  # Design doc + DRI working doc + ADR standards
│   │   ├── diataxis-standards/    # Diataxis documentation framework standards
│   │   ├── dotnet-standards/      # .NET/C# engineering standards
│   │   ├── internet-research/     # Multi-source internet research
│   │   ├── kedro-standards/       # Kedro pipeline standards
│   │   ├── langfuse/              # Langfuse observability standards
│   │   ├── mongodb-standards/     # MongoDB engineering standards (+ evals)
│   │   ├── sql-standards/         # Cross-dialect SQL standards (+ evals)
│   │   ├── mcp-key-rotate/        # MCP API key rotation
│   │   ├── pr/                    # PR creation (Conventional Commits)
│   │   ├── pr-operations/         # Cross-platform PR/MR operations
│   │   ├── pr-review/             # Multi-agent PR review
│   │   ├── pr-writing/            # PR and commit message writing
│   │   ├── python-standards/      # Python engineering standards
│   │   ├── rust-standards/        # Rust engineering standards
│   │   ├── tavily-search/         # Tavily AI-native search
│   │   └── web-search/            # Built-in web search
│   ├── agents/                    # Subagent definitions
│   │   ├── code-reviewer-expert.md
│   │   ├── d2-tala-expert.md
│   │   ├── data-scientist.md
│   │   ├── databricks-expert.md
│   │   ├── dbt-expert.md
│   │   ├── design-doc-expert.md
│   │   ├── diataxis-expert.md
│   │   ├── dotnet-expert.md
│   │   ├── internet-researcher.md
│   │   ├── kedro-expert.md
│   │   ├── langfuse-expert.md
│   │   ├── linus-torvalds.md
│   │   ├── mongodb-expert.md
│   │   ├── pr-manager.md
│   │   ├── python-expert.md
│   │   ├── rust-expert.md
│   │   ├── sonarqube-fixer.md
│   │   ├── sql-expert.md
│   │   └── ui-designer.md
│   ├── scripts/                   # Utility scripts
│   │   ├── file-suggestion.sh
│   │   ├── file-suggestion.ps1
│   │   └── statusline.sh          # Two-tier statusline with billing
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

### 3. Unified Database Guardrail

A single hook that protects all database CLI commands with three safety levels. Configured at the **agent level** (in agent frontmatter), not in project-level `settings.json`.

**Location:** `.claude/hooks/sql-guardrail.sh`

**Safety Levels:**

| Level | CLIs | What it blocks | What it allows |
|-------|------|----------------|----------------|
| **STRICT** | `databricks` | All mutations: INSERT, UPDATE, DELETE, TRUNCATE, MERGE, DROP, CREATE, ALTER, GRANT, REVOKE | SELECT, DESCRIBE, SHOW, EXPLAIN |
| **STANDARD** | `psql`, `mysql`, `sqlcmd`, `sqlite3`, `duckdb`, `sqlplus`, `clickhouse-client` | Catastrophic ops: DROP DATABASE, TRUNCATE TABLE, DELETE without WHERE | Controlled writes: INSERT, UPDATE, CREATE, DELETE with WHERE |
| **MONGO** | `mongosh` | `db.dropDatabase()`, `collection.drop()`, `deleteMany({})`, `remove({})` with empty filter | Normal CRUD with filters, aggregation, index management |

**How it works:**
1. Reads the tool input JSON from stdin (standard Claude Code hook protocol)
2. Detects the database CLI in the command and assigns the safety level
3. Pattern-matches against blocked operations (case-insensitive)
4. Exits with code `2` to block, or `0` to allow (with optional stderr warnings)
5. Fails open on empty stdin, missing `jq`, or invalid JSON — never blocks non-database commands

**Agents using this hook:** `databricks-expert`, `sql-expert`, `mongodb-expert`

### 4. Fast File Suggestion (Optional Performance Enhancement)

Provides lightning-fast file discovery when using `@` mentions in Claude Code, leveraging modern CLI tools for 10-100x performance improvement on large codebases.

**Location:** `.claude/scripts/file-suggestion.sh` (macOS/Linux) and `.claude/scripts/file-suggestion.ps1` (Windows)

**What it does:**
When you type `@` to reference a file in Claude Code, the default file suggestion can be slow on large codebases. This custom script uses industry-standard tools (`fd` + `fzf`) to provide blazing-fast, intelligent file discovery.

**Performance Benefits:**

| Codebase Size | Default | With fd + fzf | Improvement |
|--------------|---------|---------------|-------------|
| Small (100 files) | ~50ms | ~10ms | 5x faster |
| Medium (1,000 files) | ~500ms | ~30ms | 16x faster |
| Large (10,000+ files) | 2-5s | ~100ms | 20-50x faster |

**Features:**
- Respects `.gitignore` automatically
- Follows symlinks correctly
- Includes hidden files (`.env`, `.gitignore`, etc.)
- Fuzzy matching with `fzf`
- Cross-platform (macOS, Linux, Windows)

**Prerequisites:**

The setup script automatically configures this feature if the required tools are installed:

```bash
# macOS
brew install fd fzf

# Ubuntu/Debian
sudo apt-get install fd-find fzf

# Windows (choose one)
scoop install fd fzf
winget install sharkdp.fd junegunn.fzf
choco install fd fzf
```

**How it works:**

When configured, Claude Code calls the file suggestion script which:
1. Uses `fd` to rapidly find all files (respecting `.gitignore`)
2. Pipes results to `fzf` for fuzzy matching against your query
3. Returns up to 15 matching file paths

**Auto-configuration:**

The `setup.sh` and `setup.ps1` scripts automatically:
- Check if `fd` and `fzf` are installed
- Create symlink: `~/.claude/scripts/` → `<repo>/.claude/scripts/`
- Add `fileSuggestion` configuration to `~/.claude/settings.json`
- Skip gracefully if prerequisites are missing (uses default file suggestion)

**Manual Configuration (if needed):**

If you skipped the setup script or installed tools later, add this to `~/.claude/settings.json`:

```json
{
  "fileSuggestion": {
    "type": "command",
    "command": "~/.claude/scripts/file-suggestion.sh"
  }
}
```

On Windows, use:
```json
{
  "fileSuggestion": {
    "type": "command",
    "command": "~/.claude/scripts/file-suggestion.ps1"
  }
}
```

**When to use this:**
- You work on repos with 1,000+ files
- You frequently use `@` file mentions
- You want professional-grade tooling
- You work with monorepos or large projects

**When to skip:**
- Small projects (<500 files)
- You rarely use `@` mentions
- You prefer zero-config setup

### 5. Statusline with Billing Tracking

Displays real-time session metrics in Claude Code's status bar, including model info, usage percentage, time remaining, token counts, and cost tracking.

**Location:** `.claude/scripts/statusline.sh`

**What it shows:**

| Metric | Description |
|--------|-------------|
| Model | Current model (e.g., `opus-4.5`) |
| Session % | Percentage of 5-hour billing window used |
| Resets | Time until session resets |
| In/Out | Input and output tokens |
| Cache | Cache read tokens |
| Cost | Current cost + burn rate |

**Two-Tier Display (adapts to terminal width):**

Wide terminal (≥110 cols):
```
opus-4.5 | session: 43% used | resets: 3h10m | in: 1.6k out: 587 | cache: 6.9M | $5.70 ($3.11/hr)
```

Narrow terminal (<110 cols):
```
opus-4.5 | 43% | 3h10m | 1.6k/587/6.9M | $5.75
```

**Prerequisites:**

```bash
# Required
npm install -g ccusage

# Also needed (usually pre-installed)
brew install jq  # macOS
sudo apt-get install jq  # Ubuntu/Debian
```

**Auto-configuration:**

The `setup.sh` script automatically:
- Checks if `ccusage` and `jq` are installed
- Adds `statusLine` configuration to `~/.claude/settings.json`
- Uses the two-tier script from `~/.claude/scripts/statusline.sh`

**Manual Configuration (if needed):**

Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/statusline.sh",
    "padding": 0
  }
}
```

**When to use this:**
- You have a Claude Pro/Max subscription
- You want to track billing window usage
- You want visibility into token consumption
- You want to pace your usage throughout the day

### 6. Cross-Machine Session Sync (claude-sync)

Syncs your `~/.claude/` (sessions, projects, settings) across machines via encrypted cloud storage. Optional — requires the [claude-sync](https://github.com/sammcj/claude-sync) tool installed on every machine you want synced.

**Locations:** `.claude/hooks/cc-sync-pull.sh` (SessionStart) and `.claude/hooks/cc-sync-push.sh` (SessionEnd)

**How it works:**

1. **SessionStart** → `cc-sync-pull.sh` detaches `claude-sync pull -q --force`, then optionally `~/.claude/cc-sync-remap.sh` for per-machine path rewrites (e.g., `/Users/<user>` → `/home/<user>` when crossing macOS↔Linux)
2. **SessionEnd** → `cc-sync-push.sh` detaches `claude-sync push` to upload changes for the next machine
3. **Fail-safe** — both hooks `set +e` and always `exit 0`. Errors land in `~/.claude/cc-sync-pull.log` / `cc-sync-push.log`

**Both transfers are detached, and that is load-bearing:**

- **SessionStart runs synchronously.** Whatever the pull spends is added to the time before you get a prompt, and a pull is a network round trip over the whole tracked file set. Detaching returns the hook in milliseconds; the transfer lands in time for the next session. Both hook entries also carry `"timeout": 10` as a backstop — a hook without one is unbounded.
- **SessionEnd cannot wait.** An inline push is killed the moment Claude Code exits, so the upload dies mid-flight and the remote never advances. A remote frozen behind local state is what makes the next pull diverge and write `.conflict.<timestamp>` copies — which then become newly tracked files and compound every session. The detached child outlives the parent and finishes the upload.

To confirm pushes are landing, compare the `push start` and `push exit=` lines in `~/.claude/cc-sync-push.log`; every start should have a matching exit.

**Env overrides:**

| Variable | Default | Effect |
|---|---|---|
| `CC_SYNC_BLOCKING` | `0` | `1` waits for the transfer instead of detaching |
| `CC_SYNC_TIMEOUT_SEC` | `10` | Wall-clock bound in blocking mode (needs GNU `timeout`) |

**No-op when `claude-sync` isn't installed.** Safe to ship enabled by default. To opt in, install `claude-sync` via its repo instructions on each machine.

## Shell + Terminal Configuration

Optional opinionated presets for the **fish shell** and the **Ghostty terminal** — paired daily-driver setup for macOS and Linux. Copy-install one preset of each, customize as needed.

### Fish Shell ([docs/fish/](./docs/fish/))

Three preset tiers, all modular (`conf.d/` + `functions/`):

| Preset | Use case |
|---|---|
| `config-minimal/` | Servers, throwaway boxes |
| `config-recommended/` | Most users — sensible defaults, modern CLI tool init |
| `config-power-user/` | Daily driver — Claude Code, mise, bun, dbt, Tide prompt, cross-platform brew detection, SSH socket auto-detection, OS-aware Tide badge, zellij auto-attach on SSH |

See [`docs/how-to-configure-fish.md`](./docs/how-to-configure-fish.md) for the full guide.

### Ghostty Terminal ([docs/ghostty/](./docs/ghostty/))

Six presets covering the spectrum:

| Preset | Philosophy |
|---|---|
| `config-minimal.ini` | Clean macOS-native feel, fewest overrides |
| `config-recommended.ini` | Daily driver — productivity-focused, no visual noise |
| `config-power-user.ini` | tmux + Neovim workflow, max screen real estate |
| `config-aesthetic.ini` | Transparent + blurred, riced |
| `config-maximalist.ini` | Every popular option enabled (good starting point to trim from) |
| `config-tip.ini` | Tip-channel preset with Ghostty 1.3+ features (click-to-move cursor, command-finish notifications, P3 colorspace, OSC 52) |

See [`docs/how-to-configure-ghostty.md`](./docs/how-to-configure-ghostty.md) for the full guide.

All presets target macOS + Linux. Ghostty silently ignores `macos-*` keys on Linux, and `super+` keybinds work as Cmd (macOS) or Super/Win (Linux) automatically.

## Proxy Launcher

Route Claude Code through alternative model providers (OpenAI Codex, Google Gemini, Antigravity Cloud Code) using a single unified CLI. The proxy launcher auto-starts the backend, configures environment variables, and launches Claude Code — all in one command.

### How the Proxy Launcher Works

```
┌──────────────┐         ┌──────────────────┐         ┌─────────────────────────┐
│  claude-proxy │────────▶│  Profile Script  │────────▶│  Provider Backend       │
│  (entry point)│         │  proxy-start-*   │         │                         │
│              │         │                  │         │  codex: CLIProxyAPI     │
│  Configures: │         │  Starts the      │         │  antigravity: Cloud Code│
│  • base URL  │         │  proxy server    │         │  custom: your own       │
│  • auth token│         │  in background   │         │                         │
│  • model     │         │                  │         │                         │
└──────┬───────┘         └──────────────────┘         └─────────────────────────┘
       │
       ▼
┌──────────────┐
│  Claude Code  │
│  (exec claude)│
└──────────────┘
```

**How it works step-by-step:**

1. Checks if the proxy is already running (HTTP health check)
2. If not running, launches the profile's start script in the background
3. Waits up to 5 seconds for the proxy to become reachable
4. Sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and model environment variables
5. Runs `claude` with all environment variables injected — your session starts immediately

> **Key design principle:** Profiles only control *how to start the proxy*. Model selection is decoupled — you can use any model string the backend supports.

**PATH and shortcuts setup:** The `setup.sh` script automatically adds `bin/` to your shell PATH and installs shell functions in `~/.zshrc`, `~/.bashrc`, or `~/.profile`:

```bash
claude        # normal Claude Code, with bypassPermissions available in Shift+Tab cycle
claude -a     # start Claude Code directly in bypassPermissions mode
clp           # claude-proxy with gpt-5.5(high), bypassPermissions available in Shift+Tab cycle
clp -a        # claude-proxy with gpt-5.5(high), directly in bypassPermissions mode
```

The proxy shortcut default model can be overridden per shell:

```bash
export CLAUDE_PROXY_MODEL="gpt-5.5(high)"
```

If you skipped this during setup, add PATH manually:

```bash
# Add to ~/.zshrc or ~/.bashrc (use the actual path to your clone):
export PATH="/path/to/claude-code-config/bin:$PATH"
```

Or re-run `./setup.sh` to configure PATH and shortcuts automatically.

### Proxy Quick Start

#### Antigravity (Google Cloud Code)

Uses your Google account to access Claude and Gemini models for free via [Antigravity Cloud Code](https://github.com/badrisnarayanan/antigravity-claude-proxy).

**Prerequisites:**

| Tool | Install |
|------|---------|
| Node.js 18+ | `brew install node` |
| Google account | Any Gmail / Google Workspace account |

**First-time setup** (link your Google account):

```bash
# Start the proxy manually
npx antigravity-claude-proxy@latest start

# Open http://localhost:8081 in your browser
# Go to Accounts → Add Account → complete Google OAuth
# Once linked, press Ctrl+C to stop
```

**Run Claude Code:**

```bash
# Claude models via Antigravity
./bin/claude-proxy -p antigravity -m 'claude-sonnet-4-5-thinking'

# Gemini models via Antigravity
./bin/claude-proxy -p antigravity -m 'gemini-3-pro-high[1m]'
```

#### Codex (CLIProxyAPI + OpenAI/ChatGPT)

Uses your existing OpenAI Codex/ChatGPT subscription tokens via [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI).

**Prerequisites:**

| Tool | Install |
|------|---------|
| Go 1.21+ | `brew install go` |
| jq | `brew install jq` |
| CLIProxyAPI source | `git clone https://github.com/router-for-me/CLIProxyAPI.git ~/Documents/dev/CLIProxyAPI` |
| Codex CLI auth | Sign in via `codex` CLI (creates `~/.codex/auth.json`) |

**Run Claude Code:**

```bash
# GPT models via CLIProxyAPI (codex is the default profile)
./bin/claude-proxy -m 'gpt-5.3-codex(high)'
```

### Available Profiles

| Profile | Backend | Port | Auth Token | Models |
|---------|---------|------|------------|--------|
| `codex` (default) | [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) | 8317 | `sk-dummy` | GPT / Codex |
| `antigravity` | [Antigravity Claude Proxy](https://github.com/badrisnarayanan/antigravity-claude-proxy) | 8081 | `test` | Claude / Gemini |
| `none` | (external) | 8317 | `sk-dummy` | Any (proxy must be pre-started) |

Port and auth token are per-profile defaults — override them with `--port` and `--api-key` if needed.

### CLI Reference

```
Usage:
  ./bin/claude-proxy [options] [--] [claude args...]

Options:
  -m, --model MODEL        Model string (validated per profile; uses profile default if omitted)
  -p, --profile PROFILE    Proxy profile: codex | antigravity | none (default: codex)
  --models                 List available models for the selected profile and exit
  --host HOST              Proxy bind address (default: 127.0.0.1)
  --port PORT              Proxy port (auto-set per profile if omitted)
  --api-key KEY            Proxy auth key (auto-set per profile if omitted)
  --no-start               Require proxy to be already running (skip auto-start)
  --no-validate            Skip model validation
  -h, --help               Show help
```

**Examples:**

```bash
# Use profile defaults (codex + gpt-5.3-codex(high))
./bin/claude-proxy

# Antigravity with default (claude-opus-4-5-thinking)
./bin/claude-proxy -p antigravity

# Codex with medium effort
./bin/claude-proxy -m 'gpt-5.3-codex(medium)'

# Antigravity with Gemini + 1M context
./bin/claude-proxy -p antigravity -m 'gemini-3-pro-high[1m]'

# List available models per profile
./bin/claude-proxy --models                   # codex models
./bin/claude-proxy -p antigravity --models    # antigravity models

# Use a proxy that's already running on a custom port
./bin/claude-proxy --no-start --port 3001 --no-validate -m 'custom-model'

# Pass extra arguments to Claude Code (after --)
./bin/claude-proxy -p antigravity -- --verbose

# Installed shell shortcut: proxy + allow switching to bypassPermissions
clp

# Installed shell shortcut: proxy + start directly in bypassPermissions
clp -a
```

### Creating Custom Profiles

Add support for any proxy backend by creating a start script:

1. Create `bin/proxy-start-<name>.sh` (must be executable)
2. The script receives environment variables: `HOST`, `PORT`, `API_KEY`, `MODEL`
3. The script should start the proxy in the foreground (the launcher handles backgrounding)

**Example:** Create a profile for a hypothetical `my-proxy` backend:

```bash
#!/usr/bin/env bash
set -euo pipefail

# bin/proxy-start-myproxy.sh
# Called by: ./bin/claude-proxy -p myproxy

PORT="${PORT:-9090}" exec my-proxy-server --port "${PORT}"
```

```bash
chmod +x bin/proxy-start-myproxy.sh
./bin/claude-proxy -p myproxy -m 'my-custom-model'
```

To set per-profile defaults (port, API key), add a case to the defaults block in `bin/claude-proxy`.

### Proxy Troubleshooting

<details>
<summary><strong>Proxy not reachable after startup</strong></summary>

Check the proxy log for errors:

```bash
cat ~/.cli-proxy-api/cli-proxy-api.log
```

Common causes:
- **Port conflict:** Another service is using the port. Override with `--port 8081`
- **Missing dependencies:** Codex profile requires `go` and `jq`; Antigravity requires `node` and `npx`
- **No auth configured:** Antigravity requires linking a Google account first (see Quick Start above)

</details>

<details>
<summary><strong>Antigravity shows "No accounts in config"</strong></summary>

The proxy is running but no Google account is linked. Open `http://localhost:8081`, go to **Accounts**, and click **Add Account** to complete OAuth.

</details>

<details>
<summary><strong>Codex profile fails to build</strong></summary>

The CLIProxyAPI source must be cloned locally:

```bash
git clone https://github.com/router-for-me/CLIProxyAPI.git ~/Documents/dev/CLIProxyAPI
```

You also need Go installed: `brew install go`

Override the source location:

```bash
CLI_PROXY_DIR=~/path/to/CLIProxyAPI ./bin/claude-proxy -m 'gpt-5.3-codex(high)'
```

</details>

<details>
<summary><strong>Running both profiles simultaneously</strong></summary>

Since each profile uses a different port, you can run them side-by-side:

```bash
# Terminal 1: Antigravity on :8081
./bin/claude-proxy -p antigravity -m 'claude-sonnet-4-5-thinking'

# Terminal 2: Codex on :8317
./bin/claude-proxy -m 'gpt-5.3-codex(high)'
```

</details>

<details>
<summary><strong>Environment variables vs. proxy launcher</strong></summary>

The proxy launcher is an alternative to manually setting environment variables. These two approaches are equivalent:

```bash
# Option A: Proxy launcher (recommended)
./bin/claude-proxy -p antigravity -m 'claude-sonnet-4-5-thinking'

# Option B: Manual environment variables
export ANTHROPIC_BASE_URL="http://localhost:8081"
export ANTHROPIC_AUTH_TOKEN="test"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-5-thinking"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-5-thinking"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-sonnet-4-5-thinking"
claude
```

The launcher adds auto-start and per-profile defaults so you don't have to remember ports and tokens.

</details>

---

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
 
## Branching Strategy (Trunk-Based / GitHub Flow)

This repository uses Trunk-Based Development (GitHub Flow 2026) with a single protected branch:

| Branch | Purpose | Protected |
|--------|---------|-----------|
| `main` | Production (single source of truth) | Yes (via GitHub Rulesets) |
| `feat/*` | New features | No |
| `fix/*` | Bug fixes | No |
| `hotfix/*` | Emergency fixes | No |

### Workflow

All branches merge directly to `main` via Pull Request (squash merge):

```
feat/*   ──► PR to main (squash merge)
fix/*    ──► PR to main (squash merge)
hotfix/* ──► PR to main (squash merge)
```

### Creating a Feature

```bash
git checkout main
git pull origin main              # Automatically rebases!
git checkout -b feat/my-feature
# ... make changes ...
git push -u origin feat/my-feature
# Create PR: feat/* → main
```

### Hotfix Flow

```bash
git checkout main
git pull origin main              # Automatically rebases!
git checkout -b hotfix/critical-bug
# ... fix the bug ...
git push -u origin hotfix/critical-bug
# Create PR: hotfix/* → main (expedited review)
```

### Why Trunk-Based?

- **Simpler**: One protected branch (`main`) vs two (`main` + `develop`)
- **Faster**: Direct to production, no integration bottleneck
- **Modern**: Industry standard for 2026 (GitHub, GitLab, Vercel)
- **CI/CD friendly**: Every merge to `main` can trigger deployment

> **Note**: For GitFlow templates (legacy), see `branch_protection_rules/gitflow/`
 
## Testing and Portability

This repo installs onto other people's machines, so nothing shipped may depend on one developer's paths, shell, package manager, or OS version. Two things enforce that: a cross-platform CI matrix, and a set of static portability guards in the test suite.

### Test lanes

| Command | What it runs | Typical time |
|---|---|---|
| `make unit` | Fast, hermetic — stubbed boundaries, no network | ~20s |
| `make integration` | Drives real scripts end to end, still offline | ~35s |
| `make smoke` | Runs `setup.sh` itself against a throwaway `HOME` | ~5s |
| `make test` | Everything (the merge gate) | ~45s |
| `make check` | `lint` + `format-check` + `test` | ~50s |
| `make verify-clean-machine` | The whole suite as CI sees it | ~60s |

**Run `make verify-clean-machine` before pushing.** A developer machine lies in
two ways CI does not: `~/.claude` is already installed, so tests that read it
pass for the wrong reason; and Homebrew bash sits ahead of `/bin/bash` on
`PATH`, so `env bash` finds 5.x while the macOS runner finds 3.2.57. That
target removes both — empty `HOME`, system bash first — and is the difference
between catching a portability break locally and finding it in CI.

Lanes are bats tag filters (`--filter-tags`), so a test belongs to a lane by its `# bats test_tags=` or file-level `# bats file_tags=` directive.

Tests run in parallel via `bats --jobs` when GNU parallel is installed (`make install-tools` gets it). Without it the suite still runs, just serially — the Makefile probes and degrades rather than failing.

### Hermetic by default

`tests/helpers.bash` provides the harness:

- `isolate_home` — points `HOME` and the `XDG_*` variables at the per-test tmpdir. Without it a test reads the developer's real `~/.claude`, so results depend on personal state and anything that scans it pays for gigabytes of real session history.
- `stub_bin <name> [body]` — puts a fake executable ahead of the real one on `PATH`.
- `stub_slow_bin <name> <seconds>` — a stub that hangs, for exercising timeout paths.
- `require_cmd <cmd>` — skip when a prerequisite is missing.

Call `isolate_home` first in `setup()`. A test that shells out to a real binary should stub it unless the point of the test is that binary.

### Portability guards

`tests/portability.bats` fails the build on machine-specific assumptions:

- hardcoded `/Users/...` or `/home/...` paths
- a brew prefix named without its alternatives (`/opt/homebrew` is Apple-Silicon-only)
- `$HOME/.config` written without an `XDG_CONFIG_HOME` fallback
- `[^\n]` inside a `sed` expression — BSD sed reads it as "not backslash and not the letter n", GNU sed as "not newline", so it silently behaves differently per platform
- GNU-only flags (`stat -c`, `date -d`) with neither a platform branch nor a BSD fallback
- shebangs that hardcode an interpreter path instead of using `env`
- an active absolute `command =` in a shipped Ghostty preset
- `stat -f … || stat -c …`, which reads as a BSD-then-GNU fallback but is not: on GNU coreutils `-f` means `--file-system`, so the first call *succeeds* and the `||` never fires
- `date -r <epoch>`, which formats that epoch on BSD but reads a *file's* mtime on GNU
- a personal directory convention (`~/Documents/dev`, `~/src`) used as a default rather than inside a probe list
- `PLATFORM` pinned to a literal in a test, which forces the wrong `stat`/`date` branch on every other OS
- a GitHub Action referenced by tag instead of a full commit SHA

### bash version

`setup.sh` needs bash >= 4.3 for the namerefs (`local -n`) the interactive TUI uses. macOS ships bash 3.2.57 as `/bin/bash` and cannot ship newer for licensing reasons, so `#!/usr/bin/env bash` lands on 3.2 whenever no newer bash is ahead of it on `PATH`. `bash -n` does not catch this — nameref rejection is a runtime error, so the script parses cleanly and then dies at the first prompt.

A guard at the top of `setup.sh` re-execs into a newer bash when one exists, and otherwise exits with an actionable message. Both paths are covered by tests.

### CI

`.github/workflows/ci.yml` runs lint and format on Ubuntu, then all three lanes on **both** `ubuntu-latest` and `macos-latest`. `fail-fast: false` so a macOS-only failure is never masked by cancelling on the Linux result — the cross-platform signal is the whole point of the matrix.

Every action is pinned to a full commit SHA. A tag is mutable: when `tj-actions/changed-files` was compromised in 2025, the attacker moved 350+ tags to a malicious commit and every repository pinned by tag executed it with access to the runner.

Tests that shell out over the network (`npx -y …`) probe once per suite and **skip** when the registry is unreachable, rather than failing. A flaky gate is worse than no gate — people learn to re-run it instead of reading it.

## Official Documentation
 
This configuration follows the official Claude Code documentation:
 
- [Claude Code Settings](https://code.claude.com/docs/en/settings) - Configuration scopes and file locations
- [MCP Servers](https://code.claude.com/docs/en/mcp) - Adding and configuring MCP integrations
- [Subagents](https://code.claude.com/docs/en/sub-agents) - Defining specialized agents
- [Skills](https://code.claude.com/docs/en/skills) - Creating reusable skills and slash commands
- [Common Workflows](https://code.claude.com/docs/en/common-workflows) - Best practices and examples
 
## License
 
MIT License - Feel free to use and modify for your own projects.