---
name: pr-writing
description: Expert PR and commit message writing following Conventional Commits. Use when creating pull requests, merge requests, writing commit messages, or generating changelogs. Applies to GitHub, GitLab, and Azure DevOps.
---

# PR Writing Skill

This skill provides Claude Code with expert-level knowledge for writing pull requests, merge requests, and commit messages following industry best practices and Conventional Commits specification.

## Conventional Commits Format

### Commit Message Structure

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### PR/MR Title Format

```
<type>: <concise description>
```

Or with scope:

```
<type>(<scope>): <concise description>
```

## Type Reference

| Type | When to Use | Example |
|------|-------------|---------|
| `feat` | New feature or capability | `feat: add OAuth2 authentication` |
| `fix` | Bug fix | `fix: resolve null pointer in user service` |
| `docs` | Documentation only | `docs: update API reference` |
| `chore` | Maintenance, deps, configs | `chore: upgrade dependencies` |
| `refactor` | Code change, no behavior change | `refactor: extract validation logic` |
| `test` | Adding/fixing tests | `test: add unit tests for auth module` |
| `ci` | CI/CD pipeline changes | `ci: add caching to build workflow` |
| `perf` | Performance improvement | `perf: optimize database queries` |
| `style` | Formatting, whitespace | `style: fix indentation` |
| `build` | Build system changes | `build: update webpack config` |
| `revert` | Reverting previous commit | `revert: feat: add OAuth2` |

## Title Rules

1. **Max 50 characters** for the description part
2. **Imperative mood**: "add" not "added" or "adds"
3. **Lowercase** after the colon
4. **No period** at the end
5. **Be specific**: "fix login timeout" not "fix bug"

### Good vs Bad Titles

| Bad | Good |
|-----|------|
| `Fixed the bug` | `fix: resolve race condition in auth` |
| `Updated stuff` | `chore: upgrade lodash to 4.17.21` |
| `New feature` | `feat: add dark mode toggle` |
| `Changes` | `refactor: simplify error handling` |
| `WIP` | `feat: add user export (WIP)` |

## PR/MR Body Template

```markdown
## Summary

- First major change or feature
- Second major change
- Third change if applicable

## Changes

### Category 1
- `path/to/file.ts` - Description of change
- `path/to/other.ts` - Description of change

### Category 2
- `another/file.ts` - Description of change

## Test Plan

- [ ] Verify feature X works as expected
- [ ] Verify existing tests pass
- [ ] Manual testing of scenario Y

## Notes

Any additional context, breaking changes, or migration notes.
```

## Platform-Specific Terminology

| Concept | GitHub | GitLab | Azure DevOps |
|---------|--------|--------|--------------|
| Code review request | Pull Request (PR) | Merge Request (MR) | Pull Request (PR) |
| Default branch | `main` | `main` | `main` |
| CI/CD config | `.github/workflows/` | `.gitlab-ci.yml` | `azure-pipelines.yml` |
| CLI tool | `gh` | `glab` | `az repos` |

## Platform Detection

Detect platform from git remote URL:

| URL Pattern | Platform | CLI Command |
|-------------|----------|-------------|
| `github.com` | GitHub | `gh pr create` |
| `gitlab.com` or `gitlab.*` | GitLab | `glab mr create` |
| `dev.azure.com` | Azure DevOps | `az repos pr create` |
| `*.visualstudio.com` | Azure DevOps | `az repos pr create` |

## CLI Commands by Platform

### GitHub
```bash
gh pr create --base <target> --title "<title>" --body "<body>"
```

### GitLab
```bash
glab mr create --target-branch <target> --title "<title>" --description "<body>"
```

### Azure DevOps
```bash
az repos pr create --target-branch <target> --title "<title>" --description "<body>"
```

## Analyzing Commits for PR Type

When multiple commits exist, determine the primary type:

1. **Any `feat` commit?** → PR type is `feat`
2. **Only `fix` commits?** → PR type is `fix`
3. **Only `docs` commits?** → PR type is `docs`
4. **Mixed types?** → Use the most significant:
   - `feat` > `fix` > `refactor` > `perf` > `test` > `docs` > `chore` > `style`

## Breaking Changes

For breaking changes, add an exclamation mark after the type:

```
feat!: remove deprecated API endpoints
fix!: change authentication flow
```

Or add footer:

```
feat: redesign user API

BREAKING CHANGE: User endpoint now requires authentication token.
```

## Scope Guidelines

Scope is optional but useful for larger projects:

| Scope | Example |
|-------|---------|
| Module/feature | `feat(auth): add password reset` |
| File type | `style(css): fix button alignment` |
| Component | `fix(navbar): resolve dropdown z-index` |
| Package | `chore(deps): update react to 18.2` |

## Best Practices

1. **One PR = One logical change** - Don't mix unrelated changes
2. **Keep PRs small** - Easier to review, faster to merge
3. **Write for reviewers** - Explain the "why", not just the "what"
4. **Link issues** - Reference related issues/tickets
5. **Add screenshots** - For UI changes, include before/after
6. **Update tests** - Include test changes with code changes
7. **Self-review first** - Check your own diff before requesting review
