# Safety and Error Handling

Safety layers, the idempotency invariant, error handling, in-flight schema patch cleanup, known risks, and peer-skill docs drift. Read before any non-dry-run sync and whenever a run halts.

## Safety Layers

Applied in this order of defense:

1. **`--dry-run` / `compare`** -- no writes. The plan is the only output.
2. **Plan preview + confirmation gate** -- mandatory on any non-dry-run invocation. Follows `references/confirmation-gate.md`.
3. **Bulk-operation gate** -- `all` and `--prefix` selectors (and `compare` across all types) require a second confirmation showing the object count and a sample of up to 5 names. If count > 50, require the user to retype `confirm <count>` to proceed.
4. **Retype gate for `idconfig`** -- in addition to the standard confirmation, every `idconfig` write requires the user to retype `confirm idconfig <table>` verbatim. See [sync-settings.md](sync-settings.md#idconfig-requires-an-extra-confirmation-gate).
5. **Stop-on-first-error** -- no silent continuation past failures. Partial successes remain in the destination; the manifest records `success`, the failed op, and every untouched `pending` op so the user can resume via `resume <manifest>` or `sync ... --resume <manifest>`.
6. **Read-after-write verification** -- after every successful write, GET the object and diff against expected ([normalization.md](normalization.md#read-after-write-verification)). Record `server_drift` in the manifest.
7. **In-flight patch cleanup on halt** -- draft schema patches are never left orphaned; see In-Flight Schema Patch Cleanup (below).
8. **Schema-mode re-probe after settings phase** -- if a run touches settings and schema in the same invocation, re-probe the destination schema-write mode between the two phases. A setting change may have altered the mode and the cached pre-settings decision is stale.
9. **Manifest** -- written to `~/.lytics/sync/<ISO8601>-<src>-to-<dst>.json` on every run (including aborted ones where at least one write succeeded).

### Idempotency Invariant

A successful `sync` run followed immediately by the **same command** must yield **0 writes**. This invariant is load-bearing: it's what makes `resume` safe, what makes dry-runs trustworthy, and what makes retries non-destructive.

Things that break the invariant if implemented naively, and the mitigations in this skill:

| Risk | Mitigation |
|------|------------|
| Trace line carries the current date; date changes across runs so string equality fails | Strip `^\s*\[account-sync\] .*$` from every description-like field before comparing ([normalization.md](normalization.md)) |
| Server re-serializes durations with drifting sub-microsecond precision | Normalize `<h>h<m>m<s>s` to integer seconds before comparing ([normalization.md](normalization.md)) |
| Server auto-assigns fields (e.g., `public_name`) not present in source | Strip via server-assigned field registry ([normalization.md](normalization.md)) |
| Cross-account hex IDs in FilterQL INCLUDE refs differ even when logical refs match | Resolve hex to slug on both sides before comparing ([normalization.md](normalization.md)) |
| Account-scoped group IDs differ across accounts | Strip `groups` on compare by default (Groups Policy, [normalization.md](normalization.md#groups-policy)) |
| Account setting descriptor metadata (`field`, `category`, ...) may drift across deployments | Strip via server-assigned field registry ([normalization.md](normalization.md)); only `value` is compared |
| `can_be_assigned: false` settings cannot be written -- attempting a correction would loop forever | Classify read-only drift as `drift-readonly`, never `update`; never attempt the write |
| Template body whitespace drifts on server re-save (trailing whitespace, line endings) | Trim trailing whitespace per line and normalize line endings to `\n` on both sides before comparing (see Templates in [writes.md](writes.md#templates)) |
| Two templates with the same name but different `type` collide on natural-key lookup | Disambiguate on `(name, type)`, never `name` alone |
| Webhook job `config.template_id` from src is an account-scoped hex that doesn't exist in dst | Walk + remap via the in-run template map; if unmapped, halt with a blocker rather than writing a broken reference |

If you are implementing a change to the skill and it breaks idempotency, that's the bug.

## Error Handling

- **401 on either profile** -- fail fast with a clear message naming which profile's token was rejected. Do not proceed.
- **404 on source object** -- reject the selector clearly; list close matches from the source's object list.
- **404 on `GET /v2/schema/{table}/idconfig`** -- idconfig is not set on this account, not an error. Error message may misleadingly say `"Could not find rank settings for table <table>"`. Status code is authoritative. Treat as empty idconfig.
- **403 on `PUT /api/account/setting/{slug}`** with message `"Not authorized: This setting \"<slug>\" is not editable, talk to your account manager."` -- the setting's `can_be_assigned` is `false`. The skill should have caught this client-side during classification and never issued the write; if this fires, it's a bug in the skill. Halt the settings phase and report.
- **400 on `PUT /api/account/setting/{slug}`** -- value type mismatch against `field.type`. Surface the server's message; usually the fix is client-side type coercion (e.g., boolean `true` vs string `"true"`).
- **409 on destination create** -- a natural-key race happened (something was created between the dest-lookup and the write). Re-classify as `update` and re-prompt with an amended plan.
- **422 on validation** (segment FilterQL, schema patch apply) -- surface the full message and halt. Usually indicates a missing upstream dep that should have been caught in Step 3 ([dependencies.md](dependencies.md)).
- **Rate limit (429)** -- respect `references/api.md`'s guidance. Back off briefly and retry once. Do not silently drop an op.
- **Network / transient errors** -- retry once; on second failure, treat as a hard failure and halt.

### In-Flight Schema Patch Cleanup

A schema patch is created at the start of a schema-patch-path run, populated with field/mapping changes, and applied at the end. Halts between create and apply leave the patch in `draft` state. **Never leave an orphan draft patch.**

Required cleanup on halt (must execute before the run exits, regardless of exit cause):

1. Identify in-flight patch: the last `schema.patch` `create` entry in the manifest with no corresponding `apply` or `delete`.
2. If all field/mapping operations for that patch are recorded as `success` in the manifest, you MAY attempt to apply it (typically only appropriate when the halt was in a later, non-schema op). Prompt the user; do not silently apply.
3. Otherwise, **delete the patch**: `DELETE /v2/schema/patch/{table}/{patch_id}`. Record the deletion in the manifest as a compensating op.
4. If the delete itself fails, surface the patch ID + `GET /v2/schema/patch/{table}/{patch_id}` URL in the halt message so the user can clean up manually.

**Schema patch `apply` fails**: by contrast, if `apply` specifically is what failed, leave the patch in `draft` so the user can inspect it. Surface the patch ID and GET URL; do NOT auto-delete.

## Known Risks

- **Job `config` is workflow-specific.** The skill remaps `segment_id` and `auth_ids`; other config keys are copied verbatim. Every job op in the plan carries a "review config carefully" note.
- **No API transaction support.** Partial-failure recovery relies on upsert idempotency + the manifest.
- **OAuth auths cannot be automated.** The missing-auth blocker is the only path -- user must complete OAuth in the destination UI.
- **Traceability line is visible in the UI.** Users who don't want it on prod descriptions should use `--no-trace`.
- **`all` on large accounts can be very big.** The bulk gate helps; first-time users should start with a single object or `--prefix`.
- **Schema patches are preferred but not all accounts have them enabled.** The skill detects mode per destination and falls back to direct publish when needed.
- **Server-side write drift.** Some fields may be normalized by the server after a write. Read-After-Write Verification catches this post-hoc; it does not prevent it. See Known drift classes in [normalization.md](normalization.md#known-drift-classes) for the current list.
- **Groups are not synced by default.** Segment `groups` arrays hold account-scoped IDs and would fail naive copy. Opt in with `--sync-groups` (see Groups Policy in [normalization.md](normalization.md#groups-policy)).
- **Account settings have no trace line.** Manifest is the sole audit record for settings ops; `--no-trace` is silently ignored for settings.
- **`idconfig` can re-merge profiles in the destination.** Blast radius is potentially every profile in the account; the retype gate is the only in-skill mitigation. Coordinate with the dst account owner before syncing `idconfig`.
- **Read-only settings cannot be forced.** If a setting with `can_be_assigned: false` differs between accounts, the skill classifies it as `drift-readonly` and surfaces it in the plan but never attempts a write. Corrections require platform-level (non-API) intervention.
- **Some settings have side effects on write.** `ReloadQuery`-flagged settings trigger a linkgrid reload; `content_allowlist_field`/`content_blocklist_field` additionally sync affinity config. Expect higher write latency and brief cache coldness in the destination.
- **Settings API path is `/api/`, not `/v2/`.** Easy to mistype given the rest of the skill lives at `/v2/`. Also note: the resource is `setting` (singular), not `settings`.
- **Webhook templates have no trace line.** The body is the artifact; the `description` is short and user-owned. The manifest is the sole audit record for `template` ops; `--no-trace` is silently ignored. Webhook jobs that reference a template have `config.template_id` automatically remapped via the in-run template map; if a job is synced without its template, the run halts with a blocker rather than writing a broken reference.

## Docs Drift (Peer Skills vs Real API)

This skill composes knowledge from peer skills (`lytics-schema`, `lytics-audiences`, `lytics-flows`, etc.). Those skills' example payloads are usually right, but can drift from the actual API over time.

Known drift found and fixed in this repo:

- `lytics-schema`'s schema-patch examples previously showed `name` for patch creation and capitalized keys (`Field`, `Type`, `ShortDesc`, `MergeOp`, `IsIdentifier`, `IsPII`) for adding fields to a patch. The actual patch endpoint requires `tag` (kebab-case) and lowercase field keys (`id`, `type`, `shortdesc`, `mergeop`, `is_identifier`, `is_pii`). Fixed in `lytics-schema/SKILL.md`.

When a write fails with a payload-shape error ("`X` is required for `Y`", `BADREQ-001`, `422`), don't assume the docs are correct. **Probe the endpoint:** create a disposable patch/resource and try two or three payload shapes (capitalized, lowercase, `id` vs `Field`, wrapped vs flat) until one returns 200. Clean up the disposable resource and fix the peer skill's docs as a follow-up.
