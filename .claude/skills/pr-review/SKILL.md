---
name: pr-review
description: Multi-agent PR review that spawns parallel domain-specific subagents (python-expert, rust-expert, dbt-expert, dotnet-expert, kedro-expert, d2-tala-expert, ui-designer) based on changed file types, posts inline review comments on GitHub, GitLab, and Azure DevOps.
disable-model-invocation: true
argument-hint: "[PR-number]"
---

# PR Review Orchestrator

You are orchestrating a multi-agent code review. You MUST spawn parallel domain-specific subagents to review the PR, then collect their findings and post inline review comments.

## Pre-fetched Context

- **Remote URL**: !`git remote get-url origin 2>/dev/null`
- **PR metadata**: !`gh pr view $ARGUMENTS --json number,title,baseRefName,headRefName,headRefOid,url 2>/dev/null || glab mr view $ARGUMENTS --output json 2>/dev/null || echo "FETCH_FAILED: Manually detect platform and fetch PR metadata"`
- **Changed files**: !`gh pr diff $ARGUMENTS --name-only 2>/dev/null || glab mr diff $ARGUMENTS --name-only 2>/dev/null || echo "FETCH_FAILED: Manually fetch changed file list"`

If any pre-fetch shows `FETCH_FAILED`, detect the platform from the remote URL and fetch manually:
- **GitHub**: `gh pr view <number> --json number,title,baseRefName,headRefName,headRefOid,url`
- **GitLab**: `glab mr view <number> --output json`
- **Azure DevOps**: `az repos pr show --id <number>`

## Process

### Step 1: Fetch the Full Diff

```bash
# GitHub
gh pr diff <number>

# GitLab
glab mr diff <number>

# Azure DevOps
git diff origin/<target-branch>...HEAD
```

You need the full diff to extract relevant sections for each subagent.

### Step 2: Route Files to Expert Subagents

Map each changed file to the appropriate expert using the routing table in [routing.md](routing.md).

### Step 3: Spawn Parallel Subagents

**CRITICAL: You MUST spawn ALL matched expert subagents in a SINGLE message with multiple Agent tool calls. Use `run_in_background: true` for each one.** This is the core value of this skill — parallel multi-agent review, exactly like `/simplify` spawns 3 agents in parallel.

For each matched expert, use this prompt template:

```
Review the following files from PR #<number> for code quality, security,
performance, and adherence to best practices.

PR title: <title>
PR branch: <head> -> <base>

Changed files in your domain:
- path/to/file1.ext (modified)
- path/to/file2.ext (new file)

Full diff for these files:
<paste ONLY the diff sections for files in this expert's domain>

Return your findings as a structured list. For EACH issue use this EXACT format:

---
FILE: path/to/file.ext
LINE: <line number in the NEW file>
SEVERITY: critical | warning | suggestion
FINDING: Brief description of the issue
RECOMMENDATION: How to fix it
---

If no issues found, state "No issues found" explicitly.
Do NOT modify any files — this is a read-only review.
```

**Rules:**
- Spawn the correct `subagent_type` for each expert (e.g., `python-expert`, `rust-expert`)
- Each subagent receives ONLY the diff sections for files in its domain
- Cap at **6 subagents maximum** per review
- If more than 6 experts are needed, merge the least-populated domains into self-review

### Step 4: Self-Review Unmatched Files

For files that don't match any expert agent, review them yourself using these checklists:

**Security:** No hardcoded secrets, proper input validation, no injection vectors
**Code Quality:** Clear naming, no duplication, proper error handling, single responsibility
**Performance:** No N+1 queries, appropriate data structures, no resource leaks
**Testing:** New code has tests, edge cases covered

Use the same structured findings format (FILE/LINE/SEVERITY/FINDING/RECOMMENDATION).

### Step 5: Collect Findings

Wait for ALL background subagents to complete. Then collect and classify all findings:

| Severity | Meaning | Example |
|----------|---------|---------|
| **critical** | Security vulnerability, data loss risk, broken logic | SQL injection, hardcoded secrets, null dereference |
| **warning** | Code smell, performance issue, missing validation | N+1 queries, no error handling, duplicated logic |
| **suggestion** | Style, readability, minor optimization | Naming, documentation, simplification |

**Determine the review verdict:**
- Any `critical` findings -> `REQUEST_CHANGES`
- Only `warning` + `suggestion` -> `COMMENT`
- No findings -> `APPROVE`

### Step 6: Show Summary to User

Before posting anything, show the user a complete review summary:

```markdown
## Code Review Summary

**PR**: #<number> — <title>
**Reviewed by**: pr-review (orchestrated multi-agent review)
**Experts consulted**: <list of experts spawned>

### Findings

| Severity | Count |
|----------|-------|
| Critical | N |
| Warning | N |
| Suggestion | N |

### By Domain

| Expert | Files Reviewed | Findings |
|--------|---------------|----------|
| python-expert | N files | N warnings, N suggestions |
| self-review | N files | N suggestions |

### Verdict: **<verdict>**
```

### Step 7: Post Review (After User Confirmation)

**IMPORTANT:** Ask the user for confirmation before posting. Especially for `REQUEST_CHANGES`.

See [platforms.md](platforms.md) for the platform-specific API calls to post inline review comments.

**Always:**
- Pin comments to the exact commit SHA
- Post all comments as a single atomic review (GitHub batch review) when possible
- Include the summary as the review body

## Safety Boundaries

- **Read-only**: Do NOT modify any source code files
- **Confirm before posting**: Always show findings and ask before posting review comments
- **Confirm REQUEST_CHANGES**: Never post `REQUEST_CHANGES` without explicit user approval
- **Cap subagents**: Maximum 6 parallel subagents per review

## Additional Resources

- For file-to-expert routing rules, see [routing.md](routing.md)
- For platform-specific review posting APIs, see [platforms.md](platforms.md)
