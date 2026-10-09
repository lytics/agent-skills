---
name: data-health-monitor
description: Single-command data health check -- streams, jobs, schema, and quota status in one report. Use when the user wants to check data health, view system status, or get an overview of streams, jobs, and schema health.
metadata:
  arguments: optional focus area -- streams, jobs, schema, or all
---

# Data Health Monitor

## Purpose
Answers "is my data flowing correctly?" with a single command. Aggregates health signals across streams, jobs, schema, and event quota into a unified, actionable report. Purely read-only.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## Flow

Run all four health checks, then present a unified report. If the user asks about a specific area, focus on that dimension but still show a summary of others.

### Check 1: Stream Health

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

For each stream, evaluate:

| Signal | How to Detect | Severity |
|--------|--------------|----------|
| Active | `last_msg_ts` within last hour | HEALTHY |
| Stale (continuous) | `last_msg_ts` 1-24 hours ago | WARNING |
| Stale (batch) | `last_msg_ts` 2-7 days ago | WARNING |
| Dead | `last_msg_ts` > 24h ago (continuous) or > 7d (batch) | ERROR |
| Never received | `ct == 0` | ERROR |

Distinguish batch vs continuous by checking if the stream has associated jobs with periodic schedules.

For streams with issues, fetch recent stats for more detail:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/${STREAM_NAME}/stats" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Check 2: Job Health

```bash
# Active jobs (default: non-terminal states)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Also check recently failed jobs
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job?show_completed=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Evaluate each job:

| Status | Severity | Action |
|--------|----------|--------|
| `running`, `initializing` | HEALTHY | Running normally |
| `sleeping` | HEALTHY | Scheduled, waiting for next run |
| `paused`, `pausing` | WARNING | Intentional but flag for awareness |
| `fault-N` (prefix `fault`) | ERROR | Erroring or backing off after N errors -- fetch logs |
| `failed` | ERROR | Terminal failure -- fetch logs |
| `completed` | INFO | Finished (one-shot jobs) |
| `deleted`, `deleting` | INFO | Deleted (v2 kill is a delete) |

For faulted/failed jobs, fetch logs:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/logs" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Do **not** treat an old `updated` timestamp as a stuck job: `updated` is when the job's *config* was last edited, so every healthy long-running job looks stale by that measure. To judge whether a `running` job is making progress, look at the timestamp of its most recent log event. Never recommend bouncing a job on staleness alone.

### Check 3: Schema Health

```bash
# Get all fields with metadata
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Check:
- **Identity fields**: Count fields where `is_identifier == true`. Flag if fewer than 2.
- **PII fields**: Count fields marked `is_pii == true` for awareness.
- **Stale fields**: Field freshness is per-field `last_seen` on `GET /api/schema/_streams` -- not the schema field's `modified`, which is when its *definition* was last edited. Flag actively used fields whose `last_seen` is older than 30 days.

For deeper coverage analysis:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/schema/user/fieldinfo" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Check field presence/absence ratios. Flag fields with very low coverage that appear in segment FilterQL.

### Check 4: Event Quota

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/control/eventquota/thresholds" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Report current usage against thresholds (50%, 75%, 100%, 125%).

### Optional: Metrics Deep Dive

When the user wants trends or deeper analysis:
```bash
# Stream throughput over last 24h
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/metric?dimension=stream&range=now-24h" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Job execution metrics over last 24h
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/metric?dimension=works&range=now-24h" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Segment size trends
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/metric?dimension=segment&range=now-24h" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Present as trends: "Stream throughput is down 40% vs yesterday" or "Segment sizes are stable."

## Output Format

Present the report as:

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
  Stale: 'field' not updated in N days

### Event Quota
  Current usage: X% of monthly quota

### Recommendations
1. Specific actionable recommendation
2. Another recommendation
3. ...
```

## Severity Logic

| Overall Status | Criteria |
|---------------|----------|
| HEALTHY | All streams active, all jobs running, no faults, quota < 75% |
| NEEDS ATTENTION | Any: stale streams, paused jobs, low-coverage fields, quota 75-100% |
| UNHEALTHY | Any: faulted/failed jobs, dead streams, quota > 100% |

## Recommendations Engine

Generate specific, actionable recommendations based on findings:

- Faulted job → "Investigate 'job_name' fault. Check auth credentials or bounce the job."
- Dead stream → "Stream 'name' hasn't received data in N days. Check the source integration."
- Zero-event stream → "Stream 'name' is configured but has never received data. Verify the integration is set up correctly."
- Low identity fields → "Only N identity fields configured. Consider marking additional fields as identifiers for better profile resolution."
- Quota approaching → "Event quota at X%. Consider reviewing high-volume streams or upgrading your plan."
- Stale field → "Field 'name' hasn't been updated in N days. Check if the source integration is still active."

## Error Handling
- **API errors on any check**: Report the error for that dimension, continue with other checks. Never let one failed check block the whole report.
- **Empty responses**: Report "No [streams/jobs/fields] found" -- this may indicate a new or unconfigured account.
- **Timeout**: If a check takes too long, skip it with a note and proceed.

## Dependencies
- Composes: `stream-inspector skill`, `job-manager skill`, `schema-manager skill`
- References: `../references/auth.md`, `../references/api-client.md`
