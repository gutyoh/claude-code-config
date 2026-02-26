# Claude Code Portable Configuration

This repository contains a portable Claude Code configuration with MCP servers, skills, agents, commands, and hooks.

## Project Overview

A Git-versioned, portable configuration for Claude Code that works across macOS, Linux, and Windows.

## Repository Structure

```
.
├── .mcp.json                    # MCP server configurations (portable)
├── bin/                                # Proxy launcher scripts
│   ├── claude-proxy                    # Single entry point for all proxy profiles
│   ├── proxy-start-codex.sh            # Profile: CLIProxyAPI + OpenAI Codex
│   └── proxy-start-antigravity.sh      # Profile: Antigravity (Google Cloud Code)
├── .claude/
│   ├── settings.json            # Claude Code settings with hooks
│   ├── hooks/                   # Git and workflow hooks
│   │   ├── enforce-git-pull-rebase.sh
│   │   ├── open-file-in-ide.sh
│   │   ├── rate-limit-brave-search.sh  # Rate limits Brave Search API calls
│   │   └── validate-readonly-sql.sh  # Blocks destructive SQL in databricks commands
│   ├── skills/                  # Reusable skills
│   │   ├── databricks-standards/
│   │   │   ├── SKILL.md
│   │   │   ├── core.md
│   │   │   ├── catalog-patterns.md
│   │   │   ├── sql-patterns.md
│   │   │   ├── operations-patterns.md
│   │   │   └── permissions-patterns.md
│   │   ├── internet-research/
│   │   │   └── SKILL.md
│   │   ├── kedro-standards/
│   │   │   ├── SKILL.md
│   │   │   ├── core.md
│   │   │   ├── catalog-patterns.md
│   │   │   ├── pipeline-patterns.md
│   │   │   ├── config-patterns.md
│   │   │   ├── testing-patterns.md
│   │   │   └── deployment-patterns.md
│   │   ├── d2-tala-standards/
│   │   │   ├── SKILL.md
│   │   │   ├── core.md
│   │   │   ├── layout-patterns.md
│   │   │   ├── style-patterns.md
│   │   │   ├── diagram-patterns.md
│   │   │   └── cli-patterns.md
│   │   ├── pr-operations/
│   │   │   └── SKILL.md
│   │   ├── pr-writing/
│   │   │   └── SKILL.md
│   │   └── python-standards/
│   │       ├── SKILL.md
│   │       ├── core.md
│   │       ├── async-patterns.md
│   │       ├── pydantic-patterns.md
│   │       ├── cli-patterns.md
│   │       ├── subprocess-patterns.md
│   │       └── logging-patterns.md
│   ├── agents/                  # Subagent definitions
│   │   ├── d2-tala-expert.md
│   │   ├── data-scientist.md
│   │   ├── databricks-expert.md
│   │   ├── internet-researcher.md
│   │   ├── kedro-expert.md
│   │   ├── pr-manager.md
│   │   ├── linus-torvalds.md
│   │   ├── python-expert.md
│   │   ├── sonarqube-fixer.md
│   │   └── ui-designer.md
│   ├── scripts/                 # Utility scripts
│   │   ├── file-suggestion.sh
│   │   ├── file-suggestion.ps1
│   │   ├── statusline.sh        # Entry point (sources lib/statusline/)
│   │   └── lib/statusline/      # Statusline modules
│   │       ├── config.sh        # load_config, load_theme
│   │       ├── utils.sh         # format_num, iso8601_to_epoch, format_duration_ms
│   │       ├── api.sh           # get_oauth_token, fetch_api_usage, get_api_session_data
│   │       ├── cache.sh         # get_file_age, refresh_api_cache, get_cached_api_data
│   │       ├── data.sh          # get_ccusage_block, calculate_time_remaining, collect_data
│   │       ├── bar.sh           # render_progress_bar, _overlay_pct_inside
│   │       ├── color.sh         # get_color_for_pct, get_utilization_color
│   │       ├── components.sh    # 14 render_component_* functions
│   │       └── assembly.sh      # render_all_components
│   └── commands/                # Custom slash commands
│       ├── web-search.md
│       ├── brave-search.md
│       ├── tavily-search.md
│       └── pr.md
├── branch_protection_rules/     # GitHub Ruleset templates
│   ├── trunk-based/             # GitHub Flow (current)
│   │   └── main-branch-protection.json
│   ├── gitflow/                 # Enterprise workflow (archived)
│   │   ├── main-branch-protection.json
│   │   └── develop-branch-protection.json
│   └── README.md
├── lib/
│   └── setup/                   # Setup modules (sourced by setup.sh)
│       ├── tui.sh               # tui_readkey, tui_select, tui_multiselect, tui_confirm
│       ├── preview.sh           # render_bar_preview, show_statusline_preview, show_preview_box
│       ├── filesystem.sh        # create_symlink, check_prerequisite
│       ├── settings.sh          # configure_ide_hook, configure_file_suggestion, configure_statusline, configure_agent_teams
│       ├── statusline-conf.sh   # configure_statusline_conf
│       ├── mcp.sh               # configure_mcp_servers
│       ├── cli.sh               # show_usage, parse_arguments
│       └── menu.sh              # show_install_menu, customize_installation
├── CLAUDE.md                    # This file (shared context)
└── README.md                    # User documentation
```

## Available Capabilities

### MCP Servers
- **brave-search**: Internet search via Brave Search API (web, image, video, news, local)
- **tavily**: AI-native search, extract, crawl, map, and research via Tavily API

### Skills
- **d2-tala-standards**: D2 diagramming standards with TALA layout engine for clean, professional architecture diagrams
- **databricks-standards**: Databricks engineering standards for safe, efficient workspace interaction via CLI
- **internet-research**: Expert internet research using Tavily and Brave Search (task-based routing)
- **kedro-standards**: Kedro engineering standards for building clean, modular, production-ready data pipelines (Kedro 1.0+)
- **pr-operations**: Cross-platform PR/MR operations for GitHub, GitLab, and Azure DevOps (platform detection, CLI commands, workflow detection)
- **pr-writing**: Expert PR and commit message writing following Conventional Commits
- **python-standards**: Python engineering standards for clean, type-safe, production-ready code (Python 3.12+)

### Agents
- **d2-tala-expert**: Expert D2 diagrammer with TALA layout engine for software architecture diagrams
- **data-scientist**: Expert data scientist for ML, deep learning, and statistical analysis
- **databricks-expert**: Expert Databricks engineer for querying data, exploring Unity Catalog, managing permissions, and monitoring jobs/pipelines
- **internet-researcher**: Deep research subagent for complex queries
- **kedro-expert**: Expert Kedro engineer for building data pipelines, managing catalogs, configuring environments, and deploying projects
- **linus-torvalds**: Stern software engineering mentor channeling Linus Torvalds for brutally honest technical advice, career guidance, and no-bullshit industry perspectives
- **pr-manager**: Expert PR/MR manager for full lifecycle (list, view, create, review, edit, close, reopen) with automatic workflow detection (GitFlow vs Trunk-based)
- **python-expert**: Expert Python engineer for clean, type-safe, production-ready code
- **sonarqube-fixer**: Expert SonarQube issue fixer for cognitive complexity, code smells, and security vulnerabilities
- **ui-designer**: Expert UI designer for components, styling, design systems, and accessibility

### Commands
- `/web-search <query>`: Quick search using Claude's built-in WebSearch tool
- `/tavily-search <query>`: AI-native search using Tavily MCP (requires `TAVILY_API_KEY`)
- `/brave-search <query>`: Search using Brave Search MCP (requires `BRAVE_API_KEY`)
- `/pr [base-branch]`: Create PR/MR with Conventional Commits formatting (GitHub/GitLab/Azure DevOps)

### Experimental Features
- **agent-teams**: Multi-session coordinated teams (lead + teammates with shared task list). Enabled by default in macOS/Linux `setup.sh`. Use `--no-agent-teams` to disable. Sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `~/.claude/settings.json` env.

### Hooks
- **enforce-git-pull-rebase**: Automatically adds `--rebase` to all `git pull` commands
- **ide-diagnostics-opener**: Automatically opens files in IDE before `mcp__ide__getDiagnostics` (fixes JetBrains timeout bug #3085)
- **rate-limit-brave-search**: Enforces rate limiting on Brave Search MCP calls (configurable via `BRAVE_API_RATE_LIMIT_MS`)
- **validate-readonly-sql**: Blocks destructive SQL operations (INSERT, UPDATE, DELETE, DROP, etc.) in databricks commands

## Environment Variables Required

Set these in your shell before running Claude Code:

```bash
export BRAVE_API_KEY="your-key-here"
export TAVILY_API_KEY="your-key-here"

# Optional: Brave Search rate limit (default: 1100ms for free tier)
# Set to 50 for paid plans (20 req/sec)
export BRAVE_API_RATE_LIMIT_MS="1100"
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
