# Git Branching Strategies & GitHub Rulesets Guide (2026)

This guide covers the two main branching strategies used in 2026, their GitHub Ruleset configurations, and step-by-step implementation instructions.

## Table of Contents

1. [Overview: GitFlow vs GitHub Flow](#overview-gitflow-vs-github-flow)
2. [GitFlow Strategy](#gitflow-strategy-feature--develop--main)
3. [GitHub Flow Strategy](#github-flow-strategy-feature--main)
4. [Comparison Matrix](#comparison-matrix)
5. [GitHub Ruleset Configurations](#github-ruleset-configurations)
6. [Implementation Guide](#implementation-guide)
7. [Troubleshooting Common Issues](#troubleshooting-common-issues)
8. [Sources](#sources)

---

## Overview: GitFlow vs GitHub Flow

### Industry Trends (2026)

| Workflow | Adoption | Best For |
|----------|----------|----------|
| **GitHub Flow** | Increasing | Startups, SaaS, continuous deployment |
| **Trunk-Based** | Increasing | Big tech, fast-moving teams |
| **GitFlow** | Stable/Decreasing | Enterprise, regulated industries, versioned releases |

### Quick Comparison

```
GitFlow (Traditional):
feature/* ──► develop ──► main
                │           │
                └───────────┘ (sync after release)

GitHub Flow (Modern):
feature/* ──► main
              │
              └──► Deploy immediately
```

---

## GitFlow Strategy (feature → develop → main)

### When to Use GitFlow

- Large teams with multiple developers
- Scheduled release cycles (v1.0, v2.0, etc.)
- Regulated industries requiring audit trails
- Multiple production versions requiring support
- Complex projects with long development cycles

### Branch Structure

| Branch | Purpose | Lifetime | Protection |
|--------|---------|----------|------------|
| `main` | Production releases | Permanent | High |
| `develop` | Integration/staging | Permanent | Medium |
| `feature/*` | New features | Temporary | None |
| `release/*` | Release preparation | Temporary | Low |
| `hotfix/*` | Emergency fixes | Temporary | None |

### Workflow Diagram

```
main:     ●───────────────────●─────────────────●──────►
          │                   ▲                 ▲
          │                   │ merge           │ merge
          │                   │                 │
develop:  ●───●───●───●───●───●───●───●───●─────●──────►
          │   ▲   ▲   ▲       │       ▲
          │   │   │   │       │       │
feature:  └───┴───┘   │       │       │
                squash│       │       │
                      │       │       │
release:              └───────┘       │
                                      │
hotfix:                               └─► (also merge to develop)
```

### Merge Strategies

| Merge Path | Strategy | Why |
|------------|----------|-----|
| feature → develop | **Squash** | Clean history, 1 commit per feature |
| develop → main | **Merge commit** | Preserves release history |
| hotfix → main | **Merge commit** | Preserves emergency fix context |
| main → develop | **Merge commit** | Syncs production fixes back |

### Step-by-Step Workflow

#### Feature Development

```bash
# 1. Start from develop
git checkout develop
git pull origin develop

# 2. Create feature branch
git checkout -b feature/my-feature

# 3. Work on feature
# ... make changes ...
git add -A
git commit -m "feat: add new feature"

# 4. Push and create PR
git push -u origin feature/my-feature
gh pr create --base develop --head feature/my-feature

# 5. On GitHub: Squash and merge
```

#### Release to Production

```bash
# 1. Ensure develop is ready
git checkout develop
git pull origin develop

# 2. Create PR from develop to main
gh pr create --base main --head develop --title "chore: release v1.2.0"

# 3. On GitHub: Create a merge commit (NOT squash!)

# 4. After merge, sync develop with main
git checkout develop
git pull origin develop
git merge origin/main
git push origin develop
```

#### Hotfix Workflow

```bash
# 1. Create hotfix from main
git checkout main
git pull origin main
git checkout -b hotfix/critical-bug

# 2. Fix the bug
git commit -m "fix: critical security issue"
git push -u origin hotfix/critical-bug

# 3. PR to main first
gh pr create --base main --head hotfix/critical-bug

# 4. After merge to main, sync to develop
git checkout develop
git pull origin develop
git merge origin/main
git push origin develop
```

---

## GitHub Flow Strategy (feature → main)

### When to Use GitHub Flow

- Small to medium teams
- Continuous deployment
- SaaS applications
- Projects that deploy multiple times per day
- Simpler projects without complex release cycles

### Branch Structure

| Branch | Purpose | Lifetime | Protection |
|--------|---------|----------|------------|
| `main` | Production (always deployable) | Permanent | High |
| `feature/*` | All changes | Temporary | None |

### Workflow Diagram

```
main:     ●───●───●───●───●───●───●───●───●───●──────►
              ▲   ▲   ▲   ▲   ▲   ▲
              │   │   │   │   │   │
feature:  ────┴───┴───┴───┴───┴───┴──── (squash merges)
```

### Merge Strategy

| Merge Path | Strategy | Why |
|------------|----------|-----|
| feature → main | **Squash** | Clean linear history |

### Step-by-Step Workflow

```bash
# 1. Start from main
git checkout main
git pull origin main

# 2. Create feature branch
git checkout -b feature/my-feature

# 3. Work on feature
# ... make changes ...
git add -A
git commit -m "feat: add new feature"

# 4. Push and create PR
git push -u origin feature/my-feature
gh pr create --base main --head feature/my-feature

# 5. On GitHub: Squash and merge

# 6. Deploy (automatic or manual)
```

### Hotfix in GitHub Flow

In GitHub Flow, hotfixes are just regular features with high priority:

```bash
git checkout main
git pull origin main
git checkout -b fix/critical-bug
# ... fix ...
git push -u origin fix/critical-bug
gh pr create --base main  # Mark as urgent, fast-track review
# Squash and merge, deploy immediately
```

---

## Comparison Matrix

| Aspect | GitFlow | GitHub Flow |
|--------|---------|-------------|
| **Complexity** | High | Low |
| **Branches** | 5 types | 2 types |
| **Release cycle** | Scheduled | Continuous |
| **Deploy frequency** | Weekly/Monthly | Daily/Hourly |
| **Merge conflicts** | More likely | Less likely |
| **Learning curve** | Steep | Gentle |
| **Best for** | Enterprise, regulated | Startups, SaaS |
| **Linear history** | No (merge commits) | Yes (squash) |
| **Rollback ease** | Complex | Simple |

---

## GitHub Ruleset Configurations

### GitFlow Rulesets

#### `develop` Branch Ruleset

```yaml
Name: develop-branch-protection
Enforcement: Active
Target: develop

Rules:
  Restrict deletions: ON
  Block force pushes: ON
  Require linear history: OFF          # IMPORTANT: Allows merges from main

  Require pull request:
    Required approvals: 1-2
    Dismiss stale approvals: ON
    Require code owner review: OFF

  Require status checks:
    Strict mode: OFF                    # Loose - faster iteration
    Required checks:
      - build
      - test

Allowed merge methods:
  - Squash: ON                          # For features
  - Merge: ON                           # For syncing from main
  - Rebase: OFF
```

#### `main` Branch Ruleset

```yaml
Name: main-branch-protection
Enforcement: Active
Target: main

Rules:
  Restrict deletions: ON
  Block force pushes: ON
  Require linear history: OFF           # IMPORTANT: Allows merges from develop

  Require pull request:
    Required approvals: 1-2
    Dismiss stale approvals: ON
    Require code owner review: ON       # Recommended for main

  Require status checks:
    Strict mode: ON                     # Must be up-to-date
    Required checks:
      - build
      - test
      - security-scan                   # Optional

  Require signed commits: OPTIONAL      # If team uses GPG

Allowed merge methods:
  - Squash: OFF
  - Merge: ON                           # For releases from develop
  - Rebase: OFF
```

### GitHub Flow Ruleset

#### `main` Branch Ruleset

```yaml
Name: main-branch-protection
Enforcement: Active
Target: main

Rules:
  Restrict deletions: ON
  Block force pushes: ON
  Require linear history: ON            # Clean linear history

  Require pull request:
    Required approvals: 1-2
    Dismiss stale approvals: ON
    Require code owner review: ON

  Require status checks:
    Strict mode: ON
    Required checks:
      - build
      - test
      - lint

  Require deployments: OPTIONAL         # Auto-deploy after merge

Allowed merge methods:
  - Squash: ON                          # Only squash allowed
  - Merge: OFF
  - Rebase: OFF
```

---

## Implementation Guide

### Migrating from GitFlow to GitHub Flow

If you decide to switch from GitFlow to GitHub Flow:

```bash
# 1. Ensure develop and main are in sync
git checkout main
git pull origin main
git checkout develop
git pull origin develop
git diff main develop  # Should show no differences for clean migration

# 2. Delete develop branch (after ensuring everything is merged)
git branch -d develop
git push origin --delete develop

# 3. Update branch protection
# - Delete develop ruleset
# - Update main ruleset to allow squash merges
# - Enable "Require linear history" on main

# 4. Update documentation
# - Remove references to develop branch
# - Update PR base branch defaults
```

### Setting Up GitFlow from Scratch

```bash
# 1. Create develop branch from main
git checkout main
git pull origin main
git checkout -b develop
git push -u origin develop

# 2. Configure GitHub Rulesets
# - Create develop ruleset (see above)
# - Create main ruleset (see above)

# 3. Set default branch (optional)
# GitHub Settings > General > Default branch > develop

# 4. Update PR templates
# - Set default base branch to develop
```

### Configuring GitHub Rulesets (Step-by-Step)

1. **Navigate to Repository Settings**
   ```
   Repository > Settings > Rules > Rulesets
   ```

2. **Create New Ruleset**
   - Click "New ruleset" > "New branch ruleset"
   - Name it (e.g., "main-branch-protection")

3. **Set Target Branches**
   - Under "Target branches", click "Add target"
   - Select "Include by pattern" and enter branch name (e.g., `main`)

4. **Configure Rules**
   - Check/uncheck rules as specified above
   - For "Allowed merge methods", scroll to find this setting

5. **Set Enforcement**
   - For testing: Set to "Evaluate" first
   - For production: Set to "Active"

6. **Add Bypass List (Optional)**
   - Add repository admins or specific teams for emergency access

7. **Save Ruleset**

---

## Troubleshooting Common Issues

### Issue: Merge Conflicts When Syncing develop ↔ main

**Cause:** Using squash merges for develop → main creates different commit hashes.

**Solution:** Use merge commits (not squash) for develop → main.

### Issue: "Require linear history" Blocking Merges

**Cause:** Merge commits are not allowed when linear history is required.

**Solution:**
- GitFlow: Disable "Require linear history" on both branches
- GitHub Flow: Keep it enabled, use only squash merges

### Issue: Force Push Rejected

**Cause:** Branch protection blocks force pushes.

**Solution:**
- Temporary: Add yourself to bypass list, disable ruleset, push, re-enable
- Permanent: Use `git revert` instead of force push

### Issue: Stale PR Approvals

**Cause:** New commits invalidate previous approvals.

**Solution:** This is intentional for security. Get re-approval after changes.

---

## Quick Reference Card

### GitFlow Commands

```bash
# New feature
git checkout develop && git pull
git checkout -b feature/name
# ... work ...
gh pr create --base develop        # Squash merge

# Release
gh pr create --base main --head develop  # Merge commit

# Sync after release
git checkout develop && git merge origin/main && git push

# Hotfix
git checkout main && git pull
git checkout -b hotfix/name
# ... fix ...
gh pr create --base main           # Merge commit
# Then sync: develop merge main
```

### GitHub Flow Commands

```bash
# Any change
git checkout main && git pull
git checkout -b feature/name
# ... work ...
gh pr create --base main           # Squash merge
# Auto-deploy
```

---

## Recommendation for This Repository

Based on the analysis of this `claude-code-config` repository:

### Current State
- Uses GitFlow (feature → develop → main)
- Has `enforce-git-pull-rebase.sh` hook for clean pulls
- PR command defaults to `develop` as base branch

### Recommendation

**Keep GitFlow** for this repository because:
1. It's a configuration repository with versioned releases
2. The existing tooling (hooks, commands) is built around GitFlow
3. It serves as a reference implementation for GitFlow

### Required Ruleset Settings

| Branch | Linear History | Merge Methods |
|--------|----------------|---------------|
| `develop` | OFF | Squash + Merge |
| `main` | OFF | Merge only |

---

## Sources

1. [GitHub Docs - About Rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
2. [GitHub Well-Architected - Rulesets Best Practices](https://wellarchitected.github.com/library/governance/recommendations/managing-repositories-at-scale/rulesets-best-practices/)
3. [AWS Prescriptive Guidance - GitFlow Branches](https://docs.aws.amazon.com/prescriptive-guidance/latest/choosing-git-branch-approach/branches-in-a-gitflow-strategy.html)
4. [OpenSSF Best Practices - Linear History](https://best.openssf.org/SCM-BestPractices/github/repository/non_linear_history.html)
5. [GitHub Docs - About Merge Methods](https://docs.github.com/articles/about-merge-methods-on-github)
6. [Mergify - Trunk-Based vs GitFlow](https://mergify.com/blog/trunk-based-development-vs-gitflow-which-branching-model-actually-works)
7. [GitFlow Original Article - Vincent Driessen](https://nvie.com/posts/a-successful-git-branching-model/)

---

*Last updated: January 2026*
