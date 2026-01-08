# Branch Protection Setup Guide

This document provides recommended branch protection rules for this repository.

## TL;DR - My Recommendation

**Protect BOTH `main` and `develop`**, but with different strictness levels:

| Branch | Protection Level | Why |
|--------|------------------|-----|
| `main` | **Strict** | Production-ready code only |
| `develop` | **Moderate** | Integration testing, allows faster iteration |

## Setting Up Branch Protection (GitHub)

### Step 1: Go to Branch Protection Settings

1. Navigate to your repository on GitHub
2. Click **Settings** → **Branches** (under "Code and automation")
3. Click **Add branch protection rule**

---

### Step 2: Configure `main` Branch (Strict Protection)

**Branch name pattern:** `main`

#### Recommended Settings:

| Setting | Value | Reason |
|---------|-------|--------|
| **Require a pull request before merging** | ✅ Enabled | No direct pushes to main |
| ↳ Require approvals | 1 (or more for teams) | Code review requirement |
| ↳ Dismiss stale PR approvals when new commits are pushed | ✅ Enabled | Re-review after changes |
| ↳ Require review from code owners | Optional | If you have CODEOWNERS file |
| **Require status checks to pass before merging** | ✅ Enabled | CI must pass |
| ↳ Require branches to be up to date before merging | ✅ Enabled | Prevents merge conflicts |
| **Require conversation resolution before merging** | ✅ Enabled | All comments addressed |
| **Require signed commits** | Optional | Extra security |
| **Require linear history** | ✅ Recommended | Clean git history |
| **Do not allow bypassing the above settings** | ✅ Enabled | Even admins follow rules |
| **Restrict who can push to matching branches** | Optional | Limit to specific people |
| **Allow force pushes** | ❌ Disabled | Never force push to main |
| **Allow deletions** | ❌ Disabled | Cannot delete main |

---

### Step 3: Configure `develop` Branch (Moderate Protection)

**Branch name pattern:** `develop`

#### Recommended Settings:

| Setting | Value | Reason |
|---------|-------|--------|
| **Require a pull request before merging** | ✅ Enabled | No direct pushes |
| ↳ Require approvals | 0 or 1 | Faster iteration for solo/small teams |
| ↳ Dismiss stale PR approvals when new commits are pushed | Optional | Less strict than main |
| **Require status checks to pass before merging** | ✅ Enabled | CI must pass |
| ↳ Require branches to be up to date before merging | Optional | Can be disabled for speed |
| **Require conversation resolution before merging** | Optional | Less strict than main |
| **Require linear history** | Optional | Nice to have |
| **Allow force pushes** | ❌ Disabled | Still no force pushes |
| **Allow deletions** | ❌ Disabled | Cannot delete develop |

---

## Why Protect Both Branches?

### Protecting Only `main`

**Pros:**
- Simpler setup
- Faster development on `develop`
- Fine for solo developers

**Cons:**
- `develop` can get messy
- Direct pushes to `develop` bypass review
- Harder to track what's in `develop`

### Protecting Both `main` AND `develop` (Recommended)

**Pros:**
- All changes are tracked via PRs
- Clear audit trail
- Better for teams
- `develop` stays stable
- Forces good habits

**Cons:**
- Slightly more process overhead
- Need to create PRs even for small changes

### My Expert Recommendation

For a **solo developer or small team (1-3 people)**:
```
main:    Strict protection (require PR + approval)
develop: Light protection (require PR, no approval needed)
```

For a **larger team (4+ people)**:
```
main:    Strict protection (require PR + 2 approvals)
develop: Moderate protection (require PR + 1 approval)
```

---

## GitHub CLI Commands (Alternative to UI)

If you prefer CLI:

```bash
# Protect main branch
gh api repos/{owner}/{repo}/branches/main/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  -f required_status_checks='{"strict":true,"contexts":[]}' \
  -f enforce_admins=true \
  -f required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false

# Protect develop branch (lighter)
gh api repos/{owner}/{repo}/branches/develop/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  -f required_status_checks='{"strict":false,"contexts":[]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"required_approving_review_count":0}' \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false
```

---

## Workflow After Protection

### Feature Development

```bash
# 1. Start from develop
git checkout develop
git pull origin develop

# 2. Create feature branch
git checkout -b feature/my-feature

# 3. Work on your feature
# ... make changes ...

# 4. Push and create PR
git push -u origin feature/my-feature
gh pr create --base develop --title "Add my feature"

# 5. After PR approval and merge, clean up
git checkout develop
git pull origin develop
git branch -d feature/my-feature
```

### Release to Production

```bash
# 1. Create PR from develop to main
gh pr create --base main --head develop --title "Release v1.0.0"

# 2. After approval, merge via GitHub UI or:
gh pr merge --merge

# 3. Tag the release (optional)
git checkout main
git pull origin main
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

---

## Common Questions

### Q: Can I push directly to `main` with protection?
**A:** No, that's the point. You must create a PR.

### Q: What if I need to hotfix production?
**A:** Create a `hotfix/` branch from `main`, fix, PR to `main`, then merge `main` back to `develop`.

### Q: Should I protect feature branches?
**A:** No. Feature branches are personal workspaces. Only protect shared branches.

### Q: What about `release/*` branches?
**A:** For simple projects, `develop` → `main` is enough. For complex release cycles, add `release/*` branches with moderate protection.
