# Health check

Use for the single-command report: run all four checks, then present one unified report. Read-only.

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

The other calls below use the same form.

## Check 1: Streams

`GET /v2/stream`. For each stream:

| Signal | How to detect | Severity |
|---|---|---|
| Active | `last_msg_ts` within last hour | HEALTHY |
| Stale (continuous) | `last_msg_ts` 1-24 hours ago | WARNING |
| Stale (batch) | `last_msg_ts` 2-7 days ago | WARNING |
| Dead | `last_msg_ts` > 24h ago (continuous) or > 7d (batch) | ERROR |
| Never received | `ct == 0` | ERROR |

Distinguish batch vs continuous by checking whether the stream has associated jobs with periodic schedules.

For streams with issues, fetch `GET /v2/stream/{stream}/stats` for detail.

## Check 2: Jobs

- `GET /v2/job` -- every job except completed and killed (deleted) ones; `failed` and `fault-N` jobs are included
- `GET /v2/job?show_completed=true` -- also shows completed jobs

| Status | Severity | Action |
|---|---|---|
| `running`, `initializing` | HEALTHY | Running normally |
| `sleeping` | HEALTHY | Scheduled, waiting for next run |
| `paused`, `pausing` | WARNING | Intentional but flag for awareness |
| `fault-N` (prefix `fault`) | ERROR | Erroring or backing off after N errors -- fetch logs |
| `failed` | ERROR | Terminal failure -- fetch logs |
| `completed` | INFO | Finished (one-shot jobs) |
| `deleted`, `deleting` | INFO | Deleted (v2 kill is a delete) |

For faulted/failed jobs, fetch `GET /v2/job/{id}/logs`.

Do **not** treat an old `updated` timestamp as a stuck job: `updated` is when the job's *config* was last edited, so every healthy long-running job looks stale by that measure. To judge whether a `running` job is making progress, look at the timestamp of its most recent log event. Never recommend bouncing a job on staleness alone.

## Check 3: Schema

`GET /v2/schema/user/field` (all fields with metadata):

- **Identity fields**: count fields where `is_identifier == true`. Flag if fewer than 2.
- **PII fields**: count fields with `is_pii == true`, for awareness.
- **Stale fields**: field freshness is per-field `last_seen` on `GET /api/schema/_streams` -- not the schema field's `modified`, which is when its *definition* was last edited. Flag actively used fields whose `last_seen` is older than 30 days.

For deeper coverage analysis, `GET /api/schema/user/fieldinfo`: check field presence/absence ratios, and flag fields with very low coverage that appear in segment FilterQL.

## Check 4: Event quota

`GET /v2/control/eventquota/thresholds`. Report current usage against the thresholds (50%, 75%, 100%, 125%).

## Optional: metrics deep dive

When the user wants trends or deeper analysis:

- `GET /v2/metric?dimension=stream&range=now-24h` -- stream throughput over the last 24h
- `GET /v2/metric?dimension=works&range=now-24h` -- job execution metrics
- `GET /v2/metric?dimension=segment&range=now-24h` -- segment size trends

Present as trends: "Stream throughput is down 40% vs yesterday", "Segment sizes are stable."

## Report

```
## Data Health Report

### Overall: HEALTHY | NEEDS ATTENTION | UNHEALTHY

### Streams (N total)
  HEALTHY: X streams actively receiving data
  WARNING: 'stream_name' -- last event 3 days ago
  ERROR: 'stream_name' -- never received events

### Jobs (N active)
  HEALTHY: X jobs running normally
  FAULT: 'job_name' -- error message from logs
  PAUSED: 'job_name' -- paused since date

### Schema (user table, N fields)
  Identity fields: N configured (field1, field2, ...)
  Low coverage: 'field' at X%
  Stale: 'field' last_seen N days ago

### Event Quota
  Current usage: X% of monthly quota

### Recommendations
1. Specific actionable recommendation
2. ...
```

| Overall | Criteria |
|---|---|
| HEALTHY | All streams active, all jobs running, no faults, quota < 75% |
| NEEDS ATTENTION | Any: stale streams, paused jobs, low-coverage fields, quota 75-100% |
| UNHEALTHY | Any: faulted/failed jobs, dead streams, quota > 100% |

## Recommendations

Make each one specific and actionable:

- Faulted job -> "Investigate 'job_name' fault. Check auth credentials or bounce the job." (A fault, not staleness, is the reason; see `lytics-integrations` for the bounce.)
- Dead stream -> "Stream 'name' hasn't received data in N days. Check the source integration."
- Zero-event stream -> "Stream 'name' is configured but has never received data. Verify the integration is set up correctly."
- Low identity fields -> "Only N identity fields configured. Consider marking additional fields as identifiers for better profile resolution."
- Quota approaching -> "Event quota at X%. Consider reviewing high-volume streams or upgrading your plan."
- Stale field -> "Field 'name' hasn't been seen in N days (`last_seen`). Check if the source integration is still active."

## When a check fails or comes back empty

- An API error on any check: report the error for that dimension and continue with the others. Never let one failed check block the whole report.
- Empty response: report "No [streams/jobs/fields] found" -- this may indicate a new or unconfigured account.
- A check that takes too long: skip it with a note and proceed.
