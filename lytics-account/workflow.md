# Workflow

The end-to-end sync flow, plan rendering, manifest, and the `compare` and `resume` verbs. Read before running any `sync`, `compare`, or `resume`.

## Compare Mode

`compare` is a read-only audit. It produces the same per-type plan that `sync --dry-run` would produce, but:

- Omitting `<type>` runs the audit across **all** supported types in one pass.
- No selector is required; by default every object of each requested type is compared.
- No traceability line is considered during comparison (the plan still tells you whether a trace line is the only thing that would change on write, so you can judge idempotency).
- No writes under any circumstance, regardless of confirmation. The user's "yes" is never solicited.
- Output is the plan body only; manifest is optional (`--write-manifest` to emit one).

When to use it: "what's different between these accounts?" -- the question that came up in this session. When to use `sync --dry-run` instead: "if I ran `sync <selector> ...` right now, what would it do?"

## Resume Mode

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
3. Make every call through the `src` / `dst` helpers from `references/auth.md`, never through `LYTICS_API_URL` / `LYTICS_API_TOKEN` -- an env-prefixed call silently hits the ambient account, so a "sandbox to prod" run can overwrite the sandbox source. This applies to every snippet borrowed from a peer skill.
4. Resolve each profile's own aid with the **Same-account guard** in `references/auth.md`. Fail fast on 401 with a clear message naming which profile's token was rejected. Halt if either aid fails to resolve or the two match. Print both aids in the plan header (Step 5).

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

For prefix and all-of-type, the **bulk-operation gate** ([safety.md](safety.md#safety-layers)) fires before continuing.

### Step 3: Build Dependency Graph
See [dependencies.md](dependencies.md#step-3-build-dependency-graph): walk every reference, topologically sort, fail on cycles.

### Step 4: Resolve Destination State Per Object
See [dependencies.md](dependencies.md#step-4-resolve-destination-state-per-object): look up each node by natural key and classify it (`create`, `update`, `skip`, `conflict`, `drift-readonly`, `excluded`), after normalizing both sides per [normalization.md](normalization.md).

### Step 5: Render Plan
Print the full plan and wait for approval. Format:

```
## Sync Plan: sandbox -> prod

**Source**: sandbox (https://api.lytics.io, aid 1234)
**Destination**: prod (https://api.lytics.io, aid 5678)
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
Follows `references/confirmation-gate.md`:
- NEVER execute without explicit `yes`.
- If user requests changes, revise and re-render Step 5.
- Bulk selections (all-of-type, prefix) require a second confirmation echoing the object count + a sample of 5 names.

### Step 7: Execute in Topological Order
Process nodes one by one. For each:
1. Apply cross-reference remapping using the in-run `src_id -> dst_id` map ([dependencies.md](dependencies.md#cross-reference-remapping)).
2. Apply traceability append (unless `--no-trace`; see [normalization.md](normalization.md#traceability)).
3. Invoke the per-type write (see [writes.md](writes.md)).
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
