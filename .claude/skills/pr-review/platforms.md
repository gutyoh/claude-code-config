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

# Build the review JSON with jq (handles escaping and variable expansion)
jq -n \
  --arg sha "$COMMIT_SHA" \
  --arg event "COMMENT" \
  --arg body "## Code Review Summary ..." \
  '{
    commit_id: $sha,
    event: $event,
    body: $body,
    comments: [
      {
        path: "src/example.py",
        line: 42,
        side: "RIGHT",
        body: "**Warning**: Description.\n\n**Recommendation**: Fix."
      }
    ]
  }' | gh api --method POST "/repos/$REPO/pulls/$PR_NUMBER/reviews" --input -
```

**Comment fields:**
- `path` (required) — relative file path
- `line` (required) — line number in the file (new file when `side` is `"RIGHT"`, old file when `"LEFT"`)
- `side` — `"RIGHT"` (new file, default) or `"LEFT"` (old/deleted file)
- `body` (required) — comment text (Markdown supported)
- `start_line` + `start_side` — for multi-line comment ranges
- `subject_type` — `"line"` (default) or `"file"` (comment on whole file)

**`event` values:**
- `"COMMENT"` — neutral review with comments
- `"REQUEST_CHANGES"` — block merge until resolved (requires user confirmation)
- `"APPROVE"` — approve the PR

**Important:** Always include `commit_id` to pin comments to the reviewed commit.

**CRITICAL:** Never use a single-quoted heredoc (`<<'EOF'`) with shell variables — they won't expand. Always use `jq` to build JSON with variable interpolation, then pipe to `gh api --input -`.

## GitLab (Discussions REST API)

GitLab inline comments require the Discussions API with position-based comments.
`glab mr note` supports general comments but NOT file/line positioning (as of 2026, see gitlab-org/cli#1311).

```bash
# General summary comment
glab mr note <number> --message "## Code Review Summary ..."

# Get diff_refs SHAs from the MR (required for positioning)
MR_IID=<number>
PROJECT_ID=$(glab api "projects/:fullpath" --jq '.id')
DIFF_REFS=$(glab api "projects/$PROJECT_ID/merge_requests/$MR_IID" --jq '.diff_refs')
BASE_SHA=$(echo "$DIFF_REFS" | jq -r '.base_sha')
START_SHA=$(echo "$DIFF_REFS" | jq -r '.start_sha')
HEAD_SHA=$(echo "$DIFF_REFS" | jq -r '.head_sha')

# Post inline comment via Discussions API (one per comment)
# Use jq to build JSON safely — prevents shell injection from untrusted diff content
COMMENT_BODY="**Warning**: Description. **Recommendation**: Fix."
jq -n \
  --arg body "$COMMENT_BODY" \
  --arg base_sha "$BASE_SHA" \
  --arg start_sha "$START_SHA" \
  --arg head_sha "$HEAD_SHA" \
  --arg new_path "src/example.py" \
  --arg old_path "src/example.py" \
  --argjson new_line 42 \
  '{
    body: $body,
    position: {
      position_type: "text",
      base_sha: $base_sha,
      start_sha: $start_sha,
      head_sha: $head_sha,
      new_path: $new_path,
      old_path: $old_path,
      new_line: $new_line
    }
  }' | glab api --method POST "projects/$PROJECT_ID/merge_requests/$MR_IID/discussions" --input -
```

**Position fields:**
- `position[position_type]` (required) — always `"text"` for inline comments
- `position[base_sha]`, `position[start_sha]`, `position[head_sha]` (required) — from MR `diff_refs`
- `position[new_path]` (required) — file path after change
- `position[old_path]` (required) — file path before change (same as `new_path` if not renamed)
- `position[new_line]` — line number on added lines (green in diff)
- `position[old_line]` — line number on deleted lines (red in diff)
- Use `new_line` for comments on new/modified code, `old_line` for deleted code

**Important:** `glab api` handles authentication automatically (no need for `curl` + `PRIVATE-TOKEN`). Prefer `glab api` over raw `curl` when the `glab` CLI is available.

**No batch API** — each inline comment requires a separate POST call.

## Azure DevOps (Pull Request Threads via `az devops invoke`)

Azure DevOps uses pull request threads for both general and inline comments.
The `az repos pr` CLI does NOT support comment creation directly — use `az devops invoke`.

```bash
# Get the repository ID and org/project context
ORG=https://dev.azure.com/<org>
PROJECT="<project>"
REPO_ID=$(az repos show --repository <repo-name> --org "$ORG" --project "$PROJECT" --query id -o tsv)
PR_ID=<number>

# Post inline comment as a thread (one per comment)
cat > /tmp/thread.json << 'EOF'
{
  "comments": [
    {
      "parentCommentId": 0,
      "content": "**Warning**: Description.\n\n**Recommendation**: Fix.",
      "commentType": 1
    }
  ],
  "threadContext": {
    "filePath": "/src/example.py",
    "rightFileStart": { "line": 42, "offset": 1 },
    "rightFileEnd": { "line": 42, "offset": 11 }
  },
  "status": 1
}
EOF

az devops invoke \
  --area git --resource pullRequestThreads \
  --org "$ORG" \
  --route-parameters \
    project="$PROJECT" \
    repositoryId="$REPO_ID" \
    pullRequestId="$PR_ID" \
  --http-method POST \
  --in-file /tmp/thread.json \
  --api-version 7.0 \
  -o json
```

**Thread JSON fields:**
- `comments[].parentCommentId` — `0` for top-level comment (required)
- `comments[].content` — comment text (Markdown supported)
- `comments[].commentType` — `1` for text
- `threadContext.filePath` — absolute path from repo root (must start with `/`)
- `threadContext.rightFileStart.line` / `rightFileEnd.line` — line range in new file
- `threadContext.rightFileStart.offset` / `rightFileEnd.offset` — character offset within line
- `status` — **must be integer**: `1`=active, `2`=fixed, `4`=closed

**CRITICAL:** `status` must be an **integer** (`1`), not a string (`"active"`). Using a string will cause the API to silently ignore the status or error.

For general (non-inline) comments, omit the `threadContext` field.

**No batch API** — each inline comment requires a separate POST call. For efficiency, write multiple thread JSON files and post them in parallel.
