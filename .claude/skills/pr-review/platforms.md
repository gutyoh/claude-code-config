# Platform-Specific Review APIs

## Platform Detection

Detect the platform from the git remote URL:
- `github.com` -> GitHub
- `gitlab.com` or self-hosted GitLab -> GitLab
- `dev.azure.com` or `visualstudio.com` -> Azure DevOps

## GitHub (Batch Review — Preferred)

Post all comments as a single atomic review. One API call, all inline comments attached.

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PR_NUMBER=<number>
COMMIT_SHA=$(gh pr view $PR_NUMBER --json headRefOid -q .headRefOid)

# Build the JSON payload with all inline comments
# NOTE: Use jq or construct the JSON directly — do NOT use a single-quoted
# heredoc with placeholders, as shell variables won't expand inside <<'EOF'.
gh api --method POST \
  "/repos/$REPO/pulls/$PR_NUMBER/reviews" \
  -f commit_id="$COMMIT_SHA" \
  -f event="COMMENT" \
  -f body="## Code Review Summary ..." \
  --input <(jq -n \
    --arg sha "$COMMIT_SHA" \
    --arg body "## Code Review Summary ..." \
    '{
      commit_id: $sha,
      event: "COMMENT",
      body: $body,
      comments: [
        {
          path: "src/example.py",
          line: 42,
          body: "**Warning**: Description.\n\n**Recommendation**: Fix."
        }
      ]
    }')
```

**`event` values:**
- `"COMMENT"` — neutral review with comments
- `"REQUEST_CHANGES"` — block merge until resolved (requires user confirmation)
- `"APPROVE"` — approve the PR

**Important:** Always include `commit_id` to pin comments to the reviewed commit.

## GitLab (REST API)

GitLab inline comments require the Discussions API with position-based comments.
`glab mr note` supports general comments but NOT file/line positioning (as of 2026, see gitlab-org/cli#1311).

```bash
# General summary comment
glab mr note <number> --message "## Code Review Summary ..."

# Inline comments via REST API (required for file/line positioning)
BASE_SHA=$(git merge-base origin/<target> HEAD)
HEAD_SHA=$(git rev-parse HEAD)

curl --request POST \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$CI_SERVER_URL/api/v4/projects/$CI_PROJECT_ID/merge_requests/<iid>/discussions" \
  --data-urlencode "body=**Warning**: Description. **Recommendation**: Fix." \
  --data "position[position_type]=text" \
  --data "position[new_path]=src/example.py" \
  --data "position[new_line]=42" \
  --data "position[base_sha]=$BASE_SHA" \
  --data "position[head_sha]=$HEAD_SHA" \
  --data "position[start_sha]=$BASE_SHA"
```

## Azure DevOps (REST API)

Azure DevOps uses pull request threads for both general and inline comments.
The `az repos pr` CLI does NOT support comment creation directly — use `az devops invoke`.

```bash
# Post comments via thread creation (both general and inline)
az devops invoke \
  --area git --resource pullRequestThreads \
  --route-parameters \
    project=<project> \
    repositoryId=<repo-id> \
    pullRequestId=<pr-id> \
  --http-method POST \
  --in-file thread.json
```

`thread.json` format for inline comments:
```json
{
  "comments": [
    {
      "content": "**Warning**: Description.\n\n**Recommendation**: Fix.",
      "commentType": 1
    }
  ],
  "threadContext": {
    "filePath": "/src/example.py",
    "rightFileStart": { "line": 42, "offset": 1 },
    "rightFileEnd": { "line": 42, "offset": 1 }
  },
  "status": "active"
}
```

For general (non-inline) comments, omit the `threadContext` field.
