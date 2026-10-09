---
name: lytics-integrations
description: "Lytics CDP: plan, set up and manage data integrations -- choose the right provider and workflow, map fields, create auth credentials and connections, and create, update, pause, resume, bounce, kill and read logs of jobs. Use when the user wants to connect a platform (Facebook, Google, Salesforce, Klaviyo...) for import, export, enrichment, audience sync or conversion API (CAPI); needs help choosing an integration approach, planning an integration or advice on field mapping; wants to set up, configure or connect a new integration end-to-end; wants to list, view, create, update or delete connections, auth providers or integration credentials, or scan a connection's data; or wants to list, view, create, update, pause, resume, restart, kill or manage data jobs and workflows, or check job status and logs."
license: MIT
---

# Lytics Integrations

Everything between "I want to connect X" and a running job: picking the provider and workflow, field mapping, auth credentials, connections to external data sources, and the job lifecycle (create, update, pause, resume, bounce, kill, logs). Integrations are layered: **Provider** (what platform) -> **Auth** (how to authenticate) -> **Connection** (optional, for data-source integrations) -> **Job** (runs one workflow).

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

## Modes

Read the mode file before acting in that mode.

| Mode | When | File |
|---|---|---|
| advise | Choosing a provider/workflow, weighing tradeoffs, planning field mappings, checking a segment for an export | `advise.md` |
| setup | End-to-end creation: auth -> connection -> job, in dependency order, behind one gate | `setup.md` |
| connections | List/get/create/update/delete connections and auth providers, list providers, scan a connection or read its schema | `connections.md` |
| jobs | List/get/create/update jobs, pause/resume/bounce/kill/release, job logs | `jobs.md` |

A specific, well-defined request ("create a job with workflow X and auth Y") goes straight to `jobs` or `setup`. A request that involves choosing a workflow, mapping fields, or a new integration from scratch starts in `advise`, then continues in `setup`.

## Related skills

- `lytics-audiences` -- the export needs a segment that does not exist yet, or the user wants help choosing the audience.
- `lytics-schema` -- look up or add the Lytics fields an import maps into or an export maps from.
- `lytics-export-debugger` -- an existing export is failing or sending fewer users than expected.
- `lytics-account-sync` -- copy jobs, connections or auth from one account to another.
