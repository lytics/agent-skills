---
name: account-sync
description: Copy metadata (segments, schema, flows, jobs, connections, auth) and account-level configuration (settings, per-table idconfig, field rankings) between Lytics accounts. Use when the user wants to promote changes from a sandbox account to production, sync objects between accounts, or copy an object from one account to another.
metadata:
  arguments: object type, selector, source profile, destination profile, and optional flags -- sync <type> <selector> from <src> to <dst> [--dry-run] [--create-only] [--diff] [--no-trace]
---

# Account Sync

## Purpose
Copy metadata between two Lytics accounts safely. Supports segments, schema fields and mappings, flows, jobs, connections, and auth providers. Handles the hard parts that break naive copy: internal-ID remapping, dependency traversal, upsert-by-natural-key, schema-patches workflow, and OAuth pauses.

## Environment
Unlike other skills, `account-sync` operates against **two** accounts per invocation. See the **Multi-Account** section of `../references/auth.md` for credential resolution (profile config, fallback prompts, per-call env overrides).

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
- **All of type**: `sync all segments from sandbox to prod` (triggers bulk gate, see Safety Layers)
- **Prefix**: `--prefix <string>` -- matches objects whose natural key starts with the string (e.g., `--prefix beta_`)

### Flags
| Flag | Applies to | Effect |
|------|------------|--------|
| `--dry-run` | sync | Build and render the full plan; never write to destination. |
| `--create-only` | sync | Refuse to update existing destination objects. Overrides default upsert behavior. |
| `--diff` | sync, compare | Render a field-level diff per `update` / `differs` op. |
| `--deep` | sync, compare | Use transitive equivalence instead of shallow equality for segments; see Transitive Equivalence. |
| `--no-trace` | sync | Do not append/replace the `[account-sync]` traceability line in descriptions. |
| `--sync-groups` | sync | Remap segment `groups` across accounts. Default off (see Groups Policy). |
| `--resume <path>` | sync | Skip operations already marked `success` in the manifest; only process `pending`. Equivalent to `resume <path>`. |

### Compare Mode

`compare` is a read-only audit. It produces the same per-type plan that `sync --dry-run` would produce, but:

- Omitting `<type>` runs the audit across **all** supported types in one pass.
- No selector is required; by default every object of each requested type is compared.
- No traceability line is considered during comparison (the plan still tells you whether a trace line is the only thing that would change on write, so you can judge idempotency).
- No writes under any circumstance, regardless of confirmation. The user's "yes" is never solicited.
- Output is the plan body only; manifest is optional (`--write-manifest` to emit one).

When to use it: "what's different between these accounts?" -- the question that came up in this session. When to use `sync --dry-run` instead: "if I ran `sync <selector> ...` right now, what would it do?"

### Resume Mode

`resume <manifest-path>` re-opens an existing manifest and continues a previously halted run:

1. Load the manifest; refuse if `status == "success"` (nothing to resume).
2. Verify the source and destination profiles still resolve and still authenticate.
3. For each entry in `operations` with `status == "success"`, skip (already done).
4. For each entry in `pending` (plus the halted op if recoverable), re-plan it against the current source and destination state (upstream state may have changed since the halt).
5. Render a resume plan showing what remains; require confirmation as normal.
6. Execute. Append new operations to the **same manifest file** rather than creating a new one.

Resume is the supported answer to "the run halted midway; what do I do?" Users should not manually re-run the original `sync` command unless they want the planner to re-evaluate everything from scratch.

## End-to-End Flow

### Step 1: Resolve Profiles
1. Read `~/.lytics/accounts.toml`. If missing, proceed with prompt-only fallback.
2. Resolve `<src-profile>` and `<dst-profile>` to `{token, url}` pairs. Prompt per missing entry.
3. Ping each with a cheap read (e.g., `GET /v2/account` or `GET /v2/schema`). Fail fast on 401 with a clear message naming which profile's token was rejected.

### Step 2: Select Source Objects
Translate the selector into a concrete list of source objects:

| Selector | Source endpoint(s) |
|----------|--------------------|
| Single segment | `GET /v2/segment?sizes=false` then filter by `slug_name`, or `GET /v2/segment/{id}` if id-like |
| All segments | `GET /v2/segment` |
| Segment prefix | List + filter client-side on `slug_name` |
| Single schema field/mapping | `GET /v2/schema/{table}/field/{id}` or `/mapping/{id}` |
| All schema | `GET /v2/schema/{table}/field` + `GET /v2/schema/{table}/mapping` |
| Single flow | `GET /v2/flow/ui/{id}` |
| All flows | `GET /v2/flow/ui` |
| Single/all job | `GET /v2/job` (add `show_completed=true&show_deleted=false` when broad) |
| Single/all connection | `GET /v2/connection` |
| Single/all auth | `GET /v2/auth` |
| Single template | `GET /v2/template` then filter by `name` (or `GET /v2/template/{id}` if id-like). Source body fetched per-template via `GET /v2/template/{id}` (list response is metadata-only). |
| All templates | `GET /v2/template`, then `GET /v2/template/{id}` per row to fetch body |
| Template prefix | List + filter client-side on `name` |
| All account settings | `GET /api/account/setting` (note: `/api/`, not `/v2/`; singular `setting`) |
| Single account setting | `GET /api/account/setting/{slug}` |
| Per-table idconfig | `GET /v2/schema/{table}/idconfig` -- 404 means "not set on this account," not an error |
| Per-table field rank | `GET /v2/schema/{table}/rank` |
| All settings (bundle) | All three above: the flat `account.setting` list, plus idconfig and rank for each schema table |

For prefix and all-of-type, the **bulk-operation gate** (Safety Layers) fires before continuing.

### Step 3: Build Dependency Graph
Walk references from each selected object to find deps that must exist in the destination. Deps are transitive -- if a flow references a segment that INCLUDEs another segment, all three are nodes.

Every reference below must be **walked** (traversed as a dep edge). Whether it also needs **remapping** (rewriting the value before the destination write) is a separate question, handled in Cross-Reference Remapping.

**Reference map:**

| Object | Reference | How to extract | Walk? | Remap? |
|--------|-----------|----------------|-------|--------|
| Segment | `INCLUDE <slug>` inside `segment_ql` | Regex over the FilterQL text; see `../references/filterql-grammar.md` | Yes -- verify slug exists in dst | No (slugs are account-stable) |
| Segment | `INCLUDE \`<32-char hex>\`` inside `segment_ql` | Regex over the FilterQL text | Yes -- resolve src hex to source slug, verify slug in dst | Yes -- rewrite to dst's own hex for that slug |
| Segment | Schema fields referenced in FilterQL identifiers | Parse FilterQL identifiers against `GET /v2/schema/{table}/field` | Yes -- verify each referenced field exists in dst | No |
| Segment | Prediction refs (e.g., `segment_prediction.\`Premier Likelihood\``) | Parse FilterQL; identifiers namespaced to `segment_prediction.*` indicate model deps | Yes -- verify model/prediction exists in dst via its registry endpoint; if missing, block | No |
| Flow | `entry_segment_id` | Top-level field on the flow payload | Yes | Yes -- hex ID remap via segment map |
| Flow | Segments referenced in `conditional`/`split_conditions` step payloads | Parse FilterQL inside each split condition | Yes | Slugs no; hex IDs yes |
| Flow | Work referenced by `work_export` / `work_export_exit` steps | `work_id` field on the step | Yes -- treat as job/work dep | Yes -- remap via job/work map |
| Job | `config.segment_id` | Export jobs reference a segment | Yes | Yes |
| Job | `config.template_id` | Webhook workflow jobs reference a template (`workflow` matches `webhook_triggers` or `webhook_enrichment`) | Yes -- verify the referenced template exists in dst by `(name, type)` | Yes -- via template map |
| Job | `auth_ids[]` | Every job dep-links its auth providers | Yes -- verify each auth exists in dst by `(label, type)` | Yes |
| Schema mapping | `field` | Mapping target field | Yes -- verify field exists in dst schema | No (field names are stable) |
| Schema mapping | `stream` | Mapping source stream | Yes -- verify stream exists in dst (`GET /v2/stream/names`); if missing, block | No |
| Schema mapping | Fields referenced inside `expr` | LQL expression; parse identifiers (e.g., `` `ltv` ``, `email(email_address)`) | Yes -- verify each referenced field exists in dst | No |
| Connection | Auth via its config | Present in most connection types as an `auth_id` | Yes | Yes |

Topologically sort so deps precede dependents. Detect cycles and fail with a clear listing if found (cycles are rare in real accounts but possible if two segments `INCLUDE` each other).

**Walking vs remapping (why both matter):**

- Walking confirms the dep is reachable in the destination before the parent write runs. A missed walk turns into a runtime validation failure after writes have already started.
- Remapping rewrites account-scoped IDs to the destination's IDs. A missed remap silently writes broken references (e.g., a flow whose `entry_segment_id` points to a segment that doesn't exist in dst).

### Step 4: Resolve Destination State Per Object
For each node in the graph, look up the destination by natural key:

| Type | Natural key | Destination lookup |
|------|-------------|---------------------|
| Segment | `slug_name` | `GET /v2/segment` then filter |
| Schema field | `id` (the field name is stored as the `id` key in read/patch responses) | `GET /v2/schema/{table}/field` then filter |
| Schema mapping | `(field, stream, guard_expr)` -- `guard_expr` is the disambiguator when multiple mappings share `(field, stream)`; `expr` is the value being compared, not part of the key | `GET /v2/schema/{table}/mapping` then filter |
| Flow | `id` (payload's top-level `id`) | `GET /v2/flow/ui/{id}` |
| Job | `(name, workflow)` | `GET /v2/job?show_all=true` then filter |
| Connection | `(label, provider_slug)` | `GET /v2/connection` then filter. The user-facing name is stored as `label`, not `name` |
| Auth | `(label, type)` | `GET /v2/auth` then filter. The user-facing name is stored as `label`, not `name` |
| Template | `(name, type)` | `GET /v2/template` then filter. Two templates of the same name but different `type` could collide on `name` alone, so `type` is part of the key |
| Account setting | `slug` (e.g., `onboarding_question_vertical`) | `GET /api/account/setting` then filter, or `GET /api/account/setting/{slug}` for a single key. Flat key/value on the account; no surrogate ID |
| Account idconfig | `(table)` | `GET /v2/schema/{table}/idconfig`. Table-scoped singleton. 404 means not set on this account (treat as empty, not an error) |
| Account rank | `(table)` | `GET /v2/schema/{table}/rank`. Table-scoped singleton |

Classify each node:
- **create** -- not present in destination.
- **update** -- present; source differs from destination (upsert mode).
- **skip** -- present; source and destination are equivalent (after stripping traceability line).
- **conflict** -- present with same natural key but differing definition while running under `--create-only`, or a dep conflict under any mode. Terminal classification -- the plan surfaces it; see Dependency-Conflict Handling.
- **drift-readonly** -- settings only; source and destination differ but `can_be_assigned: false` so the skill cannot write. Informational; surfaced in the plan but never executed.

### Step 5: Render Plan
Print the full plan and wait for approval. Format:

```
## Sync Plan: sandbox -> prod

**Source**: sandbox (https://api.lytics.io)
**Destination**: prod (https://api.lytics.io)
**Mode**: upsert     (use --create-only to refuse overwrites)

### Operations (in execution order)

1. [create]   schema.field        purchase_total            (dep of segment high_value_customers)
2. [create]   schema.mapping      purchase_total <- shopify_orders.total_price
3. [update]   segment             included_premium          (diff below)
4. [create]   segment             high_value_customers
5. [skip]     segment             dnd_list                  (already matches)

### Summary: 3 create, 1 update, 1 skip, 0 conflict

### Blockers
- None.

### Field-level diff (update only, shown with --diff)

segment high_value_customers (update):
  segment_ql:
    - FILTER AND (country = "US", purchase_total > 100) FROM user ALIAS hvc
    + FILTER AND (country = "US", purchase_total > 250) FROM user ALIAS hvc
  description:
    - High value customers
    + High value customers (>$250 lifetime)

Proceed with this sync? (yes/no)
```

Always include the operations list. Include "Blockers" when any exist (missing auths, schema-patch incompatibility, dep cycles). Include field-level diff only when `--diff` is set.

Under `--dry-run`, stop after rendering the plan -- do not prompt for confirmation and do not execute.

### Step 6: Confirmation Gate
Follows `../references/confirmation-gate.md`:
- NEVER execute without explicit `yes`.
- If user requests changes, revise and re-render Step 5.
- Bulk selections (all-of-type, prefix) require a second confirmation echoing the object count + a sample of 5 names.

### Step 7: Execute in Topological Order
Process nodes one by one. For each:
1. Apply cross-reference remapping using the in-run `src_id -> dst_id` map.
2. Apply traceability append (unless `--no-trace`).
3. Invoke the per-type write (see Per-Type Writes).
4. Record the result in the manifest.
5. On failure, stop. Retain completed successes. Report remaining-pending nodes.

### Step 8: Write Manifest
Write `~/.lytics/sync/<ISO8601>-<src>-to-<dst>.json`:

```json
{
  "started_at": "2026-04-16T14:22:01Z",
  "finished_at": "2026-04-16T14:22:47Z",
  "src": {"profile": "sandbox", "url": "https://api.lytics.io"},
  "dst": {"profile": "prod",    "url": "https://api.lytics.io"},
  "mode": "upsert",
  "flags": {"dry_run": false, "create_only": false, "diff": true, "no_trace": false},
  "selector": {"type": "segment", "selector": "high_value_customers"},
  "operations": [
    {
      "type": "schema.field",
      "natural_key": "purchase_total",
      "op": "create",
      "src_id": "fld_abc",
      "dst_id": "fld_def",
      "status": "success",
      "timestamp": "2026-04-16T14:22:03Z"
    },
    { "...": "..." }
  ],
  "status": "success",
  "pending": []
}
```

Pending entries let the user see what remains after a partial-failure halt and re-run idempotently.

## Normalization Rules

Raw object payloads contain a lot of fields that are either server-assigned or vary across accounts for non-semantic reasons. If you compare them verbatim, every dry-run drowns in false-positive "updates." Before classifying (Step 4) and before computing diffs (`--diff`), normalize both sides.

### Server-Assigned Field Registry

Strip these fields per type before comparing. They are either server-metadata (timestamps, surrogate IDs), computed/cached (AST, derived fields), account-scoped (IDs that can't be meaningful across accounts), or controlled entirely by platform behavior.

| Type | Always strip | Strip when present |
|------|--------------|---------------------|
| Segment | `id`, `aid`, `account_id`, `author_id`, `created`, `updated`, `ast`, `fields`, `field_changes_fields`, `includes`, `datemath_calc`, `forward_datemath`, `invalid`, `invalid_reason`, `deleted` | `groups` (see Groups Policy), `public_name` (server-generated from slug when `is_public`) |
| Schema field | `created`, `modified`, `edit_status`, `managed_by`, `assertions` | -- |
| Schema mapping | `id`, `created`, `modified`, `edit_status`, `managed_by` | -- |
| Flow | `id`, `aid`, `account_id`, `author_id`, `created`, `updated`, `version`, `last_version_id`, `state` | -- |
| Job | `id`, `aid`, `account_id`, `author_id`, `created`, `updated`, `state`, `work_state`, `last_run` | `auth_ids` (remap + strip for compare; see Cross-Reference Remapping) |
| Connection | `id`, `aid`, `account_id`, `author_id`, `updated_by_user_id`, `created`, `updated` | `auth_ids` (remap + strip) |
| Auth | `id`, `account_id`, `user_id`, `provider_id`, `created`, `updated`, `last_accessed_at`, `status`, `unhealthy` | -- |
| Template | `id`, `aid`, `account_id`, `author_id`, `created`, `updated` | -- |
| Account setting | `field` (type/label/description metadata, not user value), `subject`, `category`, `sub_category`, `can_be_assigned` -- all server-derived descriptors. Only `value` is user-owned. | -- |
| Account idconfig | `created`, `modified`, `edit_status` | account-scoped IDs if present |
| Account rank | `created`, `modified`, `edit_status` | -- |

### Trace-Line Stripping (All Description-Like Fields)

Any field that may carry a traceability line must have it stripped before comparison. Scope is broader than `description` -- it covers every field the skill may write into:

| Type | Description-like fields |
|------|-------------------------|
| Segment | `description` |
| Schema field | `shortdesc`, `longdesc` |
| Schema mapping | (none today; mappings do not carry a description) |
| Flow | `description` |
| Job | `description` |
| Connection | `description`, `label` (do NOT strip from `label` -- it's the natural key; only append trace to `description`) |
| Auth | `description` (sensitive; may prefer `--no-trace` for auth) |
| Template | (none -- template `description` is short and user-owned, and the source body is account-stable; no reliable place to embed a trace line. Manifest is the sole audit record. `--no-trace` is silently accepted.) |

Stripping rule: remove any line matching the regex `^\s*\[account-sync\] .*$` from the field before diffing. The date inside the trace line changes across runs -- without stripping, an idempotent re-run would register every object as `update`.

### Duration Precision

Some time-duration fields (e.g., schema field `keep_duration`) serialize with sub-microsecond precision that drifts across re-saves: `2159h59m59.9999992s` vs `2159h59m59.99999899s`. Both are effectively 90 days.

Normalize any string matching the Go duration shape `<h>h<m>m<s>s` (possibly with fractional seconds) to integer-second precision before comparing. Treat sub-second differences as noise.

### Hex-ID INCLUDE Resolution

`segment_ql` can reference included segments by either slug (`INCLUDE my_segment`) or internal hex (`INCLUDE \`24114e3cbba5be2a09d3599e7b90045d\``). Hex IDs differ by account even when they refer to the same logical segment.

Before comparing `segment_ql` across accounts, rewrite every `INCLUDE <hex>` to `INCLUDE <slug>` on each side, using that account's own hex-to-slug map. Slug-based INCLUDEs are left as-is. This eliminates the biggest false-positive class for segment comparisons.

Regex for detection: `INCLUDE\s+` + either a backtick-wrapped 32-char hex or a bare identifier.

### Groups Policy

Segment `groups` arrays hold account-scoped group IDs. Different accounts have different IDs for the same logical group, so groups arrays virtually always differ across accounts even when everything else matches. Two supported behaviors:

- **Default: strip `groups` on compare; do not write `groups` during sync.** Simplest and safe. Groups must be re-applied in the destination by hand or via a separate (future) `groups-sync` operation.
- **Opt-in (`--sync-groups`): remap groups by name.** Before writing, list destination groups, match source groups to destination groups by name, rewrite the `groups` array. Missing dest groups become blockers in the plan.

Default today is `--sync-groups=off`.

## Transitive Equivalence

By default, segment equality is **shallow**: `seg_src` matches `seg_dst` when their normalized non-reference fields match, regardless of whether referenced (INCLUDEd) segments agree.

Shallow equality is the right default for the dry-run plan because it keeps the plan focused on what the skill will write. But it can hide semantic drift: `seg_src` and `seg_dst` both contain `INCLUDE premier_customer`, but `premier_customer` itself has a different FilterQL in each account -- so `seg_src` and `seg_dst` behave differently even though they "match."

With `--deep`, perform a recursive equivalence check:

1. For each referenced slug in `seg_src.segment_ql`:
   1. Look up the same slug in destination.
   2. If missing, mark the referenced dep as `missing` (a blocker).
   3. If present, recursively normalize+compare `dep_src` to `dep_dst`.
4. If any referenced dep is `missing` or not equivalent, classify the parent as `differs-transitively` -- a distinct category from `update` (the parent's own normalized content is unchanged) and from `skip` (runtime behavior differs).
5. Render `differs-transitively` in the plan with the specific dep(s) that diverge, so the user can decide whether to also sync those deps.

Cycles: if the recursion reaches a segment already in the stack, treat it as equivalent for the cycle branch (avoids infinite recursion; same-structure cycles are rare but not impossible).

Performance: `--deep` adds O(number of referenced segments) extra GETs per segment. For large accounts use it on a narrow selector.

## Per-Type Writes

### Segments
Use the `segment-manager skill` conventions (`POST /v2/segment` for create, `PUT /v2/segment/{id}` for update, `DELETE /v2/segment/{id}` never). Before writing:
1. Rewrite any internal-ID references: slug-based `INCLUDE <slug>` is account-stable (no remap); hex-based `INCLUDE \`<hex>\`` must be rewritten to the destination's own hex for that slug (see Cross-Reference Remapping).
2. Validate the FilterQL against the destination (`POST /api/segment/validate`). If validation fails in destination but passed in source, surface the error and halt -- typically a missing schema field dep that should have been caught in Step 3.
3. Apply traceability append.
4. Write (POST for create, PUT for update).
5. Read-after-write verification (GET and diff).

### Schema Fields and Mappings
Before any schema write, determine the destination's schema-write mode (from `schema-manager skill`):

```bash
LYTICS_API_TOKEN="$DST_TOKEN" LYTICS_API_URL="$DST_URL" \
  curl -s "${LYTICS_API_URL}/v2/schema/patch/user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

If it returns success (even an empty array), the destination uses **schema patches**. Otherwise use **direct publish**.

**Schema-patches path (preferred when available):**
1. Create one named patch per sync run: `POST /v2/schema/patch/{table}` with `name: "sync-from-<src>-<ISO8601>"` and a description listing the run context.
2. Add every schema field op to the patch via `POST /v2/schema/patch/{table}/{patch_id}/field`.
3. Add every mapping op via `POST /v2/schema/patch/{table}/{patch_id}/mapping`.
4. Before Step 6's confirmation, `GET /v2/schema/patch/{table}/{patch_id}` and include its diff in the rendered plan.
5. On approval, `POST /v2/schema/patch/{table}/{patch_id}/apply`.
6. On abort, `DELETE /v2/schema/patch/{table}/{patch_id}` to discard.

**Direct-publish path (when patches are not available):**
Write fields and mappings directly, then publish once per run with a tag like `account-sync-<src>-to-<dst>-<ISO8601>` and a description. A schema write is NOT complete until publish succeeds -- same rule as `schema-manager skill`.

**Streams are not created**. Mapping copies require the source stream to exist in the destination. If a referenced stream is absent, classify the mapping as `conflict` with reason "source stream not present in destination" and surface it in Blockers.

### Flows
Before writing a flow:
1. Remap `entry_segment_id` via the in-run `src_id -> dst_id` map. If no mapping (the referenced segment wasn't copied and doesn't pre-exist in destination by slug), halt with a blocker.
2. Remap any segment ID references inside `split_conditions` step payloads. Slug-based FilterQL inside those conditions needs no remap.
3. For flow state: source `state: running` is never copied as `running`. Default to `draft` in destination unless the user explicitly confirms a live-promote. Surface this explicitly in the plan.
4. Apply traceability append to `description`.
5. Write via `POST /v2/flow/ui` (create) or `POST /v2/flow/ui/{id}` (update).

### Jobs
Before writing a job:
1. Remap `config.segment_id` via the in-run map.
2. Resolve `auth_ids`: look up each by `(label, type)` in the destination. If any is missing, treat the job as blocked and surface an auth blocker in the plan.
3. **If the job's `workflow` is `webhook_triggers` or `webhook_enrichment`, remap `config.template_id` via the in-run template map.** If the source job has a `template_id` and the corresponding template isn't in the destination map, halt with a blocker (the template should have synced earlier in topological order; if it didn't, it was excluded from the selector).
4. Remap any other fields the skill recognizes. For unknown `config` keys, copy them verbatim and include a **"review config carefully"** note on the job's op line. Job configs are workflow-specific; the skill does not attempt to understand every workflow.
5. Job state is never auto-started. Default to the destination's normal post-create state (workflow-dependent) and let the user start via `job-manager` separately. Surface this in the plan.
6. Apply traceability append.
7. Write via `POST /v2/job` or `PUT /v2/job/{workflow}/{id}`.

### Connections
1. Resolve the referenced auth in the destination by `(label, type)`. If missing, block.
2. Copy the connection config verbatim; apply traceability append.
3. Write via `POST /v2/connection` or `PUT /v2/connection/{id}`.

### Templates
Webhook templates (`webhook-template-builder skill`) are referenced by webhook-workflow jobs via `config.template_id`. Templates therefore sync **before** any dependent webhook job; the topological sort enforces this naturally via the dep edge added in Step 3.

1. **Resolve destination by `(name, type)`** (`GET /v2/template`, filter, then `GET /v2/template/{id}` for the body).
2. **Probe source-body location** on the GET response. The body may be on `data` directly, on `data.body`, on `data.source`, or require `?include_body=true` / `/v2/template/{id}/source`. Cache the working shape per-account.
3. **Normalize source body on both sides** before diff:
   - Strip trailing whitespace per line
   - Normalize line endings to `\n`
   - Strip trailing blank lines
   - Strip server-assigned fields (`id`, `aid`, `account_id`, `author_id`, `created`, `updated`)
4. **Classify**: equal -> `skip`; differ -> `update` (or `conflict` under `--create-only`); missing in dst -> `create`.
5. **Write**:
   - Create: `POST /v2/template?name=<>&type=<>&description=<>` -- metadata in query string, body raw via `--data-binary`. Use `Content-Type: text/plain` first, fall back to `application/javascript` on 415 (see `webhook-template-builder skill` Probing Notes).
   - Update: `PUT /v2/template/{id}?name=<>&type=<>&description=<>` (the API reference says POST but the live endpoint requires PUT; see `webhook-template-builder skill` Probing Notes).
6. **Read-after-write**: GET the template back, re-normalize, expect zero diff. If the server normalized whitespace differently than we did, record `server_normalized` (not `server_drift`).
7. **Update the in-run map** `(template, name, type) -> dst_id` so dependent webhook jobs can remap `config.template_id` later in the topological order.

If a webhook job's `config.template_id` references a template that doesn't exist in the destination map (e.g., the user selected the job but excluded the template from the selector), halt with a blocker:
> "Job `<job-name>` references template `<src_template_name>` (`<src_template_id>`) which is not present in the destination. Re-run with `sync template <src_template_name> from <src> to <dst>` first, or include the template in your selector."

### Auth Providers
Auth is the trickiest type. Behavior:
- **Match-first**: For every auth referenced by any copied object, look up destination by `(label, type)`. If found, use its ID and proceed.
- **Missing auth**: halt before Step 7 with a blocker listing:
  ```
  Destination is missing the following auth providers:
    - salesforce_prod (type: oauth_salesforce)
    - shopify_main    (type: apikey_shopify)

  OAuth providers must be created in the destination UI.
  Create them, then re-run this sync. API-key providers can also be copied
  by running `sync auth <name> from <src> to <dst>` -- but review carefully,
  because credentials are sensitive and may differ per environment.
  ```
- **Direct auth copy (only when the user runs `sync auth ...` explicitly)**: copy via `POST /v2/auth/{type}`. Never auto-copy OAuth auths -- they require a completed flow and the token will not be valid for the new account. OAuth auths are always blockers.

## Account Settings

Account settings are a different shape from everything else in this skill: flat key/value on the account (for `account.setting`) or a table-scoped singleton (for `idconfig` and `rank`). They have no surrogate IDs, no cross-references to other objects, and no `description` field for a trace line. The manifest is the sole audit record.

### Endpoints

**Path is `/api/account/setting` (singular; `/api/` not `/v2/`).** Source: `lytics/lio/src/api/rw/account_setting.go`.

```bash
# List all settings (returns 99+ items typically; each is {slug, category, sub_category, value, field, can_be_assigned, subject})
curl -s "${API}/api/account/setting" -H "Authorization: ${TOKEN}"

# Get one setting
curl -s "${API}/api/account/setting/${SLUG}" -H "Authorization: ${TOKEN}"

# Update one setting -- body is the raw JSON VALUE (not wrapped in an object)
curl -s -X PUT "${API}/api/account/setting/${SLUG}" \
  -H "Authorization: ${TOKEN}" -H "Content-Type: application/json" \
  -d 'true'                             # boolean
curl ... -d '"finance"'                  # string
curl ... -d '["mobile","web"]'           # array
curl ... -d '500'                        # number

# Delete (reset to unset)
curl -s -X DELETE "${API}/api/account/setting/${SLUG}" -H "Authorization: ${TOKEN}"
```

For idconfig and rank, use the existing v2 schema endpoints (`schema-manager skill`): `/v2/schema/{table}/idconfig` and `/v2/schema/{table}/rank`.

### Response Shape (account.setting)

```json
{
  "slug": "onboarding_question_vertical",
  "category": "onboarding",
  "sub_category": "...",
  "value": "finance",
  "field": {
    "type": "string",
    "label": "...",
    "name": "...",
    "description": "..."
  },
  "can_be_assigned": true,
  "subject": "account"
}
```

Only `value` is user-owned content. The rest (`field`, `category`, `sub_category`, `subject`, `can_be_assigned`) is server-derived descriptor metadata and is stripped during comparison (see Server-Assigned Field Registry).

### `can_be_assigned` governs writability

Each setting has a boolean `can_be_assigned`. Settings where this is `false` are read-only from the user's perspective -- the API returns **403** on attempted updates:

> `"This setting %q is not editable, talk to your account manager."`

Behavior in this skill:
- During compare, settings with `can_be_assigned: false` that differ are classified as `drift-readonly` (informational only) and surfaced in the plan -- never as `create` or `update`.
- The skill never attempts a write on `can_be_assigned: false`. If a user explicitly requests `sync setting <slug>` for a read-only setting, refuse with a clear message.
- Typical ratio observed: ~75% of settings are writable (`can_be_assigned: true`); the rest require platform-level intervention.

### Non-public settings are invisible

The API filters out non-public settings server-side (`FilterNonPublic(false)` in the handler). The skill does not need to handle `public: false` settings -- they won't appear in responses. Rare exceptions (when `FeatureConductorSchema` is enabled, `schema_user_private_fields` is additionally filtered) are handled by the server.

### Write-path probe

Before the first settings write of a run, probe one setting with a **no-op**: re-submit the destination's current value for a writable setting (pick one with `can_be_assigned: true` and a non-null value). Confirm the endpoint returns 200 and no side effects were logged. This validates the write shape (raw JSON value, not a wrapper) before committing to bulk changes. If the no-op fails, halt the settings phase before any real write.

### Write workflow per-setting

1. **Permission check** -- confirm `can_be_assigned: true` on the source setting. If false, classify as `drift-readonly` and skip.
2. **Validate** -- the server validates `value` against `field.type` (`setting.Field.Validate(val)`); type mismatches return 400. The skill mirrors this check client-side where possible to avoid round-trips (boolean vs string vs array).
3. **Write** -- `PUT /api/account/setting/{slug}` with body = the raw value JSON.
4. **Side-effect awareness** -- some settings trigger platform-level side effects:
   - Any setting with `ReloadQuery: true` in the server-side definition forces a LinkgridReloadQueryFor on the user table. Expect increased latency on the response.
   - `content_allowlist_field` / `content_blocklist_field` (exact slugs subject to `SettingContentAllowlistField` / `SettingContentBlocklistField` constants) additionally sync affinity config. Do not batch these with other settings in a way that would obscure a failure.
   - The API flushes cached resources for jstag after every setting update; brief cache-coldness in the destination is expected.
5. **Read-after-write verification** -- GET the setting back and confirm `.value` matches the submitted value. This is especially important for settings with server-side transformation (e.g., the server may re-case or sort array elements).

### `idconfig` requires an extra confirmation gate

`idconfig` (identity config per table) controls which schema fields are treated as identity fields for profile matching and merging. Flipping it can re-merge profiles in the destination -- the blast radius is potentially every profile in the account, and the change is not straightforwardly reversible.

**Gate procedure, in addition to the standard confirmation gate:**

1. Render the current → proposed diff inside the plan preview as usual.
2. After the user approves the plan (the first `yes`), **prompt again**: `This will change profile identity/merge rules on <dst-profile>/<table>. Retype 'confirm idconfig <table>' to proceed.`
3. Accept only the exact literal string (case-sensitive, whole match). Any other input -- including plain `yes`, `y`, `confirm`, or near-matches -- aborts this `idconfig` write for that table but leaves other settings operations in the plan intact.

Other settings (`rank`, flat `account.setting` keys) go through the standard confirmation gate only.

### `idconfig` 404 handling

A 404 on `GET /v2/schema/{table}/idconfig` means the account has no idconfig set for that table -- not that the endpoint is broken. Error messages from the server may include the string `"Could not find rank settings for table <table>"` (the error message is imprecise; the status code is authoritative). Treat 404 as `idconfig = empty` during compare:
- If both sides are 404, classify as `skip`.
- If one side is 404 and the other has an idconfig, classify as `create` (idconfig will be written on the empty side) or `dst-only` (reported, not acted on).

### Settings phase ordering

When a run includes multiple types (e.g., `sync all`), settings are processed **first**, before segments/schema/flows/jobs. Two reasons:

1. Any setting that flips the destination's schema-write mode (e.g., a future `enable_schema_patches` setting if/when it becomes writable) must be applied before the schema phase computes its mode.
2. `idconfig` changes the profile merge rules that downstream segments and flows depend on.

**After the settings phase completes**, the schema-mode probe (see Schema Fields and Mappings section) must be **re-run** before the schema phase executes. The cached pre-settings schema-mode decision is stale if any setting just altered the mode.

### Traceability

Account settings have no `description` or `notes` field in which to embed an `[account-sync]` trace line. The **manifest** is the sole audit record for settings ops. `--no-trace` has no effect on settings; accept the flag silently. This is a documented limitation, not a bug.

### Selectors

| Invocation | Behavior |
|------------|----------|
| `sync settings from <src> to <dst>` | All writable settings (`can_be_assigned: true`) that differ, plus per-table idconfig and rank for every schema table. Bulk-operation gate fires. |
| `sync setting <slug> from <src> to <dst>` | Single setting by slug. Refuses if `can_be_assigned: false`. |
| `sync idconfig [<table>] from <src> to <dst>` | Per-table idconfig; `<table>` defaults to all tables. Extra confirmation gate fires per table. |
| `sync rank [<table>] from <src> to <dst>` | Per-table field rank; `<table>` defaults to all tables. Standard confirmation gate only. |

`compare` variants (`compare settings from <src> to <dst>`, etc.) are read-only per the existing Compare Mode section.

### Manifest op types

Settings ops use these `type` values in the manifest:

- `account.setting` (natural_key = slug)
- `account.idconfig` (natural_key = table)
- `account.rank` (natural_key = table)

Same envelope as other ops: `{type, natural_key, op, src_id: null, dst_id: null, status, error, timestamp}`. `src_id` and `dst_id` are always `null` for settings -- no surrogate IDs.

## Cross-Reference Remapping

Keep an in-run `Map<(type, src_natural_key), dst_id>`. Populate as each node is created or matched to an existing destination. When writing a dependent object, rewrite every recognized reference field from source IDs to destination IDs:

| Field | Object type | Remap? |
|-------|-------------|--------|
| `entry_segment_id` | flow | Yes, via segment map |
| `split_conditions[].condition` FilterQL | flow step | Slugs no; hex-ID INCLUDEs yes (same rules as segment `segment_ql`) |
| Flow step `work_id` | flow step (work_export / work_export_exit) | Yes, via job/work map |
| `config.segment_id` | job | Yes, via segment map |
| `config.template_id` | job (webhook workflows: `webhook_triggers`, `webhook_enrichment`) | Yes, via template map (`(name, type)` lookup). Only attempt remap when the job's `workflow` is a webhook workflow; for other workflows, `template_id` is not a recognized field and the existing "unknown config keys are copied verbatim" rule applies. |
| `auth_ids[]` | job, connection | Yes, via auth map (`(label, type)` lookup) |
| `mapping.field` | schema mapping | No -- field names are stable |
| `mapping.stream` | schema mapping | No -- stream names are stable; require dest stream to exist |
| `mapping.expr` field identifiers | schema mapping | No -- field names are stable; but verify each referenced field exists in dst |
| Segment `segment_ql` `INCLUDE <slug>` | segment | No -- slug is the reference |
| Segment `segment_ql` `INCLUDE \`<hex>\`` | segment | Yes -- resolve src hex to its slug, then rewrite to dst's own hex for that slug (dst must have the slug, enforced by the dep graph). Backticks around the hex are optional -- the server accepts both forms and may re-serialize without them. Normalize backticks on compare. |

Also persist the map in the manifest for audit.

## Dependency-Conflict Handling

When a traversed dependency exists in the destination with the same natural key but a different definition:

- **upsert (default)**: classify the dep as `update`. The plan renders it as an update; on approval, the dep is overwritten with the source version. Show this prominently in the plan -- user should see that their `sync segment X` is about to change the definition of a dep.
- **create-only (`--create-only`)**: classify the dep as `conflict`. The plan lists every conflict and refuses to proceed. Instruct the user to either (a) re-run without `--create-only`, (b) resolve the deps manually, or (c) re-run with a narrower selector.

## Traceability

For every copied object, append or replace this single line in the object's description-like field(s):

```
[account-sync] Copied from <src-profile> on <YYYY-MM-DD>
```

The exact target field varies per type -- see the **Trace-Line Stripping** table in the Normalization Rules section for the full list (`description`, `shortdesc`, `longdesc`, etc.). The line is appended to each description-like field the skill writes; compare logic strips it before equality checks.

**Replacement**: before writing, strip any existing line matching the regex `^\s*\[account-sync\] .*$` from each target field, then append the fresh line with a leading blank line if there is prior content in that field.

Suppressed entirely with `--no-trace`. When suppressed, do not strip any pre-existing `[account-sync]` line -- leave the destination's content alone.

**Per-type targets:**
- Segment: `description`
- Schema field: `shortdesc` (primary), `longdesc` only if already populated in source
- Schema mapping: none (mappings carry no description field today)
- Flow: `description`
- Job: `description`
- Connection: `description`
- Auth: `description` -- but prefer `--no-trace` for auth; auth descriptions often carry sensitive context

## Read-After-Write Verification

Trusting the write response is not enough. Servers can set defaults, auto-generate dependent fields, or normalize values in ways the caller doesn't expect.

After every successful write, immediately:

1. **GET the written object** from the destination using the returned `id`.
2. **Normalize** both the expected payload and the returned object (Normalization Rules), using the server-assigned field registry and trace-line stripping.
3. **Diff** them. For each field where the server's value differs from what was sent:
   - If the field is in that type's "Strip when present" column (e.g., `public_name` auto-generated from slug), treat it as expected server behavior and record it in the manifest as `server_normalized` (not `server_drift`).
   - Otherwise, record as `server_drift` with the expected vs. actual values and surface a warning to the user after the run completes.
4. **Update the manifest** for that operation with a `verified_at` timestamp and any `server_drift` / `server_normalized` entries.

Verification never changes execution flow on its own (the write already succeeded; drift is a post-hoc observation). It gives the user grounds to either accept the drift, hand-correct the object, or file a bug against the platform.

### Known drift classes

| Field(s) | Type | Behavior |
|----------|------|----------|
| `keep_duration` precision | Schema field | Server re-serializes with sub-microsecond precision that drifts slightly. Normalization Rules already strip this noise on compare. |
| `edit_status` | Schema field / mapping | Server assigns based on patch state. Never user-controlled. |
| `public_name` | Segment | Auto-generated from slug when `is_public: true`; user-settable only via explicit PUT and rarely needed. Classified as `server_normalized`, not `server_drift`. |

## Safety Layers

Applied in this order of defense:

1. **`--dry-run` / `compare`** -- no writes. The plan is the only output.
2. **Plan preview + confirmation gate** -- mandatory on any non-dry-run invocation. Follows `../references/confirmation-gate.md`.
3. **Bulk-operation gate** -- `all` and `--prefix` selectors (and `compare` across all types) require a second confirmation showing the object count and a sample of up to 5 names. If count > 50, require the user to retype `confirm <count>` to proceed.
4. **Retype gate for `idconfig`** -- in addition to the standard confirmation, every `idconfig` write requires the user to retype `confirm idconfig <table>` verbatim. See Account Settings > `idconfig` requires an extra confirmation gate.
5. **Stop-on-first-error** -- no silent continuation past failures. Partial successes remain in the destination; the manifest records `success`, the failed op, and every untouched `pending` op so the user can resume via `resume <manifest>` or `sync ... --resume <manifest>`.
6. **Read-after-write verification** -- after every successful write, GET the object and diff against expected (Read-After-Write Verification section). Record `server_drift` in the manifest.
7. **In-flight patch cleanup on halt** -- draft schema patches are never left orphaned; see Error Handling.
8. **Schema-mode re-probe after settings phase** -- if a run touches settings and schema in the same invocation, re-probe the destination schema-write mode between the two phases. A setting may have flipped `enable_schema_patches` (or similar) and the cached pre-settings decision is stale.
9. **Manifest** -- written to `~/.lytics/sync/<ISO8601>-<src>-to-<dst>.json` on every run (including aborted ones where at least one write succeeded).

### Idempotency Invariant

A successful `sync` run followed immediately by the **same command** must yield **0 writes**. This invariant is load-bearing: it's what makes `resume` safe, what makes dry-runs trustworthy, and what makes retries non-destructive.

Things that break the invariant if implemented naively, and the mitigations in this skill:

| Risk | Mitigation |
|------|------------|
| Trace line carries the current date; date changes across runs so string equality fails | Strip `^\s*\[account-sync\] .*$` from every description-like field before comparing (Normalization Rules) |
| Server re-serializes durations with drifting sub-microsecond precision | Normalize `<h>h<m>m<s>s` to integer seconds before comparing (Normalization Rules) |
| Server auto-assigns fields (e.g., `public_name`) not present in source | Strip via server-assigned field registry (Normalization Rules) |
| Cross-account hex IDs in FilterQL INCLUDE refs differ even when logical refs match | Resolve hex to slug on both sides before comparing (Normalization Rules) |
| Account-scoped group IDs differ across accounts | Strip `groups` on compare by default (Groups Policy) |
| Account setting descriptor metadata (`field`, `category`, ...) may drift across deployments | Strip via server-assigned field registry (Normalization Rules); only `value` is compared |
| `can_be_assigned: false` settings cannot be written -- attempting a correction would loop forever | Classify read-only drift as `drift-readonly`, never `update`; never attempt the write |
| Template body whitespace drifts on server re-save (trailing whitespace, line endings) | Trim trailing whitespace per line and normalize line endings to `\n` on both sides before comparing (see Per-Type Writes > Templates) |
| Two templates with the same name but different `type` collide on natural-key lookup | Disambiguate on `(name, type)`, never `name` alone |
| Webhook job `config.template_id` from src is an account-scoped hex that doesn't exist in dst | Walk + remap via the in-run template map; if unmapped, halt with a blocker rather than writing a broken reference |

If you are implementing a change to the skill and it breaks idempotency, that's the bug.

## Error Handling

- **401 on either profile** -- fail fast with a clear message naming which profile's token was rejected. Do not proceed.
- **404 on source object** -- reject the selector clearly; list close matches from the source's object list.
- **404 on `GET /v2/schema/{table}/idconfig`** -- idconfig is not set on this account, not an error. Error message may misleadingly say `"Could not find rank settings for table <table>"`. Status code is authoritative. Treat as empty idconfig.
- **403 on `PUT /api/account/setting/{slug}`** with message `"This setting is not editable, talk to your account manager"` -- the setting's `can_be_assigned` is `false`. The skill should have caught this client-side during classification and never issued the write; if this fires, it's a bug in the skill. Halt the settings phase and report.
- **400 on `PUT /api/account/setting/{slug}`** -- value type mismatch against `field.type`. Surface the server's message; usually the fix is client-side type coercion (e.g., boolean `true` vs string `"true"`).
- **409 on destination create** -- a natural-key race happened (something was created between the dest-lookup and the write). Re-classify as `update` and re-prompt with an amended plan.
- **422 on validation** (segment FilterQL, schema patch apply) -- surface the full message and halt. Usually indicates a missing upstream dep that should have been caught in Step 3.
- **Rate limit (429)** -- respect `../references/api-client.md`'s guidance. Back off briefly and retry once. Do not silently drop an op.
- **Network / transient errors** -- retry once; on second failure, treat as a hard failure and halt.

### In-Flight Schema Patch Cleanup

A schema patch is created at the start of a schema-patch-path run, populated with field/mapping changes, and applied at the end. Halts between create and apply leave the patch in `draft` state. **Never leave an orphan draft patch.**

Required cleanup on halt (must execute before the run exits, regardless of exit cause):

1. Identify in-flight patch: the last `schema.patch` `create` entry in the manifest with no corresponding `apply` or `delete`.
2. If all field/mapping operations for that patch are recorded as `success` in the manifest, you MAY attempt to apply it (typically only appropriate when the halt was in a later, non-schema op). Prompt the user; do not silently apply.
3. Otherwise, **delete the patch**: `DELETE /v2/schema/patch/{table}/{patch_id}`. Record the deletion in the manifest as a compensating op.
4. If the delete itself fails, surface the patch ID + `GET /v2/schema/patch/{table}/{patch_id}` URL in the halt message so the user can clean up manually.

**Schema patch `apply` fails**: by contrast, if `apply` specifically is what failed, leave the patch in `draft` so the user can inspect it. Surface the patch ID and GET URL; do NOT auto-delete.

### `is_public` / `public_name` Interdependence

- Setting `is_public: true` auto-populates `public_name` from the slug. Sending your own `public_name` alongside `is_public: true` may or may not be respected.
- Toggling a segment from public -> private via `PUT /v2/segment/{id}` with `is_public: false` does NOT clear `public_name`. The value persists. Probably intentional (external references may depend on it) but worth being aware of.

### Tag / Identifier Format Rules

- Schema patch `tag` must be **kebab-case**. ISO-8601 timestamps are not valid because they contain `:`. Replace `:` with `-` before using an ISO timestamp as part of a tag (e.g., `2026-04-16T20-38-25Z`).
- Segment `slug_name` must be URL-safe; the skill copies it verbatim from source.
- Stream names are case-sensitive and must match exactly.

## Dependencies
- Uses: `../references/auth.md`, `../references/api-client.md`, `../references/confirmation-gate.md`, `../references/api-response-format.md`
- References: `../references/filterql-grammar.md` (for `INCLUDE slug` parsing)
- Composes knowledge from: `segment-manager skill`, `schema-manager skill`, `flow-manager skill`, `job-manager skill`, `connection-manager skill`

## Known Risks

- **Job `config` is workflow-specific.** The skill remaps `segment_id` and `auth_ids`; other config keys are copied verbatim. Every job op in the plan carries a "review config carefully" note.
- **No API transaction support.** Partial-failure recovery relies on upsert idempotency + the manifest.
- **OAuth auths cannot be automated.** The missing-auth blocker is the only path -- user must complete OAuth in the destination UI.
- **Traceability line is visible in the UI.** Users who don't want it on prod descriptions should use `--no-trace`.
- **`all` on large accounts can be very big.** The bulk gate helps; first-time users should start with a single object or `--prefix`.
- **Schema patches are preferred but not all accounts have them enabled.** The skill detects mode per destination and falls back to direct publish when needed.
- **Server-side write drift.** Some fields may be normalized by the server after a write. Read-After-Write Verification catches this post-hoc; it does not prevent it. See Known drift classes for the current list.
- **Groups are not synced by default.** Segment `groups` arrays hold account-scoped IDs and would fail naive copy. Opt in with `--sync-groups` (see Groups Policy).
- **Account settings have no trace line.** Manifest is the sole audit record for settings ops; `--no-trace` is silently ignored for settings.
- **`idconfig` can re-merge profiles in the destination.** Blast radius is potentially every profile in the account; the retype gate is the only in-skill mitigation. Coordinate with the dst account owner before syncing `idconfig`.
- **Read-only settings cannot be forced.** If a setting with `can_be_assigned: false` differs between accounts, the skill classifies it as `drift-readonly` and surfaces it in the plan but never attempts a write. Corrections require platform-level (non-API) intervention.
- **Some settings have side effects on write.** `ReloadQuery`-flagged settings trigger a linkgrid reload; `content_allowlist_field`/`content_blocklist_field` additionally sync affinity config. Expect higher write latency and brief cache coldness in the destination.
- **Settings API path is `/api/`, not `/v2/`.** Easy to mistype given the rest of the skill lives at `/v2/`. Also note: the resource is `setting` (singular), not `settings`.
- **Webhook templates have no trace line.** The body is the artifact; the `description` is short and user-owned. The manifest is the sole audit record for `template` ops; `--no-trace` is silently ignored. Webhook jobs that reference a template have `config.template_id` automatically remapped via the in-run template map; if a job is synced without its template, the run halts with a blocker rather than writing a broken reference.

## Docs Drift (Peer Skills vs Real API)

This skill composes knowledge from peer skills (`schema-manager`, `segment-manager`, `flow-manager`, etc.). Those skills' example payloads are usually right, but can drift from the actual API over time.

Known drift found and fixed in this repo:

- `schema-manager`'s schema-patch examples previously showed `name` for patch creation and capitalized keys (`Field`, `Type`, `ShortDesc`, `MergeOp`, `IsIdentifier`, `IsPII`) for adding fields to a patch. The actual patch endpoint requires `tag` (kebab-case) and lowercase field keys (`id`, `type`, `shortdesc`, `mergeop`, `is_identifier`, `is_pii`). Fixed in `schema-manager/SKILL.md`.

When a write fails with a payload-shape error ("`X` is required for `Y`", `BADREQ-001`, `422`), don't assume the docs are correct. **Probe the endpoint:** create a disposable patch/resource and try two or three payload shapes (capitalized, lowercase, `id` vs `Field`, wrapped vs flat) until one returns 200. Clean up the disposable resource and fix the peer skill's docs as a follow-up.
