# Normalization

What to strip or normalize before comparing, the traceability line, and read-after-write verification. Read before classifying, diffing, or verifying any write.

## Normalization Rules

Raw object payloads contain a lot of fields that are either server-assigned or vary across accounts for non-semantic reasons. If you compare them verbatim, every dry-run drowns in false-positive "updates." Before classifying (Step 4, [dependencies.md](dependencies.md#step-4-resolve-destination-state-per-object)) and before computing diffs (`--diff`), normalize both sides.

### Server-Assigned Field Registry

Strip these fields per type before comparing. They are either server-metadata (timestamps, surrogate IDs), computed/cached (AST, derived fields), account-scoped (IDs that can't be meaningful across accounts), or controlled entirely by platform behavior.

| Type | Always strip | Strip when present |
|------|--------------|---------------------|
| Segment | `id`, `aid`, `account_id`, `author_id`, `created`, `updated`, `ast`, `fields`, `field_changes_fields`, `includes`, `datemath_calc`, `forward_datemath`, `invalid`, `invalid_reason`, `deleted` | `groups` (see Groups Policy), `public_name` (server-generated from slug when `is_public`) |
| Schema field | `created`, `modified`, `edit_status`, `managed_by`, `assertions` | -- |
| Schema mapping | `id`, `created`, `modified`, `edit_status`, `managed_by` | -- |
| Flow | `id`, `aid`, `account_id`, `author_id`, `created`, `updated`, `version`, `last_version_id`, `state` | -- |
| Job | `id`, `aid`, `account_id`, `author_id`, `created`, `updated`, `state`, `work_state`, `last_run` | `auth_ids` (remap + strip for compare; see [Cross-Reference Remapping](dependencies.md#cross-reference-remapping)) |
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
