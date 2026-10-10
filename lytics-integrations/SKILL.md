---
name: lytics-integrations
description: "Lytics CDP: plan, set up, manage and debug data integrations -- choose a provider and workflow, map fields, create auth and connections, run the job lifecycle (create, update, pause, resume, bounce, kill, logs), build and test webhook templates, and trace why a user was or wasn't exported. Use when the user wants to connect a platform (Facebook, Google, Salesforce, Klaviyo...) for import, export, enrichment, audience sync or conversion API (CAPI); wants advice on an integration approach or field mapping; wants to set up a new integration end-to-end; wants to list, create, update or delete connections, auth providers or credentials, or scan a connection; wants to list, create, update, pause, resume, restart or kill jobs or check job status and logs; wants to send audience triggers or enrichment to a custom webhook (Qualtrics, Slack, a custom CRM) or list, edit or test webhook templates; or asks why a profile did or didn't reach a destination, or wants to debug an export."
license: MIT
---

# Lytics Integrations

Everything between "I want to connect X" and a running job: picking the provider and workflow, field mapping, auth credentials, connections to external data sources, webhook templates for custom destinations, the job lifecycle (create, update, pause, resume, bounce, kill, logs), and debugging why one user did or didn't reach a destination. Integrations are layered: **Provider** (what platform) -> **Auth** (how to authenticate) -> **Connection** (optional, for data-source integrations) -> **Job** (runs one workflow).

## Before you start

- Credentials: `references/auth.md`.
- Request conventions, URL-encoding and the `/v2` error shape (`.errors[0].message`): `references/api.md`.
- Every create, update, delete and lifecycle command goes through `references/confirmation-gate.md` (pause/resume may use a brief confirmation; kill needs explicit confirmation).
- Never log or display full credential values. OAuth cannot be completed from the CLI: send the user to the Lytics UI, then pick up the new `auth_id` via `GET /v2/auth`.

## Gotchas

- **Create starts the job.** `POST /v2/job` and `POST /v2/job/{workflow}` default `run_job` to `true`, so an export begins sending data the moment it is created. Say so in the gate; pass `?run_job=false` to create it without running.
- **Job update is a full replace, not a merge.** Omitted `description`, quiet-window fields, `expires_at`, `meta`, `hidden`, `verbose_logging` are reset, and a sent `config` replaces the stored one wholesale. GET the job, edit only what was asked, PUT the whole object back.
- **Kill is a delete.** `POST /v2/job/{id}/kill` soft-deletes the job; it drops out of the job list and there is no API to undelete it. Offer pause as the reversible alternative.
- **Status values** are `running`, `sleeping`, `paused`, `pausing`, `initializing`, `failed`, `completed`, `deleted`, `deleting`, `unknown`, `fault-N`. Match faults by the `fault` prefix; the API never returns `runnable`, `fault` or `killed`.
- **Killed jobs are hidden by default.** List them with `show_all=true` (or `show_deleted=true&show_completed=true`); `show_deleted` alone does not show them. `/v2/job/logs` (account-wide) also excludes killed jobs.
- **`sleep_until` is only on the list.** `GET /v2/job/{id}` omits it; use `GET /v2/job?show_state=true`. With `drop_events_during_quiet_window: true`, quiet-time events are dropped, not queued.
- **Webhook templates:** update is `PUT /v2/template/{id}` (POST is 405); `desired_format` must be set or `/test` returns an empty 500; a template that threw still returns HTTP 200 with the error in `data`; the source is never readable back. js1 entry point is `function template(data)`.
- **Webhook job config has no `headers` field** -- headers live on a `header_param_auth` auth provider referenced by `auth_ids[]`. Live names are `segment_ids`, `audience_events` (`""`/`enters_only`/`exits_only`), `do_not_retry` (array of ints), `withbackfill`.

## Modes

Read the mode file before acting in that mode.

| Mode | When | File |
|---|---|---|
| advise | Choosing a provider/workflow, weighing tradeoffs, planning field mappings, checking a segment for an export | `advise.md` |
| setup | End-to-end creation: auth -> connection -> job, in dependency order, behind one gate | `setup.md` |
| connections | List/get/create/update/delete connections and auth providers, list providers, scan a connection or read its schema | `connections.md` |
| jobs | List/get/create/update jobs, pause/resume/bounce/kill/release, job logs | `jobs.md` |
| webhook-templates | Send triggers/enrichment to a custom webhook; list/get/create/update/delete/test templates; build one from the destination's docs | `webhook-templates.md` (+ `webhook-templates-reference.md`) |
| export-debug | Why one user was or wasn't exported: segment -> job status -> quiet window -> flow step -> logs (read-only) | `export-debug.md` |

A specific, well-defined request ("create a job with workflow X and auth Y") goes straight to `jobs` or `setup`. A request that involves choosing a workflow, mapping fields, or a new integration from scratch starts in `advise`, then continues in `setup`. An existing export that is failing or sending fewer users than expected goes to `export-debug`; a custom webhook destination goes to `webhook-templates`, which hands off to `connections` and `jobs`.

## Related skills

- `lytics-audiences` -- the export needs a segment that does not exist yet, or the user wants help choosing the audience.
- `lytics-schema` -- look up or add the Lytics fields an import maps into or an export maps from.
- `lytics-profiles` -- explain why a user is not in an export's segment, or pull a real profile to test a webhook template.
- `lytics-flows` -- an export driven by a flow step, when the user's flow position is the question.
- `lytics-account` -- copy jobs, connections or auth from one account to another.
