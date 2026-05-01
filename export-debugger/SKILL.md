---
name: export-debugger
description: Trace why a specific user was or wasn't exported to an external platform. Use when the user wants to debug an export, understand why a profile wasn't sent to a destination, or trace export behavior.
metadata:
  arguments: user identity and export job or destination platform name
---

# Export Debugger

## Purpose
Diagnoses why a specific user was or wasn't exported to an external platform. Traces through the full export pipeline: segment membership -> job status -> flow state -> quiet windows -> export logs. Read-only diagnostic.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## Inputs
- User identity (field + value, e.g., `email user@example.com`)
- Export destination: job ID, job name, platform name, or flow name
- Table (default: `user`)

## Diagnostic Flow

### Step 1: Identify the Export Job

If the user provides a job ID, fetch it directly. Otherwise, find the relevant job:

```bash
# List all jobs to find the export
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Match by name, workflow type, or platform. Extract the `segment_id` from the job's `config` field -- this is the segment the job exports from.

If the user mentions a flow, fetch it and trace to the export step:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Find steps with `type_hint: "work_export"` and get their `work_id` to identify the export job.

### Step 2: Check User's Segment Membership

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/${VALUE}?segments=true&allsegments=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Check: Is the user in the export job's target segment?

- **YES** -> proceed to Step 3 (job should be exporting them)
- **NO** -> this is likely the reason. Use `profile-investigator skill` to explain why they're not in the segment.

### Step 3: Check Job Status

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Status | Diagnosis |
|--------|-----------|
| `runnable` | Job is active -- check logs for export details |
| `sleeping` | Job is between runs. Check `sleep_until` -- may be in quiet window or scheduled delay |
| `paused` | Job is paused. User or system paused it -- exports are halted |
| `fault` | Job has errors. Check logs for the error details |
| `failed` | Job has terminally failed. Check logs for root cause |
| `killed` | Job was manually stopped |

### Step 4: Check Quiet Window

If the job has quiet window settings, calculate whether it's currently active:

From the job response, check these fields:
- `quiet_time_of_day` -- e.g., "2:00pm"
- `quiet_timezone` -- e.g., "America/Los_Angeles"
- `quiet_period` -- hours of quiet, e.g., 4

If all three are set, calculate:
```
Quiet window: quiet_time_of_day to (quiet_time_of_day + quiet_period hours)
              in the configured timezone

Example: 2:00pm - 6:00pm America/Los_Angeles
```

If the current time falls within the quiet window, the job is sleeping and won't export until the window ends. Check `sleep_until` in the job response to confirm.

If `drop_events_during_quiet_window` is true, events arriving during quiet time are permanently dropped, not queued.

### Step 5: Check Flow State (if flow-based export)

If the export is triggered through a flow, check which step the user is at:

The entity response from Step 2 includes `flows_step_slugs`:
```json
{
  "flows_step_slugs": {
    "flow_id-1": "welcome_email_step"
  }
}
```

Cross-reference with the flow's step list to determine:
- Has the user reached the export step yet? (may still be in a delay or earlier step)
- Did the user exit the flow before reaching the export?
- Is the user in a conditional branch that doesn't lead to the export?

### Step 6: Check Job Logs

Always use `include_errors=true` when debugging to get full error details:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/logs?include_errors=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Look for:
- **Export counts**: `added`, `omitted`, `removed` in the log context
- **Errors**: Rate limits, auth failures, API errors from the destination platform
- **Timestamps**: When the job last ran successfully
- **User-level errors**: Some platforms report per-user failures (e.g., invalid email format)

## Output Format

```
## Export Debug Report

### User: user@example.com
### Destination: Facebook Custom Audiences (job: "fb_export_high_value")

### Diagnostic Results

1. SEGMENT MEMBERSHIP: PASS
   User IS in segment "High Value Customers" (id: seg123)

2. JOB STATUS: PASS
   Job is "runnable" -- actively processing

3. QUIET WINDOW: FAIL
   Job is currently in quiet window (2:00pm - 6:00pm PT)
   Will resume at: 6:00pm PT (2026-03-19T01:00:00Z)
   drop_events_during_quiet_window: false (events are queued)

4. FLOW STATE: N/A
   Export is not flow-based

5. JOB LOGS: INFO
   Last export: 2026-03-19 09:45:00 UTC
   Added: 145, Omitted: 3, Removed: 12
   No errors in recent logs

### Diagnosis
The user IS in the export segment and the job is active, but the job
is currently in its quiet window (2:00pm-6:00pm PT). The user should
be exported when the job resumes at 6:00pm PT. Events are being
queued, not dropped.
```

### Common Diagnoses

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| User not in segment | FilterQL conditions not met | Use profile-investigator to see which conditions fail |
| Job paused | Manually paused or auto-paused | Resume the job |
| Job faulted | Auth expired, rate limit, API error | Check logs, fix auth or wait for rate limit reset |
| Job sleeping | Quiet window or scheduled delay | Wait for quiet window to end |
| User in wrong flow step | Delay step or conditional branch | Check flow structure and timing |
| User exported but not appearing | Platform sync delay | Check platform-side, may take minutes to hours |
| "Omitted" in logs | User was filtered by export config | Check job config for additional filters beyond segment |

## Error Handling
- **Job not found**: List jobs and help user identify the right one
- **User not found**: Try alternative identity fields
- **Multiple export jobs for same platform**: Show all, ask user to pick
- **No logs available**: Job may be new or logs may have aged out

## Dependencies
- Composes: `job-manager skill`, `entity-lookup skill`, `segment-manager skill`, `flow-manager skill`
- Related: `profile-investigator skill` (for segment membership diagnosis)
- References: `../references/auth.md`, `../references/api-client.md`
