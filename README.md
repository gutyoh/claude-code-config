# claude-code-config

[![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?logo=claude&logoColor=fff)](https://code.claude.com/docs)
[![macOS](https://img.shields.io/badge/macOS-000?logo=apple&logoColor=fff)](#platform-support)
[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=000)](#platform-support)
[![Windows](https://img.shields.io/badge/Windows-0078D4?logo=windows&logoColor=fff)](#platform-support)

A portable Claude Code setup in one Git repository: subagents, skills, hooks, a
status line and a few command-line tools. One script links it into `~/.claude`
on macOS, Linux and Windows, so every project on every machine gets the same
configuration, and a `git pull` updates them all.

```text
opus-5.5 | 32%/72% (39h12m) | 2h13m | 1.6k/68.1k/72.3M | $19.51 | user@example.com
```

## What you get

| | What it is |
|---|---|
| **[Subagents](#subagents-and-skills)** | Experts for Python, Rust, .NET, SQL, dbt, Databricks, MongoDB, design docs and more, most with a standards skill they load |
| **[Skills](#subagents-and-skills)** | Engineering standards, web search (built-in, Brave, Tavily) and pull request workflows for GitHub, GitLab and Azure DevOps |
| **[Hooks](docs/hooks.md)** | Session names, `git pull --rebase`, IDE diagnostics, a database guardrail, and API key guards for the search servers |
| **[Status line](docs/how-to-configure-statusline.md)** | Model, 5-hour and weekly usage, reset times, tokens, cost and service status, sized to the terminal |
| **[MCP search](docs/how-to-add-mcp-server.md)** | Brave Search and Tavily, with key pools that rotate when one runs out of quota |
| **[Full-page reading](docs/how-to-read-full-pages.md)** | `/full-search` reads JavaScript pages and PDFs through Firecrawl, Tavily or Bright Data, keys and fnox optional |
| **Command-line tools** | [`claude-as`](docs/how-to-use-multiple-accounts.md) for several accounts, [`claude-permissions-audit`](docs/how-to-audit-permissions.md), [`claude-proxy`](docs/how-to-use-the-proxy-launcher.md), `mcp-key-rotate` and `mcp-env-inject` |
| **Shell and terminal presets** | Optional [fish](docs/how-to-configure-fish.md) and [Ghostty](docs/how-to-configure-ghostty.md) configurations |

When [OpenCode](https://opencode.ai) is on your PATH, setup installs the same
agents for it too.

## Quick start

You need [Claude Code](https://code.claude.com/docs/en/setup), Git and `jq`,
plus `python3` on macOS and Linux. `fd` and `fzf` (faster `@` file search) and
`ccusage` (token and cost figures in the status line) are optional.

**1. Clone and install**

Fork this repository, so your own changes have somewhere to go, and clone the fork:

```bash
git clone https://github.com/<you>/claude-code-config.git
cd claude-code-config
./setup.sh          # macOS, Linux, WSL
```

```powershell
.\setup.ps1         # Windows PowerShell 5.1 or PowerShell 7, no Administrator needed
```

Setup links each agent, skill, hook and script into `~/.claude` (or
`$CLAUDE_CONFIG_DIR`), merges its entries into your `settings.json`, registers
the search servers and adds `bin/` to your PATH. Entries other tools installed
there are left alone. Run it again at any time; `./setup.sh --help` lists every
option.

**2. Add your search API keys** (free tiers: [Brave Search](https://api-dashboard.search.brave.com/), [Tavily](https://tavily.com))

```bash
echo 'BRAVE_API_KEY=your-key' >> ~/.claude/mcp-keys.env
echo 'TAVILY_API_KEY=your-key' >> ~/.claude/mcp-keys.env
```

```powershell
Add-Content "$HOME\.claude\mcp-keys.env" 'BRAVE_API_KEY=your-key', 'TAVILY_API_KEY=your-key'
```

Without keys everything else works, and `/web-search` uses Claude's built-in search.

**3. Check it**

```bash
claude mcp list     # brave-search and tavily, user scope
claude              # then /agents lists the subagents
```

[Getting started](docs/getting-started.md) walks through the same steps with
the output to expect at each one.

## Platform support

| | macOS | Linux | Windows |
|---|---|---|---|
| Installer | `setup.sh` | `setup.sh` | `setup.ps1` |
| Hooks and status line | bash 3.2 or later | bash | Git Bash, from [Git for Windows](https://gitforwindows.org/) |
| fish and Ghostty presets | Yes | Yes | No |
| Tested in CI | Installer, hooks, status line | Installer, hooks, status line | Installer on x64 and arm64; status line under Git Bash |

On Windows without Developer Mode, folders are linked as junctions and files
are copied, so run `setup.ps1` again after each pull. WSL uses `setup.sh`.

## Highlights

**Status line.** Usage comes from the plan behind the session's model: Claude's,
or the ChatGPT or Muse Code plan when a router runs a GPT or Muse model.
Components, progress bars, icons and colors are configurable, and the line
shortens to fit narrow terminals. Sessions on the same account show the newest
reading any of them has seen.
[Configure it](docs/how-to-configure-statusline.md).

**Several accounts.** `claude-as` keeps more than one Claude account signed in
and picks one per session; a session started on one continues on another.

```bash
claude-as --add you@example.com          # once per account and machine
claude-as you@example.com --continue
```

**Session names.** Each session is named once, at its first prompt, as
`claude-20261012T1412Z-btree-page-splits-0ed0b890`: the name `--resume` and
Remote Control find it by. [Details](docs/configuration.md#session-names).

**Database guardrail.** The `sql-expert`, `databricks-expert` and
`mongodb-expert` agents cannot drop a database or delete without a filter;
`databricks-expert` is read-only. [Levels](docs/hooks.md#database-guardrail).

**Permission audit.** `claude-permissions-audit` finds allow rules that permit
more than they look like they do, or that saved a password in plain text;
`--fix` backs the file up and removes them. [How to](docs/how-to-audit-permissions.md).

**Other models.** `claude-proxy` (shortcut `clp`) starts a local proxy and runs
Claude Code against OpenAI Codex or Antigravity models.
[How to](docs/how-to-use-the-proxy-launcher.md).

## Subagents and skills

<details>
<summary><strong>Subagents</strong> (<code>.claude/agents/</code>)</summary>

| Agent | For |
|---|---|
| `code-reviewer-expert` | Reviews a pull request with one expert per language and posts inline comments |
| `d2-tala-expert` | Architecture diagrams in D2 with the TALA layout engine |
| `data-scientist` | Machine learning, statistics and feature engineering |
| `databricks-expert` | Read-only Databricks: queries, Unity Catalog, permission audits, jobs |
| `dbt-expert` | dbt models, sources, tests and macros |
| `design-doc-expert` | Design docs, DRI working docs and ADRs |
| `diataxis-expert` | Documentation organized by the Diátaxis framework |
| `dotnet-expert` | .NET and C# services and APIs |
| `internet-researcher` | Multi-source web research with sources compared |
| `kedro-expert` | Kedro pipelines, catalogs and deployment |
| `langfuse-expert` | Langfuse traces, prompts and sessions |
| `linus-torvalds` | Blunt engineering advice, on request |
| `mongodb-expert` | MongoDB queries, aggregations, schemas and indexes |
| `pr-manager` | Pull requests on GitHub, GitLab and Azure DevOps |
| `python-expert` | Typed, production Python |
| `rust-expert` | Idiomatic Rust |
| `sonarqube-fixer` | SonarQube and SonarLint issues, read from the server or the IDE |
| `sql-expert` | SQL across PostgreSQL, MySQL, SQL Server, SQLite, DuckDB and Oracle |
| `ui-designer` | Components, styling, design systems and accessibility |

</details>

<details>
<summary><strong>Skills</strong> (<code>.claude/skills/</code>)</summary>

| Skill | For |
|---|---|
| `web-search`, `brave-search`, `tavily-search` | One search with Claude's built-in tool, Brave Search or Tavily |
| `full-search` | Rendered page text, JavaScript and PDFs included, through Firecrawl, Tavily or Bright Data, no keys needed |
| `internet-research` | Research across Brave Search and Tavily |
| `pr`, `pr-writing` | Pull requests and commit messages in Conventional Commits |
| `pr-operations`, `pr-review` | Pull request operations and multi-agent review on GitHub, GitLab and Azure DevOps |
| `mcp-key-rotate` | Quota checks and key rotation for the search servers |
| `python-standards`, `rust-standards`, `dotnet-standards` | Language standards the matching agents load |
| `sql-standards`, `mongodb-standards`, `dbt-standards`, `databricks-standards`, `kedro-standards` | Data engineering standards |
| `design-doc-standards`, `diataxis-standards`, `d2-tala-standards` | Writing and diagram standards |
| `langfuse` | Langfuse observability |

`config-hooks` in the same folder is a plugin, not a skill: it carries the
[stop-nudge hook](docs/hooks.md#stop-nudge).

</details>

[Add an agent](docs/how-to-add-agent.md) · [Add a skill](docs/how-to-add-skill.md) · [Run skill evals](docs/how-to-run-evals.md)

## Documentation

| | |
|---|---|
| **Tutorial** | [Getting started](docs/getting-started.md) |
| **How-to guides** | [Configure the status line](docs/how-to-configure-statusline.md) · [Use multiple accounts](docs/how-to-use-multiple-accounts.md) · [Sync across machines](docs/how-to-sync-across-machines.md) · [Audit permission rules](docs/how-to-audit-permissions.md) · [Use the proxy launcher](docs/how-to-use-the-proxy-launcher.md) · [Add an MCP server](docs/how-to-add-mcp-server.md) · [Read full pages](docs/how-to-read-full-pages.md) · [Add an agent](docs/how-to-add-agent.md) · [Add a skill](docs/how-to-add-skill.md) · [Run skill evals](docs/how-to-run-evals.md) · [Configure fish](docs/how-to-configure-fish.md) · [Configure Ghostty](docs/how-to-configure-ghostty.md) |
| **Reference** | [Configuration](docs/configuration.md) · [Hooks](docs/hooks.md) · [Project structure](docs/project-structure.md) |
| **Explanation** | [Architecture](docs/architecture.md) · [Design decisions](docs/design-decisions.md) · [Testing and portability](docs/testing.md) · [Branching strategies](docs/branching-strategies.md) |

## Development

```bash
just install-tools          # the toolchain pinned in mise.toml, through mise
just check                  # the merge gate: lint, format, secret scan, bats, PowerShell
just verify-clean-machine   # the tests with an empty HOME and the system bash, as CI runs them
```

Shell code targets bash 3.2, the version macOS ships, and avoids GNU-only flags;
[Testing and portability](docs/testing.md) lists the guards that enforce it.
Branch from `main` and open a pull request; changes are squash-merged.

## License

MIT
