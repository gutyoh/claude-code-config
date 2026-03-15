# Project Structure

Directory layout, module responsibilities, and file organization for claude-code-config.

## Top-level directory tree

```
claude-code-config/
├── .mcp.json                              # MCP server configurations (brave-search, tavily)
├── .env.example                           # Environment variable template
├── .envrc.example                         # direnv config template
├── .gitignore                             # Comprehensive gitignore (231 lines)
├── .gitattributes                         # Line endings, language stats, diff settings
├── .shellcheckrc                          # ShellCheck config (bash dialect, disabled rules)
├── CLAUDE.md                              # Project context (shared, checked into repo)
├── README.md                              # User documentation (1081 lines)
├── Makefile                               # Quality targets: lint, format, test, check, ci
├── setup.sh                               # Interactive setup for macOS/Linux (354 lines)
├── setup.ps1                              # Setup for Windows PowerShell (521 lines)
├── bin/                                   # Utility scripts (installed to PATH)
├── lib/                                   # Library modules (sourced by setup/proxy)
├── .claude/                               # Claude Code configuration
├── branch_protection_rules/               # GitHub Ruleset templates
├── tests/                                 # BATS test suite
├── docs/                                  # Documentation (this directory)
└── .github/workflows/                     # GitHub Actions
```

## bin/ — Utility scripts

| File | Purpose |
|------|---------|
| `claude-proxy` | Single entry point for all proxy profiles (494 lines) |
| `mcp-key-rotate` | API key rotation for MCP servers (554 lines) |
| `mcp-env-inject` | Wrapper injecting MCP keys from `~/.claude/mcp-keys.env` |
| `proxy-start-codex.sh` | Profile: CLIProxyAPI + OpenAI Codex |
| `proxy-start-antigravity.sh` | Profile: Antigravity (Google Cloud Code) |

## lib/ — Library modules

### lib/setup/

Sourced by `setup.sh`. Each module exports functions used during interactive setup.

| File | Functions | Purpose |
|------|-----------|---------|
| `tui.sh` | `tui_readkey`, `tui_select`, `tui_multiselect`, `tui_confirm` | Terminal UI widgets |
| `preview.sh` | `render_bar_preview`, `show_statusline_preview`, `show_preview_box` | Live statusline preview |
| `filesystem.sh` | `create_symlink`, `check_prerequisite` | Symlink creation with conflict handling |
| `settings.sh` | `configure_ide_hook`, `configure_file_suggestion`, `configure_statusline`, `configure_agent_teams`, `configure_proxy_path` | settings.json manipulation |
| `statusline-conf.sh` | `configure_statusline_conf` | `~/.claude/statusline.conf` management |
| `mcp.sh` | `mcp_get`, `detect_mcp_backend`, `configure_mcp_servers` | MCP server registration |
| `cli.sh` | `show_usage`, `parse_arguments` | CLI flag parsing (25+ flags) |
| `menu.sh` | `show_install_menu`, `customize_installation`, `customize_statusline_with_preview` | Interactive menus |

### lib/proxy/

| File | Purpose |
|------|---------|
| `preflight.sh` | Binary staleness detection, OAuth session verification, token freshness checks |

## .claude/ — Claude Code configuration

### .claude/hooks/

| File | Trigger | Matcher | Purpose |
|------|---------|---------|---------|
| `enforce-git-pull-rebase.sh` | PreToolUse | `Bash` | Adds `--rebase` to `git pull` commands |
| `open-file-in-ide.sh` | PreToolUse | `mcp__ide__getDiagnostics` | Opens file in IDE before diagnostics (13 IDEs) |
| `rate-limit-brave-search.sh` | PreToolUse | `mcp__brave-search__.*` | Filesystem mutex + sleep for rate limiting |
| `validate-readonly-sql.sh` | PreToolUse | `Bash` (agent-scoped) | Blocks destructive SQL in databricks commands |
| `refresh-usage-cache.sh` | PreToolUse + Stop | `.*` and `""` | Background Haiku API ping for usage data |

### .claude/scripts/

| File | Purpose |
|------|---------|
| `statusline.sh` | Entry point for statusline rendering (255 lines) |
| `file-suggestion.sh` | Fast file discovery for `@` mentions (macOS/Linux) |
| `file-suggestion.ps1` | Fast file discovery for `@` mentions (Windows) |

### .claude/scripts/lib/statusline/

| File | Functions | Purpose |
|------|-----------|---------|
| `config.sh` | `load_config`, `load_theme` | Config and theme loading |
| `utils.sh` | `format_num`, `iso8601_to_epoch`, `format_duration_ms` | Formatting utilities |
| `api.sh` | `get_oauth_token`, `fetch_api_usage`, `get_api_session_data` | OAuth credential retrieval and API calls |
| `cache.sh` | `get_file_age`, `try_acquire_lock`, `refresh_api_cache`, `get_cached_api_data` | API cache with locking, backoff, stale-while-error |
| `data.sh` | `get_ccusage_block`, `calculate_time_remaining`, `collect_data` | Data collection (3-tier priority chain) |
| `bar.sh` | `render_progress_bar`, `_overlay_pct_inside` | Progress bar rendering (6 styles) |
| `color.sh` | `get_color_for_pct`, `get_utilization_color`, `get_cc_status_color` | Color helpers |
| `status.sh` | `collect_service_status` | Claude Code service health (status.claude.com) |
| `components.sh` | 15 `render_component_*` functions | Individual component renderers |
| `assembly.sh` | `render_all_components` | Component joining with merge groups |

### .claude/skills/ (19 skills)

| Skill | Files | Purpose |
|-------|-------|---------|
| `brave-search` | 1 | Brave Search MCP slash command |
| `d2-tala-standards` | 6 | D2 + TALA diagramming standards |
| `databricks-standards` | 6 | Databricks engineering standards |
| `dbt-standards` | 8 | dbt engineering standards |
| `design-doc-standards` | 7 | Design doc + DRI working doc + ADR standards |
| `diataxis-standards` | 8 | Diataxis documentation framework |
| `dotnet-standards` | 10 | .NET/C# engineering standards |
| `internet-research` | 1 | Multi-source internet research |
| `kedro-standards` | 7 | Kedro pipeline standards |
| `langfuse` | 5 | Langfuse observability standards |
| `mcp-key-rotate` | 1 | MCP API key rotation command |
| `pr` | 1 | PR creation (Conventional Commits) |
| `pr-operations` | 1 | Cross-platform PR/MR operations |
| `pr-review` | 3 | Multi-agent PR review |
| `pr-writing` | 1 | PR and commit message writing |
| `python-standards` | 7 + refs + versions | Python engineering standards |
| `rust-standards` | 10 | Rust engineering standards |
| `tavily-search` | 1 | Tavily AI-native search command |
| `web-search` | 1 | Built-in web search command |

### .claude/agents/ (17 agents)

| Agent | Color | Skills | Hooks |
|-------|-------|--------|-------|
| `code-reviewer-expert` | blue | pr-operations | — |
| `d2-tala-expert` | blue | d2-tala-standards | — |
| `data-scientist` | purple | — | — |
| `databricks-expert` | red | databricks-standards | validate-readonly-sql |
| `dbt-expert` | orange | dbt-standards | — |
| `design-doc-expert` | yellow | design-doc-standards | — |
| `diataxis-expert` | pink | diataxis-standards | — |
| `dotnet-expert` | purple | dotnet-standards | — |
| `internet-researcher` | cyan | internet-research | — |
| `kedro-expert` | yellow | kedro-standards | — |
| `langfuse-expert` | cyan | langfuse | — |
| `linus-torvalds` | yellow | — | — |
| `pr-manager` | blue | pr-writing, pr-operations | — |
| `python-expert` | green | python-standards | — |
| `rust-expert` | orange | rust-standards | — |
| `sonarqube-fixer` | orange | — | — |
| `ui-designer` | pink | — | — |

## branch_protection_rules/

| File | Purpose |
|------|---------|
| `trunk-based/main-branch-protection.json` | GitHub Ruleset for trunk-based development |
| `gitflow/main-branch-protection.json` | GitHub Ruleset for GitFlow main branch |
| `gitflow/develop-branch-protection.json` | GitHub Ruleset for GitFlow develop branch |
| `README.md` | Strategy comparison and import instructions |

## tests/ — BATS test suite

| File | Tests |
|------|-------|
| `rate-limit-brave-search.bats` | Rate limiting hook |
| `statusline-utils.bats` | Statusline utility functions |
| `statusline-cache.bats` | API cache with locking and backoff |
| `mcp-key-rotate.bats` | Key rotation script |
| `mcp-env-inject.bats` | MCP environment injection |
| `mcp-env-inject-sync.bats` | Sync variant of env injection |
| `proxy-preflight.bats` | Proxy launcher preflight checks |
| `setup-cli.bats` | Setup CLI argument parsing |
| `langfuse-skill.bats` | Langfuse skill validation |
| `refresh-usage-cache.bats` | Usage cache refresh hook |
| `cc-status.bats` | Claude Code service status |

## .github/workflows/

| File | Purpose |
|------|---------|
| `claude.yml` | Claude Code action for @claude mentions in issues/PRs |
| `claude-code-review.yml` | Automated PR code review (currently disabled) |

## Entry points

| Entry Point | Command | Description |
|-------------|---------|-------------|
| Setup (macOS/Linux) | `./setup.sh` | Interactive TUI setup |
| Setup (Windows) | `.\setup.ps1` | PowerShell setup |
| Proxy launcher | `claude-proxy [options]` | Route Claude through proxy |
| Key rotation | `mcp-key-rotate <service> [action]` | Rotate MCP API keys |
| Lint | `make lint` | ShellCheck all scripts |
| Format | `make format` | shfmt all scripts |
| Test | `make test` | Run BATS test suite |
| CI | `make ci` | Full CI: format-check + lint + test |

## See also

- [Architecture](architecture.md): why the directory structure is organized this way
- [Configuration](configuration.md): full reference for all configuration files and environment variables
- [How to Add an Agent](how-to-add-agent.md): add a new agent to `.claude/agents/`
- [How to Add a Skill](how-to-add-skill.md): add a new skill to `.claude/skills/`
