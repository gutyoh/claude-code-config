# Design Decisions

Architecture Decision Records (ADRs) for the claude-code-config repository. Each records the context, decision, alternatives considered, and consequences.

## ADR-1: Symlinks over file copying

### Context

The configuration needs to be shared across all Claude Code projects on a machine. Two approaches exist: copy files into `~/.claude/`, or symlink from `~/.claude/` back to the Git repo.

### Decision

Use symlinks. The setup script creates `~/.claude/hooks → <repo>/.claude/hooks`, `~/.claude/skills → <repo>/.claude/skills`, etc.

### Alternatives considered

- **File copying**: copy `.claude/*` into `~/.claude/` during setup. Rejected because updates require re-running the copy. Git pull does not propagate changes automatically. Users forget to re-copy, leading to stale configs.
- **Git submodule in each project**: add claude-code-config as a submodule in every project. Rejected because it requires modification of every project repo. Submodule management adds friction.

### Consequences

- **Benefits**: `git pull` updates everything instantly. No re-installation. Config is always in sync across machines.
- **Trade-offs**: if the repo directory moves, symlinks break. The setup script handles this by detecting changed targets and re-creating symlinks. Users must keep the repo cloned.

## ADR-2: Agent + skill separation over monolithic agents

### Context

Domain experts (python-expert, databricks-expert, etc.) need both behavioral instructions (persona, process) and domain knowledge (patterns, rules, anti-patterns). All of this could go in a single agent file.

### Decision

Separate agents from skills. The agent file (`.claude/agents/X.md`) defines persona and process. The skill (`.claude/skills/X-standards/`) provides the actual knowledge via multiple files.

### Alternatives considered

- **Monolithic agent file**: put everything in one `.md` file per agent. Rejected because agent files would grow to 1000+ lines, exceeding Claude Code's recommended size. Conditional loading is impossible with a single file.
- **Skills without agents**: define only skills, let Claude decide when to use them. Rejected because skills lack the agent's behavioral instructions (process, persona) and can't define hooks or model overrides.

### Consequences

- **Benefits**: conditional loading keeps context lean. Skills are reusable across agents. Agent files stay short (40-60 lines). Skills can be tested and evolved independently.
- **Trade-offs**: two-component system is more complex than a single file. New contributors must understand both patterns.

## ADR-3: Conditional loading over loading everything

### Context

Skills like python-standards have 7+ pattern files. Loading all of them into every agent invocation wastes context window space. Most tasks only need 1-2 pattern files.

### Decision

Use a conditional loading table in SKILL.md. The `core.md` file always loads. Pattern files load based on the task type.

### Alternatives considered

- **Load everything**: always inject all pattern files into context. Rejected because context window is finite. Loading 7 files when only 1 is needed wastes tokens and increases latency.
- **Manual loading**: require the user to specify which patterns to load. Rejected because users don't know which patterns they need. The agent should decide based on the task.

### Consequences

- **Benefits**: context window efficiency. Faster responses. Agents load only what's relevant.
- **Trade-offs**: the conditional loading table in SKILL.md must be maintained. If a pattern file is missing from the table, it won't be discovered.

## ADR-4: Standalone hook scripts over inline settings

### Context

Claude Code hooks can be defined as inline commands in settings.json or as standalone scripts referenced by path.

### Decision

Use standalone bash scripts in `.claude/hooks/`. Settings.json references them by path.

### Alternatives considered

- **Inline commands**: put the hook logic directly in the `command` field of settings.json. Rejected because complex logic (JSON parsing, regex matching, conditional blocking) is unreadable as a single-line command. Can't be tested independently.

### Consequences

- **Benefits**: scripts are testable (BATS tests exist for hooks). Version-controlled with meaningful diffs. Reusable across projects. Support `set -euo pipefail` and proper error handling.
- **Trade-offs**: two files to maintain per hook (the script + the settings.json reference). File path must be correct.

## ADR-5: Trunk-based development over GitFlow

### Context

The repo needs a branching strategy. GitFlow (main + develop + feature branches) and trunk-based development (main + feature branches, squash merge) are the two main options.

### Decision

Trunk-based development (GitHub Flow). All feature/fix/hotfix branches merge directly to `main` via squash merge PR.

### Alternatives considered

- **GitFlow**: separate `develop` branch, feature branches merge to develop, then develop merges to main. Rejected because this repo has 1-2 contributors. The develop branch adds merge ceremony without value. GitFlow rulesets are preserved in `branch_protection_rules/gitflow/` for repos that need them.

### Consequences

- **Benefits**: simpler (one protected branch). Faster (no integration bottleneck). Modern industry standard. The `enforce-git-pull-rebase` hook ensures linear history.
- **Trade-offs**: no staging branch for pre-release validation. Acceptable for a config repo where every merge to main is immediately live.

## ADR-6: BATS for testing shell scripts

### Context

The repo is 100% shell scripts. Shell scripts are notoriously hard to test. Options include no tests, custom test harness, or an established framework.

### Decision

Use BATS (Bash Automated Testing System). 11 test files covering hooks, statusline, proxy, MCP rotation, and setup CLI.

### Alternatives considered

- **No tests**: accepted risk of manual verification. Rejected because the hook scripts handle security (SQL blocking), financial data (rate limiting), and authentication (OAuth tokens). Bugs in these areas have real consequences.
- **Custom test scripts**: write ad-hoc test scripts. Rejected because BATS provides `setup`/`teardown`, assertions, tap output, and CI integration out of the box.

### Consequences

- **Benefits**: regression protection for critical hooks. CI integration via `make test`. Confidence when refactoring.
- **Trade-offs**: BATS is a dependency (installed via npm/brew). Test files add maintenance overhead.

## ADR-7: Three-tier statusline data priority

### Context

The statusline needs real-time usage data (session percentage, weekly percentage). Three data sources exist: native Claude Code fields (future), hook cache (background Haiku API), and OAuth API.

### Decision

Three-tier priority chain. Try native fields first, fall back to hook cache, fall back to OAuth API with SWR caching.

### Alternatives considered

- **OAuth API only**: call the API every time the statusline renders. Rejected because statusline renders every few seconds. Rate limiting and latency would degrade the experience.
- **Hook cache only**: rely entirely on the background hook. Rejected because hooks may not fire frequently enough, and the cache has a staleness threshold (5 minutes).

### Consequences

- **Benefits**: resilience — if any data source fails, the next tier provides data. Performance — hook cache and native fields are instant (no API call). Future-proof — when Anthropic adds native rate limit fields, they take priority automatically.
- **Trade-offs**: complexity — three code paths for the same data. Stale data is prefixed with `~` to signal uncertainty.

## ADR-8: MCP key pools with rotation

### Context

Free-tier API keys have monthly quotas (Brave: $5 credits, Tavily: 1,000 credits). A single key can be exhausted mid-month, breaking search functionality.

### Decision

Support key pools (comma-separated list in `*_API_KEY_POOL`). The `mcp-key-rotate` script rotates to the next key, checks per-key quota, and supports adding new keys.

### Alternatives considered

- **Single key**: use one key, tell the user when it's exhausted. Rejected because it leaves users without search for the rest of the month. `/web-search` fallback exists but provides lower-quality results.
- **Paid plans**: upgrade to paid API plans. Rejected because this repo targets users with free-tier accounts. Paid plans eliminate the problem but not everyone has budget.

### Consequences

- **Benefits**: zero-downtime rotation. Per-key quota visibility. Pool can grow by adding keys with `--add`. Combined free credits across multiple keys.
- **Trade-offs**: key management complexity. Users must understand the pool concept. After rotation, Claude Code must be restarted for the new key to take effect (MCP servers cache env vars).

## See also

- [Architecture](architecture.md): how these decisions shaped the system design
- [Project Structure](project-structure.md): where each component lives in the repo
- [Configuration](configuration.md): the configuration surfaces created by these decisions
