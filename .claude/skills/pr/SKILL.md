---
name: pr
description: Create a pull request (or merge request) with Conventional Commits formatting. Works with GitHub, GitLab, and Azure DevOps. Use when the user asks to create a PR or merge request.
argument-hint: [base-branch]
disable-model-invocation: true
---

# PR Command

Create a pull request (or merge request) with Conventional Commits formatting. Works with GitHub, GitLab, and Azure DevOps.

## Usage

```
/pr [base-branch]
```

## Arguments

- `base-branch` (optional): Target branch for the PR/MR. Defaults to `main` (trunk-based workflow).

## Behavior

When invoked, the command will:

1. **Detect platform** - Run `git remote -v` and identify:
   - `github.com` -> GitHub (use `gh pr create`)
   - `gitlab.com` or `gitlab.*` -> GitLab (use `glab mr create`)
   - `dev.azure.com` or `*.visualstudio.com` -> Azure DevOps (use `az repos pr create`)

2. **Analyze commits** - Run `git log` to see all commits on current branch vs base

3. **Determine PR type** - Based on commits, select appropriate type:
   - `feat`: New feature or capability
   - `fix`: Bug fix
   - `docs`: Documentation only
   - `chore`: Maintenance, dependencies, configs
   - `refactor`: Code change without behavior change
   - `test`: Adding/fixing tests
   - `ci`: CI/CD changes
   - `perf`: Performance improvement
   - `style`: Formatting, no code change

4. **Generate title** - Format: `<type>: <concise description>`
   - Max 50 characters for the description
   - Use imperative mood ("add" not "added")
   - Lowercase after the colon

5. **Generate body** - Include:
   - `## Summary` - 2-4 bullet points of what changed
   - `## Changes` - Organized by category with file paths
   - `## Test Plan` - Checklist of verification steps

6. **Create PR/MR** - Use the appropriate CLI based on detected platform

7. **Fallback** - If CLI not available, output the title and body for manual copy/paste

## Platform Detection

| URL Pattern | Platform | CLI Tool |
|-------------|----------|----------|
| `github.com` | GitHub | `gh` |
| `gitlab.com` or `gitlab.*` | GitLab | `glab` |
| `dev.azure.com` | Azure DevOps | `az repos` |
| `*.visualstudio.com` | Azure DevOps | `az repos` |

## Platform CLI Commands

| Platform | Create Command |
|----------|----------------|
| GitHub | `gh pr create --base <target> --title "<title>" --body "<body>"` |
| GitLab | `glab mr create --target-branch <target> --title "<title>" --description "<body>"` |
| Azure DevOps | `az repos pr create --target-branch <target> --title "<title>" --description "<body>"` |

## Examples

```
/pr
/pr main
/pr develop
/pr master
```

## Fallback Output Format

If the platform CLI is not installed, output for manual copy/paste:

```markdown
PR READY FOR MANUAL CREATION

Platform:      [GitHub/GitLab/Azure DevOps]
Target branch: [base-branch]
Source branch: [current-branch]

TITLE: <type>: <description>

BODY:
## Summary
...

## Changes
...

## Test Plan
...

CREATE AT: [URL to create PR/MR on the platform]
```

## Notes

- Automatically detects platform from git remote URL
- Defaults to `main` branch (trunk-based / GitHub Flow)
- For GitFlow repositories with a `develop` branch, the pr-manager agent will auto-detect and target accordingly
- Uses the `pr-writing` skill for formatting conventions
- Terminology adapts to platform (PR for GitHub/Azure, MR for GitLab)
