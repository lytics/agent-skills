# Setup

Use to create a complete integration end-to-end -- auth, connection, job -- for an import (into Lytics) or an export (out to a platform). If the user still needs to choose a workflow or plan field mappings, do `advise.md` first; a specific request ("create a job with workflow X and auth Y") can start here directly.

## Steps

1. **Identify the integration**: platform, direction (import/export), data type (audiences, events, profiles, conversions). Optional inputs: credentials, segment to export, schedule.
2. **Find the provider**: `GET /v2/provider`.
3. **Check existing auth**: `GET /v2/auth`; reuse valid auth for the target platform.
4. **Create auth if needed** (`connections.md`). Tell the user which credentials their platform needs and where to find them; OAuth goes through the Lytics UI. Invalid auth: suggest re-creating it.
5. **Create or select a connection** (`connections.md`): `GET /v2/connection`; reuse a suitable one, otherwise create it.
6. **Configure the job** (`jobs.md`): workflow matching the integration type, platform-specific `config`, `auth_ids` linking the credentials, `segment_id` for exports. Workflow not found: list the provider's workflows. Segment not found: hand off to the `lytics-audiences` skill to create it first.
7. **Confirmation gate** for the whole setup:
   - auth provider details (type, never credential values)
   - connection configuration
   - job settings (workflow, schedule, segment)
   - the raw API payload for every resource to be created
   - that creating the job **starts it immediately** unless created with `?run_job=false`

   Example job payload:
   ```json
   {
     "name": "Export High Value to Facebook",
     "workflow": "facebook_custom_audiences",
     "config": {
       "segment_id": "abc123",
       "field_mappings": { ... }
     },
     "auth_ids": ["auth_456"]
   }
   ```
8. **Execute on approval, in dependency order**: auth (if new) -> connection (if new) -> job. Report each created resource's id.
9. **Verify**: `GET /v2/job/{id}` and `GET /v2/job/{id}/logs?include_errors=true`. Report the initial status (e.g. `running`; see the status list in `jobs.md`) and suggest checking back in a few minutes for the first sync results.

## Common patterns

| Pattern | Steps |
|---|---|
| Audience export | Select/create a segment -> export job with `segment_id` -> set schedule (continuous, daily, ...) |
| Data import | Configure connection to the source -> scan it to discover data -> import job with field mappings |
| Conversion API (CAPI) | Auth for the ad platform -> conversion export job -> map Lytics events to platform conversion events |
