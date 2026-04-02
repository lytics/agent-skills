---
name: job-manager
description: Job/work CRUD and lifecycle management -- create, pause, resume, bounce, kill. Use when the user wants to list, view, create, pause, resume, restart, or manage data jobs and workflows.
metadata:
  arguments: action and relevant parameters -- list, get, create, update, pause, resume, bounce, kill, logs
---

# Job Manager

## Purpose
Full job/work lifecycle management -- list, create, update, and control job state (pause, resume, bounce, kill). Jobs represent data integration tasks like imports, exports, and syncs.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## API Endpoints

### List Jobs
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
By default only shows non-terminal jobs (runnable, sleeping, paused, fault).

| Query Parameter | Default | Description |
|----------------|---------|-------------|
| `workflow` | - | Filter by workflow slug |
| `auth_ids` | - | Filter by auth IDs |
| `show_completed` | false | Include completed jobs |
| `show_deleted` | false | Include deleted jobs |
| `show_hidden` | false | Include hidden jobs |
| `show_all` | false | Show everything (sets completed, deleted, hidden to true) |
| `show_state` | false | Include WorkState details in response |

### Get Job
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Get Job by Workflow
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${WORKFLOW}/${JOB_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Create Job
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Job Name",
    "description": "What this job does",
    "workflow": "workflow_name",
    "config": { ... workflow-specific config ... },
    "auth_ids": ["auth_id"],
    "tag": "optional-tag"
  }'
```

### Create Job with Workflow
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${WORKFLOW}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... job config ... }'
```

### Update Job
```bash
curl -s -X PUT "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${WORKFLOW}/${JOB_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... updated fields ... }'
```

### Job Lifecycle Commands
```bash
# Pause
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/pause" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Resume
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/resume" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Bounce (restart)
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/bounce" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Kill (stop permanently)
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/kill" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Release
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/release" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Job Logs

Two endpoints: all-account logs (last 24h, excludes killed jobs) or logs for a specific job (since job creation).

```bash
# All account job logs (last 24 hours, non-killed jobs)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/logs" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Logs for a specific job (by ID)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/logs" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Logs for a specific job (by workflow + ID)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${WORKFLOW}/${JOB_ID}/logs" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Include additional error details
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/logs?include_errors=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

**Query parameter:** `include_errors=true` returns additional error details beyond the default log entries. Always use this when debugging job failures.

**Response: array of JobLog entries, sorted by timestamp.**

Each log entry contains:
```json
{
  "job_id": "abc123",
  "context": {
    "added": 145,
    "omitted": 3,
    "removed": 12,
    "user_email": "admin@acme.com"
  },
  "code": "JOB-FAULT-022",
  "message": "Human-readable description of what happened",
  "level": "info",
  "timestamp": "2026-03-19T14:30:00Z"
}
```

**Log entry fields:**

| Field | Description |
|-------|-------------|
| `job_id` | Which job this log belongs to |
| `message` | Human-readable description (e.g., "Started by user admin@acme.com", "Rate limit exceeded") |
| `level` | Log level -- `info` for events, `error`/`warn` for problems |
| `timestamp` | When the event occurred |
| `code` | Error code for error-level entries (e.g., `JOB-FAULT-022`, `UNAUTHORIZED-017`) |
| `context` | Additional metadata map, varies by event type |

**Common context fields for export jobs:**

| Context Key | Description |
|-------------|-------------|
| `added` | Number of users added/exported in this run |
| `omitted` | Number of users skipped (e.g., already exported, filtered out) |
| `removed` | Number of users removed from the destination |
| `user_email` | Who triggered the action (for manual start/pause/kill) |

**Log sources:**
- **API errors** from the job's WorkState (execution errors, auth failures, rate limits)
- **System events** (job created, started, paused, killed, updated -- info level)

**Interpreting logs for debugging:**
- Look at `level: "error"` entries first for failures
- Check `added`/`omitted`/`removed` counts to verify exports are happening
- Compare `timestamp` of latest log to current time to detect stale jobs
- `code` field helps categorize the error type (auth, rate limit, bad request, etc.)

## Job Payload

```json
{
  "name": "My Export Job",
  "description": "Export high-value users to Facebook",
  "workflow": "facebook_custom_audiences",
  "config": {
    "segment_id": "segment_id_here",
    "...": "workflow-specific configuration"
  },
  "auth_ids": ["auth_provider_id"],
  "tag": "optional-client-tag",
  "hidden": false,
  "verbose_logging": false,
  "quiet_time_of_day": "02:00",
  "quiet_timezone": "America/Los_Angeles",
  "quiet_period": 4
}
```

## Behavior

### For Read Operations (list, get, logs)
Execute immediately and display results in a table format showing:
- Job ID, name, workflow, status, last updated

### For Write Operations (create, update)
Use the confirmation-gate pattern.

### For Lifecycle Commands (pause, resume, bounce, kill)
- **pause/resume**: Execute with brief confirmation
- **bounce**: Explain this restarts the job, confirm
- **kill**: Warn this permanently stops the job, require explicit confirmation

## Error Handling
- **Job not found (404)**: Check job ID, list available jobs
- **Invalid workflow**: List available workflows
- **Auth missing**: Suggest creating auth provider first via connection-manager

## Dependencies
- Uses: `../references/api-client.md`, `../references/confirmation-gate.md`
