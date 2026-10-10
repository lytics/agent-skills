# Jobs

Use to list, view, create and update jobs (imports, exports, syncs), control their state (pause, resume, bounce, kill, release), and read their logs.

Reads (list, get, logs) run immediately; show jobs as a table of id, name, workflow, status, last updated. Create and update go through the confirmation gate. Lifecycle: pause/resume with a brief confirmation; bounce -- explain it restarts the job, then confirm; kill -- warn that it **deletes** the job (no undelete through the API), suggest pause as the reversible alternative, and require explicit confirmation.

## List and get

```bash
curl -sS -w '\n%{http_code}\n' -G "${LYTICS_API_URL:-https://api.lytics.io}/v2/job" \
  -H "Authorization: ${LYTICS_API_TOKEN}" --data-urlencode "show_all=true"
```

| Query parameter | Default | Description |
|---|---|---|
| `workflow` | - | Filter by workflow slug |
| `auth_ids` | - | Filter by auth ids |
| `show_completed` | false | Include completed jobs |
| `show_hidden` | false | Include hidden jobs |
| `show_all` | false | Show everything: sets completed, deleted (killed) and hidden to true. Killed jobs need this, or `show_deleted=true` **and** `show_completed=true` together -- either flag alone does not list them |
| `show_state` | false | Include WorkState details in the response |

Status values the API returns: `running`, `sleeping`, `paused`, `pausing`, `initializing`, `failed`, `completed`, `deleted`, `deleting`, `unknown`, and `fault-N` (N = error count; also used for a job sleeping in error backoff). Match faults by the `fault` prefix -- the API never returns `runnable`, `fault` or `killed`.

Get one job: `GET /v2/job/{job_id}` or `GET /v2/job/{workflow}/{job_id}`. Not found (404): check the id and list jobs.

## Create

`POST /v2/job` (workflow in the body) or `POST /v2/job/{workflow}`.

Create **starts the job immediately** (`run_job` defaults to `true`), so an export begins sending data the moment it is created. Say so in the confirmation gate, and pass `?run_job=false` when the user wants to review it before it runs:

```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${WORKFLOW}?run_job=false" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary @job.json
```

Job payload:

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

Invalid workflow: list available workflows. Auth missing: create the auth provider first (`connections.md`).

## Update

An update is not a merge. `description`, the quiet-window fields, `expires_at`, `meta`, `hidden` and `verbose_logging` are reset whenever the body omits them, and a sent `config` replaces the stored one wholesale. GET the job, change only what the user asked for, and PUT the whole object back; show the before/after diff in the confirmation gate.

```bash
curl -sS "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" | jq '.data' > job.json
# ...edit job.json...
curl -sS -w '\n%{http_code}\n' -X PUT "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${WORKFLOW}/${JOB_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary @job.json
```

## Lifecycle

All are `POST` with no body:

| Command | Request | Effect |
|---|---|---|
| Pause | `/v2/job/{job_id}/pause` | Reversible stop |
| Resume | `/v2/job/{job_id}/resume` | Restart a paused job |
| Bounce | `/v2/job/{job_id}/bounce` | Restart the job |
| Kill | `/v2/job/{job_id}/kill` | **Delete**: the job is soft-deleted, drops out of the job list, and there is no API to undelete it. Prefer pause unless the user wants it gone |
| Release | `/v2/job/{job_id}/release` | - |

## Logs

| Request | Scope |
|---|---|
| `GET /v2/job/logs` | All account job logs, last 24 hours, excludes killed jobs |
| `GET /v2/job/{job_id}/logs` | One job, since creation |
| `GET /v2/job/{workflow}/{job_id}/logs` | Same, by workflow + id |

Add `include_errors=true` for additional error details beyond the default entries -- always use it when debugging a failure.

The response is an array of JobLog entries sorted by timestamp:

```json
{
  "job_id": "abc123",
  "context": {"added": 145, "omitted": 3, "removed": 12, "user_email": "admin@acme.com"},
  "code": "JOB-FAULT-022",
  "message": "Human-readable description of what happened",
  "level": "info",
  "timestamp": "2026-03-19T14:30:00Z"
}
```

| Field | Description |
|---|---|
| `job_id` | Which job the entry belongs to |
| `message` | Human-readable description (e.g. "Started by user admin@acme.com", "Rate limit exceeded") |
| `level` | `info` for events, `error`/`warn` for problems |
| `timestamp` | When it happened |
| `code` | Error code on error-level entries (e.g. `JOB-FAULT-022`, `UNAUTHORIZED-017`) |
| `context` | Metadata map that varies by event type |

Common `context` keys on export jobs: `added` (users added/exported this run), `omitted` (skipped, e.g. already exported or filtered out), `removed` (removed from the destination), `user_email` (who triggered a manual start/pause/kill).

Entries come from the job's WorkState (execution errors, auth failures, rate limits) and from system events (job created, started, paused, killed, updated -- info level).

Reading them:
- Look at `level: "error"` entries first.
- Check `added`/`omitted`/`removed` to verify exports are happening.
- Compare the latest `timestamp` to now to detect a stale job.
- `code` categorizes the error (auth, rate limit, bad request, ...).
