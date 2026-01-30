# Operations Patterns

## Warehouse Management

SQL warehouses are the compute resources for running SQL queries. The agent should use warehouses, not clusters. Warehouse IDs are discovered dynamically — never hardcoded.

### List Warehouses

```bash
databricks warehouses list -p <profile> -o json
```

Present the list to the user and ask which warehouse to use, or use the one they specified.

### Get Warehouse Status

```bash
databricks warehouses get <warehouse_id> -p <profile> -o json
```

Key fields in response:
- `state`: `RUNNING`, `STOPPED`, `STARTING`, `STOPPING`, `DELETING`
- `num_clusters`: Active cluster count
- `num_active_sessions`: Active query sessions

### Start a Stopped Warehouse

```bash
# Only if warehouse is STOPPED and needed for queries
databricks warehouses start <warehouse_id> -p <profile>
```

---

## Job Monitoring

### List Jobs

```bash
databricks jobs list -p <profile> -o json
```

### Get Job Details

```bash
databricks jobs get <JOB_ID> -p <profile> -o json
```

### List Recent Runs for a Job

```bash
databricks jobs list-runs --job-id <JOB_ID> -p <profile> -o json
```

### Get Run Details

```bash
databricks runs get <RUN_ID> -p <profile> -o json
```

### Get Run Output

```bash
databricks jobs get-run-output <RUN_ID> -p <profile> -o json
```

### Key Run States

| State | Meaning |
|-------|---------|
| `PENDING` | Waiting for resources |
| `RUNNING` | Currently executing |
| `TERMINATED` | Completed (check `result_state` for success/failure) |
| `SKIPPED` | Skipped by schedule |
| `INTERNAL_ERROR` | Platform error |

### Result States (after TERMINATED)

| Result State | Meaning |
|-------------|---------|
| `SUCCESS` | Completed successfully |
| `FAILED` | Task failed |
| `TIMEDOUT` | Exceeded timeout |
| `CANCELED` | Manually canceled |

---

## Pipeline Monitoring (Lakeflow / DLT)

Pipelines are Databricks' managed ETL framework (formerly Delta Live Tables).

### List Pipelines

```bash
databricks pipelines list-pipelines -p <profile> -o json
```

### Get Pipeline Details

```bash
databricks pipelines get <PIPELINE_ID> -p <profile> -o json
```

### List Pipeline Updates (Runs)

```bash
databricks pipelines list-updates <PIPELINE_ID> -p <profile> -o json
```

### Get Specific Update Details

```bash
databricks pipelines get-update <PIPELINE_ID> --update-id <UPDATE_ID> -p <profile> -o json
```

### List Pipeline Events (Logs)

```bash
databricks pipelines list-pipeline-events <PIPELINE_ID> -p <profile> -o json
```

### Key Pipeline States

| State | Meaning |
|-------|---------|
| `IDLE` | Not running |
| `RUNNING` | Currently processing |
| `FAILED` | Update failed |
| `COMPLETED` | Update succeeded |

---

## Query History

### List Recent Queries (Native CLI)

```bash
databricks query-history list -p <profile> -o json
```

### List Recent Queries (API — More Filter Options)

```bash
databricks api get /api/2.0/sql/history/queries -p <profile> -o json
```

The API endpoint supports filter parameters for warehouse ID, user, status, and time range.

---

## Genie (AI/BI Natural Language Queries)

Genie provides natural language access to data via AI/BI spaces.

### Start a Conversation

```bash
databricks genie start-conversation <SPACE_ID> \
  -p <profile> -o json \
  --json '{"content": "<natural language question>"}'
```

### Send a Follow-Up Message

```bash
databricks genie create-message <SPACE_ID> --conversation-id <CONVERSATION_ID> \
  -p <profile> -o json \
  --json '{"content": "<follow-up question>"}'
```

### Get Message Results

```bash
databricks genie get-message <SPACE_ID> --conversation-id <CONVERSATION_ID> --message-id <MESSAGE_ID> \
  -p <profile> -o json
```

**Note**: Genie requires an AI/BI Genie space to be configured in the workspace. Not all workspaces have this.

---

## Alerts and Notifications

### List SQL Alerts

```bash
databricks alerts list -p <profile> -o json
```

### Get Alert Details

```bash
databricks alerts get <ALERT_ID> -p <profile> -o json
```

---

## Common Monitoring Workflows

### Daily Operations Check

```bash
# 1. Check warehouse status
databricks warehouses list -p <profile> -o json

# 2. Check recent job runs
databricks jobs list-runs -p <profile> -o json

# 3. Check pipeline status
databricks pipelines list-pipelines -p <profile> -o json

# 4. Check query history for errors
databricks query-history list -p <profile> -o json
```

### Investigate a Failed Job

```bash
# 1. List recent runs for the job
databricks jobs list-runs --job-id <JOB_ID> -p <profile> -o json

# 2. Get the failed run details
databricks runs get <RUN_ID> -p <profile> -o json

# 3. Get the run output/error
databricks jobs get-run-output <RUN_ID> -p <profile> -o json
```

### Check Pipeline Health

```bash
# 1. List pipelines
databricks pipelines list-pipelines -p <profile> -o json

# 2. List recent updates
databricks pipelines list-updates <PIPELINE_ID> -p <profile> -o json

# 3. Get events for the latest update
databricks pipelines list-pipeline-events <PIPELINE_ID> -p <profile> -o json
```

---

## Anti-Patterns

1. **Starting clusters**: Use SQL warehouses, not clusters. The agent should not manage clusters.
2. **Not checking warehouse state**: Always verify the warehouse is `RUNNING` before executing SQL queries.
3. **Ignoring run `result_state`**: A `TERMINATED` run can be `SUCCESS` or `FAILED` — always check both.
4. **Not using `--job-id` filter**: When listing runs, always filter by job ID to avoid noisy output.
5. **Forgetting pipeline events**: Pipeline failures are detailed in events, not just the update status.
6. **Hardcoding warehouse IDs**: Always discover via `databricks warehouses list`.
7. **Hardcoding profile names**: Always discover via `databricks auth profiles`.
