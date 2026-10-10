---
name: lytics-profiles
description: "Lytics CDP: find, explore, diagnose, and delete individual user profiles. Look up a profile by email, user ID, _uid, or any identity field; view its attributes, linked identities, segment memberships, and event history; explain why a user is or isn't in a segment by checking each FilterQL condition against the profile; trace data lineage (which streams and fragments supplied each field); hard- or soft-delete a profile. Use when the user wants to find or look up a specific user profile, explore a profile, see what segments a user is in, browse event history for an identity, compare two users, debug why a profile qualifies or doesn't qualify for a segment, understand \"what happened to this user\", trace data lineage, or delete a user profile."
license: MIT
---

# Lytics Profiles

Everything about a single profile (entity): looking it up by identity, exploring its attributes, memberships and activity, diagnosing segment membership against FilterQL, tracing where its data came from, and deleting it.

## Before you start

- Credentials: `references/auth.md`.
- Calling conventions, the `/v2` vs `/api` response shapes, and URL-encoding: `references/api.md`. Identity values (emails with `@`) must be URL-encoded in the path.
- Reads run immediately. Every delete goes through `references/confirmation-gate.md`.
- Account-specific identity fields: `GET /v2/schema/{table}/idconfig`. Common ones: `email`, `_uid`, `user_id`.

## Gotchas

- **Not found is a 200.** `/api/entity` answers a missing profile with HTTP 200, `message: "Not Found"` (or `"Timed out"`) and a placeholder `{"segments": ["not_found", "all"]}`. Never present that as a real profile in segment `all`; check `.message` and the `not_found` segment, or use `/v2/identity`, which does return 404.
- **Value-only lookup means `_uid`.** `GET /api/entity/{table}/{value}` looks the value up as `_uid` only; it does not search other identity fields. For an email or external id, use `/api/entity/{table}/{field}/{value}`.
- **Both deletes are irreversible through the API.** Hard delete is async (poll `/api/entity/deletestatus/{request_id}`) and defaults to `conflicts=true`, a greedy identity traversal that can reach identifiers beyond the profile a lookup shows; offer `?conflicts=false`. Soft delete cannot be undone either: the undelete endpoint is deprecated, returns 401, and has no replacement.
- **Soft delete returns 200 even when no such profile exists**, so a 200 confirms nothing was deleted.
- **A FilterQL field missing from the profile** is often the root cause of a "why isn't this user in X" question; report it as "field not present", not as a value mismatch.

## Modes

Read the mode file before acting in that mode.

| Mode | When | File |
|---|---|---|
| lookup | Find a profile by identity field/value; list its segment memberships; delete a profile (hard or soft) | `lookup.md` |
| explore | Comprehensive view of one profile: identity, key attributes, memberships, recent activity; compare users; help find a user when no identity is known | `explore.md` |
| investigate | Why is/isn't this user in segment X (condition-by-condition PASS/FAIL); "what happened to this user" data lineage via `?explain=true` | `investigate.md` |

## Related skills

- `lytics-audiences`: list or scan segment members to find a user, look up a segment by name/slug, or change a segment's FilterQL after a diagnosis shows it is wrong.
- `lytics-schema`: identity fields, field types, and mappings when a profile field is missing or mis-mapped.
- `lytics-data-health`: recent events on a stream, when a profile's data looks stale or a source stream stopped.
