# Dependencies

Dependency traversal, natural keys and classification, cross-reference remapping, dependency conflicts, and `--deep` transitive equivalence. Read before building a plan for any object that references another.

## End-to-End Steps 3-4

These are Steps 3 and 4 of the flow in [workflow.md](workflow.md).

### Step 3: Build Dependency Graph
Walk references from each selected object to find deps that must exist in the destination. Deps are transitive -- if a flow references a segment that INCLUDEs another segment, all three are nodes.

Every reference below must be **walked** (traversed as a dep edge). Whether it also needs **remapping** (rewriting the value before the destination write) is a separate question, handled in Cross-Reference Remapping (below).

**Reference map:**

| Object | Reference | How to extract | Walk? | Remap? |
|--------|-----------|----------------|-------|--------|
| Segment | `INCLUDE <slug>` inside `segment_ql` | Regex over the FilterQL text; see `references/filterql-grammar.md` | Yes -- verify slug exists in dst | No (slugs are account-stable) |
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
- **skip** -- present; source and destination are equivalent (after stripping traceability line; see [normalization.md](normalization.md)).
- **conflict** -- present with same natural key but differing definition while running under `--create-only`, or a dep conflict under any mode. Terminal classification -- the plan surfaces it; see Dependency-Conflict Handling (below).
- **drift-readonly** -- settings only; source and destination differ but `can_be_assigned: false` so the skill cannot write. Informational; surfaced in the plan but never executed.
- **excluded** -- settings only; writable, but in the **Writable is not the same as safe to copy** table ([sync-settings.md](sync-settings.md#writable-is-not-the-same-as-safe-to-copy)), so `sync settings` never writes it. Surfaced with its reason; only an explicit `sync setting <slug>` with a retype gate writes it.

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
| Segment `segment_ql` `INCLUDE \`<hex>\`` | segment | Yes -- resolve src hex to its slug, then rewrite to dst's own hex for that slug (dst must have the slug, enforced by the dep graph in Step 3). Backticks around the hex are optional -- the server accepts both forms and may re-serialize without them. Normalize backticks on compare. |

Also persist the map in the manifest for audit.

## Dependency-Conflict Handling

When a traversed dependency exists in the destination with the same natural key but a different definition:

- **upsert (default)**: classify the dep as `update`. The plan renders it as an update; on approval, the dep is overwritten with the source version. Show this prominently in the plan -- user should see that their `sync segment X` is about to change the definition of a dep.
- **create-only (`--create-only`)**: classify the dep as `conflict`. The plan lists every conflict and refuses to proceed. Instruct the user to either (a) re-run without `--create-only`, (b) resolve the deps manually, or (c) re-run with a narrower selector.

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
