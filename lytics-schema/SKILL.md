---
name: lytics-schema
description: "Lytics CDP: discover, manage, and optimize the profile schema. Find fields that match a natural-language concept, with their types, sample values, and value distributions; browse and modify schema fields, mappings, identity configuration, and field rankings, through schema patches or the direct publish workflow; and analyze field usage, coverage, mappings, merge operations, PII exposure, and identity config to suggest cleanup. Use when the user wants to find schema fields, understand field types, discover what data is available in the profile schema, map an audience concept to a field, list, view, create, or modify schema fields, mappings, identity configuration, or field rankings, publish schema changes, optimize their schema, find unused or inert fields, improve coverage, or review identity and merge configuration."
license: MIT
---

# Lytics Schema

The profile schema: which fields exist on a table (default `user`), how stream data is mapped into them, how identity is resolved, and whether the configuration is healthy. Discovery and optimization are read-only; management writes fields, mappings, and rankings and publishes them.

## Before you start

- Credentials: `references/auth.md`.
- Calling conventions, response shapes, and error handling: `references/api.md`.
- Every write (field, mapping, rank, patch, publish, delete) goes through `references/confirmation-gate.md`.
- Field types and their operators: `references/field-types.md`.

## Gotchas

- **Field bodies use lowercase keys** (`id`, `type`, `shortdesc`, `mergeop`, `is_identifier`, `is_pii`). Capitalized keys (`Field`, `Type`, `ShortDesc`, ...) are not accepted; patch endpoints reject them with `Attribute 'Field' is required for Field`.
- **A field update is a full replace, not a merge.** Any key you omit is reset, so `is_identifier` / `is_pii` silently become false. GET the field, change only what was asked, POST the whole object back.
- **Drop `mergeop` for identifier fields on GET -> POST.** GET reports a server-filled `mergeop` on identifiers, but POST rejects it: `Identifier Field cannot define a Merge Operation.`
- **Field POST is an upsert: there is no 409.** Creating a field that exists silently replaces it. GET `/v2/schema/{table}/field/{id}` first and confirm a replace.
- **A mapping's `stream` cannot change** (400). Delete the mapping and create a new one.
- **A field without a mapping is inert**: it never receives data. Always ask which stream and source field should populate a new field.
- **Patch mode is the `enable_schema_patches` account setting**, read from `/api/account/setting/enable_schema_patches`. Do not probe by listing patches: `GET /v2/schema/patch/{table}` returns 200 on every account.
- **Publish ships the whole shared draft**, including edits other users staged. Show `GET /v2/schema/{table}/compare` before confirming and ask about changes you did not make.
- **A direct-mode write is not done until publish succeeds**; unpublished edits stay staged and have no effect.

## Modes

Read the mode file before acting in that mode.

| Mode | When | File |
|---|---|---|
| discover | Find fields for a concept, inspect types, sample values, value distributions, field-for-intent lookup (e.g. for an audience) | `discover.md` |
| manage | List/view/create/update/delete fields and mappings, identity config, field rankings, schema patches, publish | `manage.md` |
| optimize | Read-only health report: unused and inert fields, coverage, identity, merge ops, PII exposure, capacity | `optimize.md` |

## Related skills

- `lytics-audiences`: build or edit segments once discover has mapped the user's concepts to fields; optimize reads its segment list to find field usage.
- `lytics-integrations`: set up the import job that feeds the stream a new mapping reads from.
- `lytics-data-health`: check whether a stream is actually receiving events when a mapped field stays empty.
- `lytics-profiles`: look at a single profile to see what values a field holds in practice.
