# Branch Protection Rules Templates

Ready-to-use GitHub Ruleset configurations for different branching strategies.

## Strategies

### Trunk-Based / GitHub Flow (Recommended for 2026)

```
feat/* ──────► main
fix/*  ──────► main
hotfix/* ────► main
```

**Use when:**
- Solo developer or small team
- Continuous deployment
- Fast iteration cycles
- Simple release process

**Files:** `trunk-based/main-branch-protection.json`

---

### GitFlow (Enterprise/Traditional)

```
feat/* ──► develop ──► main
fix/*  ──► develop ──► main
hotfix/* ─────────────► main (then back-merge to develop)
```

**Use when:**
- Multiple release versions in production
- Scheduled release cycles
- Larger teams with formal review processes
- Need for release branches

**Files:**
- `gitflow/main-branch-protection.json`
- `gitflow/develop-branch-protection.json`

---

## How to Import

### Via GitHub CLI

```bash
# Import a ruleset
gh api repos/OWNER/REPO/rulesets \
  --method POST \
  --input branch_protection_rules/trunk-based/main-branch-protection.json
```

### Via GitHub UI

1. Go to **Settings** → **Rules** → **Rulesets**
2. Click **New ruleset** → **Import a ruleset**
3. Upload the JSON file
4. Review and save

---

## Customization

### Change Required Approvals

Edit `required_approving_review_count`:
- `0` - Solo developer (no approval needed)
- `1` - Small team (one reviewer)
- `2+` - Larger teams

### Change Allowed Merge Methods

Edit `allowed_merge_methods`:
- `["squash"]` - Only squash (cleanest history)
- `["squash", "merge"]` - Squash preferred, merge allowed
- `["merge"]` - Only merge commits (preserves full history)
- `["rebase"]` - Only rebase (linear history, individual commits)

### Add Status Checks

Add this rule to require CI to pass:

```json
{
  "type": "required_status_checks",
  "parameters": {
    "strict_required_status_checks_policy": true,
    "required_status_checks": [
      {"context": "ci/build"},
      {"context": "ci/test"}
    ]
  }
}
```

### Add Code Owners Review

```json
{
  "require_code_owner_review": true
}
```

---

## Best Practices

| Practice | Trunk-Based | GitFlow |
|----------|-------------|---------|
| Branch lifetime | Hours to days | Days to weeks |
| Merge method | Squash | Merge commits |
| Release tagging | Tag main directly | Release branches |
| Hotfixes | Direct to main | Hotfix branch → main → develop |
| Feature flags | Recommended | Optional |

---

## Migration

### GitFlow → Trunk-Based

1. Merge all pending PRs to develop
2. Merge develop to main
3. Create backup: `git push origin develop:backup/develop-final-YYYYMMDD`
4. Delete develop branch protection ruleset
5. Delete develop branch
6. Import trunk-based ruleset

### Trunk-Based → GitFlow

1. Create develop from main: `git checkout -b develop main && git push -u origin develop`
2. Import both GitFlow rulesets
3. Update PR targets to develop
