---
name: lytics-data-health
description: "Lytics CDP: check whether data is flowing correctly and inspect incoming data streams. Produces a single-command data health report across streams, jobs, schema, and event quota (with optional metrics trends), and lists streams, shows stream stats and fields, and browses recent stream events. Use when the user wants to check data health, view system status, get an overview of stream, job, or schema health, check event quota, asks \"is my data flowing?\" or \"is my integration working?\", wants to list streams, view stream statistics, browse recent stream events, see what incoming data looks like, or find out why profiles aren't updating."
license: MIT
---

# Lytics Data Health

Answers "is my data flowing correctly?" Two read-only modes: a unified health report across streams, jobs, schema, and event quota, and a stream inspector for listing streams, their stats, and recent events. Nothing here writes to the account.

## Before you start

- Credentials: `references/auth.md` (`LYTICS_API_TOKEN`, optional `LYTICS_API_URL`).
- Calling conventions, the `/v2` vs `/api` response shapes, and status-code handling: `references/api.md`.
- Every endpoint in this skill is a GET; run them without asking. If the user then wants a fix (bounce a job, mark an identifier), hand off to the owning skill, whose writes go through `references/confirmation-gate.md`.

## Gotchas

- **An old job `updated` is not a stuck job.** `updated` is when the job's *config* was last edited; every healthy long-running job looks stale by it. Judge progress by the timestamp of the job's most recent log event (`GET /v2/job/{id}/logs`). Never recommend bouncing a job on staleness alone.
- **Job status values are** `running`, `initializing`, `sleeping`, `paused`, `pausing`, `fault-N` (prefix `fault`: erroring or backing off after N errors), `failed`, `completed`, `deleted`, `deleting`. A v2 kill is a delete, so killed jobs show as `deleted`/`deleting`.
- **`GET /v2/job` hides only completed and killed (deleted) jobs by default** -- `failed` and `fault-N` jobs are already in it. Add `?show_completed=true` for completed ones, `?show_all=true` for killed ones.
- **Field freshness is per-field `last_seen` on `GET /api/schema/_streams`**, not the schema field's `modified`, which is when its *definition* was last edited.
- One failed check must not block the report: report the error for that dimension and continue with the others.

## Modes

Read the mode file before acting in that mode.

| Mode | When | File |
|---|---|---|
| health-check | "Is my data healthy?", system status, overview of streams/jobs/schema/quota, quota usage, trends | `health-check.md` |
| streams | List streams, stream stats or fields, browse recent events, "what does the data look like?", "is my integration sending data?" | `streams.md` |

If the user asks about one area (streams, jobs, schema), focus on it in health-check but still show a summary of the others.

## Related skills

- `lytics-integrations`: faulted/failed jobs, job logs in depth, bouncing or reconfiguring a job, checking the source connection behind a dead stream.
- `lytics-schema`: identity-field changes, low-coverage or stale fields, mapping fixes.
- `lytics-profiles`: "why isn't this profile updating?" for a specific person, after confirming the stream is receiving data.
- `lytics-export-debugger`: an outbound export that isn't delivering, as opposed to inbound data.
- `lytics-audiences`: segment-size questions beyond the trend in the metrics deep dive.
