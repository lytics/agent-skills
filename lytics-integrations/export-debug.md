# Export debug

Use to trace why one specific user was or wasn't exported to a destination (Facebook, Google, a CRM, ...). Read-only: walks segment membership -> job status -> quiet window -> flow state -> job logs.

Inputs: the user's identity (field + value, e.g. `email user@example.com`), the destination (job id, job name, platform name or flow name), and the table (default `user`).

## Step 1: Identify the export job

With a job id, fetch it directly. Otherwise list jobs and match by name, workflow or platform (see `jobs.md`; killed jobs only appear with `show_all=true`):

```bash
curl -sS -G "${LYTICS_API_URL:-https://api.lytics.io}/v2/job" \
  -H "Authorization: ${LYTICS_API_TOKEN}" --data-urlencode "show_all=true"
```

Read the `segment_id` from the job's `config` -- the segment the job exports from. Several export jobs for the same platform: show them all and ask the user to pick. Job not found: list jobs and help the user identify the right one.

If the user names a flow, `GET /v2/flow/ui/{flow_id}`, find the steps with `type_hint: "work_export"`, and use their `work_id` as the export job id.

## Step 2: Segment membership

```bash
curl -sS "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/${VALUE}?segments=true&allsegments=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

`/api/entity` returns HTTP 200, not 404, for a missing profile: `message: "Not Found"` with a placeholder `{"segments": ["not_found", "all"]}`. Check for that before treating the response as a real profile, and try alternative identity fields.

- User **is** in the job's segment -> continue to Step 3.
- User **is not** -> this is likely the reason. Use the `lytics-profiles` skill to explain which conditions fail.

## Step 3: Job status

`GET /v2/job/{job_id}`. Status values and their meaning are in `jobs.md`; for this diagnosis:

| Status | Diagnosis |
|---|---|
| `running` | Active -- check the logs (Step 6) |
| `sleeping` | Between runs: quiet window or scheduled delay. Check `sleep_until` -- `GET /v2/job/{id}` never includes it; read it from `GET /v2/job?show_state=true` and pick the job by id |
| `paused` | Paused by a user or the system -- exports are halted |
| `fault-N` (prefix `fault`) | Errors, or backing off after N errors. Check the logs |
| `failed` | Terminally failed. Check the logs for the root cause |
| `deleted` | Killed -- in v2, kill is a delete |

## Step 4: Quiet window

If the job has `quiet_time_of_day` (e.g. `"2:00pm"`), `quiet_timezone` (e.g. `"America/Los_Angeles"`) and `quiet_period` (hours, e.g. `4`) all set, the window is `quiet_time_of_day` to `quiet_time_of_day + quiet_period` hours in that timezone (e.g. 2:00pm-6:00pm America/Los_Angeles). If now falls inside it, the job is sleeping and won't export until the window ends; confirm with `sleep_until` from `GET /v2/job?show_state=true` (the single-job GET omits it).

If `drop_events_during_quiet_window` is true, events arriving during quiet time are **permanently dropped**, not queued.

## Step 5: Flow state (flow-based exports only)

The entity response from Step 2 includes `flows_step_slugs`, e.g. `{"flow_id-1": "welcome_email_step"}`. Cross-reference it with the flow's step list: has the user reached the export step yet (may still be in a delay or an earlier step)? Did they exit the flow before it? Are they in a conditional branch that doesn't lead to the export?

## Step 6: Job logs

Always `GET /v2/job/{job_id}/logs?include_errors=true` when debugging (log fields: `jobs.md`). Look for:

- Export counts: `added`, `omitted`, `removed` in the log `context`.
- Errors: rate limits, auth failures, API errors from the destination.
- Timestamps: when the job last ran successfully.
- User-level errors: some platforms report per-user failures (e.g. invalid email format).

No logs: the job may be new, or the logs may have aged out.

## Report

One numbered line per check, each `PASS` / `FAIL` / `INFO` / `N/A` with the evidence, then a plain-language diagnosis. For example:

```
## Export Debug Report
### User: user@example.com
### Destination: Facebook Custom Audiences (job: "fb_export_high_value")

1. SEGMENT MEMBERSHIP: PASS -- user IS in "High Value Customers" (id: seg123)
2. JOB STATUS: PASS -- "running"
3. QUIET WINDOW: FAIL -- in quiet window (2:00pm - 6:00pm PT), resumes 6:00pm PT (2026-03-19T01:00:00Z);
   drop_events_during_quiet_window: false (events are queued)
4. FLOW STATE: N/A -- export is not flow-based
5. JOB LOGS: INFO -- last export 2026-03-19 09:45:00 UTC; Added: 145, Omitted: 3, Removed: 12; no errors

### Diagnosis
The user is in the export segment and the job is active, but it is in its quiet window.
The user should be exported when the job resumes at 6:00pm PT; events are queued, not dropped.
```

## Common diagnoses

| Symptom | Likely cause | Resolution |
|---|---|---|
| User not in segment | FilterQL conditions not met | `lytics-profiles` skill: see which conditions fail |
| Job paused | Manually paused or auto-paused | Resume the job (`jobs.md`) |
| Job faulted | Auth expired, rate limit, API error | Check logs; fix auth (`connections.md`) or wait for the rate limit reset |
| Job sleeping | Quiet window or scheduled delay | Wait for the quiet window to end |
| User in wrong flow step | Delay step or conditional branch | Check flow structure and timing (`lytics-flows` skill) |
| User exported but not appearing | Platform sync delay | Check the platform side; may take minutes to hours |
| "Omitted" in logs | User filtered by export config | Check the job config for filters beyond the segment |
