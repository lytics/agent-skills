---
name: lytics-account-sync
description: "Lytics CDP: copy metadata (segments, schema, flows, jobs, connections, auth, webhook templates) and account-level configuration (settings, per-table idconfig, field rankings) between two Lytics accounts, e.g. sandbox to production, with dry-run, diff, and a confirmation gate. Use only when the user explicitly asks to sync, copy, promote, or compare objects between Lytics accounts -- it writes to the destination account."
license: MIT
---

# Account Sync

Copy metadata between two Lytics accounts safely. Supports segments, schema fields and mappings, flows, jobs, connections, auth providers, webhook templates, and account settings. Handles the hard parts that break naive copy: internal-ID remapping, dependency traversal, upsert-by-natural-key, schema-patches workflow, and OAuth pauses.

## Before you start
- Unlike other skills, `lytics-account-sync` operates against **two** accounts per invocation. See the **Multi-Account** section of `references/auth.md` for credential resolution (profile config, fallback prompts, per-call env overrides).
- Request conventions and error shapes: `references/api.md`.
- Every write goes through `references/confirmation-gate.md`.
- FilterQL parsing (for `INCLUDE slug`): `references/filterql-grammar.md`.

## Gotchas
- **Every call goes through the `src` / `dst` helpers** from `references/auth.md`, never `LYTICS_API_URL` / `LYTICS_API_TOKEN` -- an env-prefixed call silently hits the ambient account, so a "sandbox to prod" run can overwrite the sandbox source. This applies to every snippet borrowed from a peer skill.
- **Same-account guard**: resolve each profile's own aid (`references/auth.md`); halt if either aid fails to resolve or the two match. Print both aids in the plan header.
- **Jobs are created with `POST /v2/job?run_job=false`.** `run_job` defaults to `true`, so a synced export would start sending immediately. Never auto-start a job ([writes.md](writes.md#jobs)).
- **Job updates are full-object PUTs.** `PUT /v2/job/{workflow}/{id}` clears omitted `description`, quiet-window fields, `expires_at`, `meta`, `hidden`, `verbose_logging`, and a sent `config` replaces the stored one wholesale.
- **Writable is not the same as safe to copy.** `can_be_assigned: true` only means the API accepts a write. `security`/`API` categories, `cull_user_filter`, `workflow_exclude_segments`, `enable_schema_patches`, `schema_user_private_fields` are excluded from `sync settings` ([settings.md](settings.md#writable-is-not-the-same-as-safe-to-copy)).
- **`idconfig` needs an extra retype gate**: after the plan `yes`, the user must type exactly `confirm idconfig <table>`; it can re-merge every profile in the destination ([settings.md](settings.md#idconfig-requires-an-extra-confirmation-gate)).
- **Never write a setting with `can_be_assigned: false`** (403). Classify it `drift-readonly`; refuse an explicit `sync setting <slug>` for it.
- **Never leave an orphan draft schema patch.** On halt, delete it (or prompt to apply); only a failed `apply` leaves the draft for inspection ([safety.md](safety.md#in-flight-schema-patch-cleanup)).
- **Schema-write mode** comes from `dst /api/account/setting/enable_schema_patches`, not from listing patches (that returns 200 everywhere); re-probe after a settings phase.
- **Stop on first error**; never auto-copy OAuth auths; flow `running` state is never copied as `running`.
- **Never alter the trace-line or schema publish-tag formats** ([normalization.md](normalization.md#traceability), [writes.md](writes.md#schema-fields-and-mappings)): already-synced destination objects carry them and compare strips that exact pattern.

## Invocation

Three verbs, one grammar:

```
sync    <type> <selector> from <src-profile> to <dst-profile> [flags]   # create/update in dst
compare [<type>]          from <src-profile> to <dst-profile> [flags]   # never write; full audit
resume  <manifest-path>                                      [flags]    # continue a halted run
```

Examples:
- `sync segment high-value-customers from sandbox to prod`
- `sync flow welcome-series from sandbox to prod --dry-run`
- `sync all schema from sandbox to prod --diff`
- `sync segments --prefix beta_ from sandbox to prod`
- `sync settings from sandbox to prod` (all account settings + per-table idconfig + rank)
- `sync setting onboarding_question_vertical from sandbox to prod`
- `sync idconfig user from sandbox to prod`
- `sync template qualtrics_audience_trigger from sandbox to prod`
- `sync templates --prefix qualtrics_ from sandbox to prod`
- `sync all templates from sandbox to prod`
- `compare templates from sandbox to prod`
- `compare from sandbox to prod` (full inventory audit; reports by type)
- `compare segments from sandbox to prod --deep`
- `resume ~/.lytics/sync/2026-04-16T20-38-25Z-sandbox-to-prod.json`

### Types
`segment`, `schema` (fields + mappings), `flow`, `job`, `connection`, `auth`, `template` (webhook templates), `settings` (account-level config: `account.setting`, `account.idconfig`, `account.rank` as a bundle), plus the individual settings types `setting` (single key from `account.setting`), `idconfig`, `rank`. Plural forms are accepted (`segments`, `flows`, `templates`, etc.). `all` works with any type (`sync all flows ...`).

### Selectors (sync only)
- **By name/slug**: `sync segment high_value_customers from sandbox to prod`
- **All of type**: `sync all segments from sandbox to prod` (triggers bulk gate, see [safety.md](safety.md#safety-layers))
- **Prefix**: `--prefix <string>` -- matches objects whose natural key starts with the string (e.g., `--prefix beta_`)

### Flags
| Flag | Applies to | Effect |
|------|------------|--------|
| `--dry-run` | sync | Build and render the full plan; never write to destination. |
| `--create-only` | sync | Refuse to update existing destination objects. Overrides default upsert behavior. |
| `--diff` | sync, compare | Render a field-level diff per `update` / `differs` op. |
| `--deep` | sync, compare | Use transitive equivalence instead of shallow equality for segments; see [dependencies.md](dependencies.md#transitive-equivalence). |
| `--no-trace` | sync | Do not append/replace the `[account-sync]` traceability line in descriptions. |
| `--sync-groups` | sync | Remap segment `groups` across accounts. Default off (see [normalization.md](normalization.md#groups-policy)). |
| `--resume <path>` | sync | Skip operations already marked `success` in the manifest; only process `pending`. Equivalent to `resume <path>`. |

## Steps (in brief)
1. **Resolve profiles** and both aids; same-account guard -- [workflow.md](workflow.md#step-1-resolve-profiles).
2. **Select source objects** from the selector; bulk gate for `all` / `--prefix` -- [workflow.md](workflow.md#step-2-select-source-objects).
3. **Build dependency graph** (walk every reference, topological sort, fail on cycles) -- [dependencies.md](dependencies.md#step-3-build-dependency-graph).
4. **Resolve destination state** by natural key after normalizing both sides; classify `create` / `update` / `skip` / `conflict` / `drift-readonly` / `excluded` -- [dependencies.md](dependencies.md#step-4-resolve-destination-state-per-object), [normalization.md](normalization.md).
5. **Render plan** (stop here under `--dry-run`) -- [workflow.md](workflow.md#step-5-render-plan).
6. **Confirmation gate**, plus bulk and `idconfig` retype gates -- [workflow.md](workflow.md#step-6-confirmation-gate), [safety.md](safety.md#safety-layers).
7. **Execute in topological order**: remap, trace, per-type write, read-after-write -- [workflow.md](workflow.md#step-7-execute-in-topological-order), [writes.md](writes.md), [settings.md](settings.md) (settings run first).
8. **Write manifest** to `~/.lytics/sync/<ISO8601>-<src>-to-<dst>.json` -- [workflow.md](workflow.md#step-8-write-manifest).

## Topic files
Read the file before acting on that part of a run.

| File | Covers |
|------|--------|
| [workflow.md](workflow.md) | Compare mode, resume mode, end-to-end Steps 1-8, plan format, manifest format |
| [dependencies.md](dependencies.md) | Reference map (walk vs remap), natural keys, classification, cross-reference remapping, dependency conflicts, `--deep` transitive equivalence |
| [normalization.md](normalization.md) | Server-assigned field registry, trace-line stripping, duration precision, hex-ID INCLUDE resolution, groups policy, traceability, read-after-write verification |
| [writes.md](writes.md) | Per-type writes: segments, schema fields/mappings (patch vs direct publish), flows, jobs, connections, templates, auth; `is_public`/`public_name`; tag format rules |
| [settings.md](settings.md) | `account.setting` endpoints and shape, `can_be_assigned`, exclusion table, write-path probe, `idconfig` gate and 404s, phase ordering, settings selectors and manifest ops |
| [safety.md](safety.md) | Safety layers, idempotency invariant, error handling, in-flight patch cleanup, known risks, peer-skill docs drift |

## Related skills
Composes knowledge from these; hand off to them for single-account work:
- the `lytics-audiences` skill -- segment create/update conventions.
- the `lytics-schema` skill -- schema patches, direct publish, idconfig/rank endpoints.
- the `lytics-flows` skill -- flow payloads.
- the `lytics-integrations` skill -- jobs, connections, auth; starting a synced job (created with `run_job=false`).
- the `lytics-webhook-templates` skill -- template body handling and Probing Notes.
