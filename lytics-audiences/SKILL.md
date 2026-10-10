---
name: lytics-audiences
description: "Lytics CDP: build, advise on, analyze, and manage audience segments. Translates natural language into FilterQL, validates and sizes it, and creates or updates the segment; recommends audience strategy for a business goal or improves an existing segment using ML feature importance, content affinities, and fieldinfo; shows audience composition (demographic breakdowns, top field values, coverage rates, distributions, segment comparisons); and lists, views, creates, updates, deletes, validates, sizes, and reevaluates segments. Use when the user wants to build, create, or define an audience or segment from a description; write, build, or validate a FilterQL query or filter expression; needs help choosing an audience strategy, advice on segment design, or to improve an existing segment; wants to understand audience composition, view segment demographics, or analyze field coverage for a segment; or wants to list, view, update, delete, validate, or size segments."
license: MIT
---

# Lytics Audiences

Everything about audience segments in Lytics: turning a description into valid FilterQL, coaching toward the right audience for a business goal, describing who is in a segment, and the segment lifecycle (list, get, create, update, delete, validate, size, reevaluate).

## Before you start

- Credentials: `references/auth.md`.
- Request and response conventions (two response shapes, URL-encoding, status codes): `references/api.md`.
- FilterQL syntax and operator/type compatibility: `references/filterql-grammar.md`, `references/field-types.md`.
- Every create, update, delete, and reevaluate goes through `references/confirmation-gate.md`. Reads (list, get, size, validate, fieldinfo) run immediately.

## Gotchas

- **Slug dedupe on create**: there is no 409. A taken `slug_name` is silently renamed to `<slug>_1`, `<slug>_2`, ... and the create still succeeds. Always report `.data.id` and `.data.slug_name` from the response, never the slug you sent, and say so explicitly if they differ. (On update, a taken slug is a 400 `Slug is already used.`)
- **Update can create a different segment**: if the new `segment_ql` omits `FROM`, the table resets to `user`; for a non-user segment the PUT misses the original and **creates a new segment**, and still succeeds. GET first, keep its `FROM <table>`, and check the returned `.data.id` equals the id you PUT to. If not, stop and tell the user a new segment was created.
- **Update can rename the slug**: if `ALIAS` differs from the current slug and no `slug_name` is sent, the slug is renamed, breaking every segment that does `INCLUDE <old_slug>`. Keep the existing `ALIAS <slug>`.
- **fieldinfo needs the `id` hash, not the slug**: `/api/segment/<slug>/fieldinfo` returns HTTP 500. Resolve the id via `GET /v2/segment` first.
- **validate and size take raw FilterQL text** (`Content-Type: text/plain`), not JSON.
- **`fieldsuggest` requires `q`**: `/api/schema/user/fieldsuggest/<field>?q=<query>`.
- Delete is irreversible; say so at the confirmation gate.

## Modes

Read the mode file before acting in that mode.

| Mode | When | File |
|---|---|---|
| build | The user describes a specific audience ("US users who visited 5+ times") or wants a FilterQL expression written or validated | `build.md` |
| advise | The user states a business goal ("drive more purchases") or wants an existing segment improved | `advise.md` |
| snapshot | The user wants to know what a segment looks like: demographics, top values, coverage, distributions, comparisons | `snapshot.md` |
| manage | List, get, ancestors, create from a ready payload, update, delete, validate, size, reevaluate | `manage.md` |

Typical sequence: advise -> build -> snapshot. A goal-oriented build request should start in advise; after any create, offer a snapshot.

## Related skills

- `lytics-schema`: find which fields exist, their types, and value distributions before mapping concepts to fields; add a missing field.
- `lytics-profiles`: look up an individual profile and the segments it belongs to.
- `lytics-content`: set up or curate content topics when affinities are not configured for advise mode.
- `lytics-integrations`: export or activate a segment to a destination once it exists.
- `lytics-flows`: use a segment as a flow entry audience.
- `lytics-account`: copy a segment to another account.
