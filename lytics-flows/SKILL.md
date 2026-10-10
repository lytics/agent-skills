---
name: lytics-flows
description: "Lytics CDP: design, create, view, update, activate and delete flows (customer journeys / campaigns) -- guided journey design from business intent into a node/edge payload with an entry segment, delays, conditional branches and export steps, configuring and publishing each export step's work, activating the flow, plus flow/journey CRUD, version reads, and flow state listing. Use when the user wants to create a campaign, build a journey, design a multi-step marketing flow (welcome series, re-engagement, multi-channel nurture), or list, view, create, update, activate, or delete flows, journeys, or campaign steps."
license: MIT
---

# Lytics Flows

Flows are Lytics customer journeys: a trigger segment, then delays, conditional splits, export steps, and exits. This skill takes a user from business intent ("I want a welcome email series") to a validated, created and activated flow, and covers day-to-day flow management (list, get, update, delete, state). Flows are the most complex Lytics object; follow the mode file rather than improvising payloads.

## Before you start

- Credentials: `references/auth.md`.
- Request and response conventions (including where `/v2` errors live: `.errors[0].message`): `references/api.md`.
- Every create, update, state change and delete goes through `references/confirmation-gate.md`. For state changes and deletes, spell out the consequence in the summary.
- Write conditions in FilterQL: `references/filterql-grammar.md`.

## Gotchas

- **Condition priority: lower number is checked first, first match wins.** Give the most specific condition the smallest number. The fallback edge (`"definition": ""`, `"priority": 1`) is taken out of the ordering and used only when nothing else matches.
- **Do not build A/B splits.** `/v2/flow/ui` ignores edge `probability`: an `ab_test` node saves without error and then sends every user down a single branch (the other branch is silently dropped). Tell the user to set the split up another way and verify it before the flow runs.
- **`DELETE /v2/flow/ui/{id}` without a version permanently removes every version, including a running one.** No soft delete, no undo. To remove one version use `DELETE /v2/flow/ui/{id}/{version}`.
- **Write with the node/edge (TranslatedFlow) format.** The `steps` / `type_hint` model is the internal `/v2/flow` representation; it is a read-only reference here, not a `/v2/flow/ui` payload (see `manage.md`).
- **Units differ per field:** trigger `reentry_delay` is in **seconds** (minimum 3600); delay node `delay` is in **nanoseconds** (24h = `86400000000000`).
- **Only one version can be `running`.** Publishing a new version automatically sets the old one to `draining`.

## Modes

Read the mode file before acting in that mode.

| Mode | When | File |
|---|---|---|
| build | The user describes a campaign or journey to create: design it, build the node/edge payload, create it, configure export work, activate | `build.md` |
| manage | List, view, version, update, change state of, or delete existing flows; list flow states | `manage.md` |

## Related skills

- `lytics-audiences` -- the flow's entry segment, or a segment a condition depends on, does not exist yet; create it there, then come back.
- `lytics-integrations` -- the export steps need a connection/auth or job set up, an export step's work needs debugging as a job, or a running flow's export step is not delivering (export-debug mode).
- `lytics-schema` -- a condition references a field and you need to confirm it exists and its type.
- `lytics-account` -- copying flows between accounts (e.g. sandbox to prod).
