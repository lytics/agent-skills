---
name: lytics-account
description: "Lytics CDP: manage a Lytics account -- list users and their roles, invite users, change roles, remove users; list, create, rotate, and revoke API tokens and their scopes and expiry; read and change account settings (including IP allowlist and 2FA/password security settings); and copy metadata (segments, schema, flows, jobs, connections, auth, webhook templates) and account configuration (settings, per-table idconfig, field rankings) between two Lytics accounts, e.g. sandbox to production, with dry-run, diff, compare, and resume. Use when the user asks who has access to an account, what roles exist, to add/remove a user or change their permissions, to create or revoke an API key/token, to view or change an account setting, or to sync, copy, promote, or compare objects between accounts. Cross-account sync and every write run only when the user explicitly asks for them."
license: MIT
---

# Account

Account management for Lytics: users and roles, API tokens, and settings on the current account, plus copying metadata and configuration between two accounts (sync, compare, resume). Reads are safe; every write changes who can reach the account or what it does, so nothing is written unless the user explicitly asks.

## Before you start
- Credentials: `references/auth.md`. Single-account modes use `LYTICS_API_TOKEN` / `LYTICS_API_URL`; sync uses two accounts and the **Multi-Account** section (profile config, `src` / `dst` helpers).
- Request conventions and error shapes: `references/api.md`. Users and tokens mostly use `/v2` (errors in `.errors[0].message`); settings and token creation use `/api` (errors in `.message`).
- Every write goes through `references/confirmation-gate.md`. Removals and revocations also need an explicit "this cannot be undone" in the summary.
- FilterQL parsing (sync, for `INCLUDE slug`): `references/filterql-grammar.md`.

## Gotchas

Users, roles, tokens, settings:
- **Role updates are a full replace.** `POST /v2/user/{id}/roles` sets the user's whole role list on this account; send current roles plus the change ([users.md](users.md#set-a-users-roles)).
- **Role slugs are not validated on users**: a typo is stored and grants nothing. Check slugs against `GET /v2/account/{aid}?roles=true` -> `roles_available` (`can_be_assigned: true`).
- **`POST /v2/user` on an existing member resets their roles** here and on every child account (to only `authed2` if `roles` is omitted). Use it only to invite.
- **Removing a user is irreversible**: `DELETE /v2/user/{id}` drops their access, and deletes the user entirely if this was their last account. The API has no last-admin check; never leave the account without an `admin`, and don't remove or demote the caller unless asked.
- **Token creation needs a user (login) token.** `POST /api/auth/createtoken` with an API token returns `403 This endpoint is available only via user tokens.`
- **A token's value is shown once**, in the create response; reads never return it. A token created without `expires` never expires.
- **Revoking a token is a permanent delete** (`DELETE /v2/auth/{id}`); every client using it breaks. The same endpoint deletes integration credentials, so confirm `type == "lytics-auth-token"`; never revoke `internal` tokens or the session's own token.
- **`api_ip_whitelist` can lock everyone out**, this session included: requests from IPs outside it get 403, and a locked-out caller cannot undo it. Security-category settings change every user's login. Both need a retype gate ([settings.md](settings.md#high-risk-settings)).

Sync between accounts:
- **Every call goes through the `src` / `dst` helpers** from `references/auth.md`, never `LYTICS_API_URL` / `LYTICS_API_TOKEN` -- an env-prefixed call silently hits the ambient account, so a "sandbox to prod" run can overwrite the sandbox source. This applies to every snippet borrowed from a peer skill.
- **Same-account guard**: resolve each profile's own aid (`references/auth.md`); halt if either aid fails to resolve or the two match. Print both aids in the plan header.
- **Jobs are created with `POST /v2/job?run_job=false`.** `run_job` defaults to `true`, so a synced export would start sending immediately. Never auto-start a job ([writes.md](writes.md#jobs)).
- **Job updates are full-object PUTs.** `PUT /v2/job/{workflow}/{id}` clears omitted `description`, quiet-window fields, `expires_at`, `meta`, `hidden`, `verbose_logging`, and a sent `config` replaces the stored one wholesale.
- **Writable is not the same as safe to copy.** `can_be_assigned: true` only means the API accepts a write. `security`/`API` categories, `cull_user_filter`, `workflow_exclude_segments`, `enable_schema_patches`, `schema_user_private_fields` are excluded from `sync settings` ([sync-settings.md](sync-settings.md#writable-is-not-the-same-as-safe-to-copy)).
- **`idconfig` needs an extra retype gate**: after the plan `yes`, the user must type exactly `confirm idconfig <table>`; it can re-merge every profile in the destination ([sync-settings.md](sync-settings.md#idconfig-requires-an-extra-confirmation-gate)).
- **Never write a setting with `can_be_assigned: false`** (403). Classify it `drift-readonly`; refuse an explicit `sync setting <slug>` for it.
- **Never leave an orphan draft schema patch.** On halt, delete it (or prompt to apply); only a failed `apply` leaves the draft for inspection ([safety.md](safety.md#in-flight-schema-patch-cleanup)).
- **Schema-write mode** comes from `dst /api/account/setting/enable_schema_patches`, not from listing patches (that returns 200 everywhere); re-probe after a settings phase.
- **Stop on first error**; never auto-copy OAuth auths; flow `running` state is never copied as `running`.
- **Never alter the trace-line or schema publish-tag formats** ([normalization.md](normalization.md#traceability), [writes.md](writes.md#schema-fields-and-mappings)): already-synced destination objects carry them and compare strips that exact pattern.

## Modes
Read the mode file before acting in that mode.

| Mode | When | File |
|------|------|------|
| users | Who is on the account, what roles exist, invite a user, change roles, remove a user | [users.md](users.md) |
| tokens | List or inspect API tokens, create one, rotate, revoke | [tokens.md](tokens.md) |
| settings | Read or change a setting on the current account | [settings.md](settings.md) |
| sync | Copy objects or settings from one account to another (`sync <type> ... from <src> to <dst>`) | [sync.md](sync.md), then [workflow.md](workflow.md) |
| compare | Read-only audit of two accounts (`compare [<type>] from <src> to <dst>`) | [sync.md](sync.md), [workflow.md](workflow.md) |
| resume | Continue a halted sync from its manifest (`resume <manifest-path>`) | [workflow.md](workflow.md), [safety.md](safety.md) |

Sync topic files (read the one for the step you are on): [dependencies.md](dependencies.md), [normalization.md](normalization.md), [writes.md](writes.md), [sync-settings.md](sync-settings.md), [safety.md](safety.md). [sync.md](sync.md) has the full verb grammar, types, selectors, flags, and step list.

## Related skills
- the `lytics-audiences` skill -- segment create/update conventions; single-account segment work.
- the `lytics-schema` skill -- schema patches, direct publish, idconfig/rank endpoints, `enable_schema_patches` migration.
- the `lytics-flows` skill -- flow payloads.
- the `lytics-integrations` skill -- jobs, connections, integration auths, webhook templates; starting a synced job (created with `run_job=false`).
