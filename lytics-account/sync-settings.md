# Sync: account settings

`account.setting`, per-table `idconfig`, and per-table `rank`: endpoints, writability, the exclusion table, the idconfig retype gate, and phase ordering. Read before any `sync settings`, `sync setting`, `sync idconfig`, or `sync rank`.

Account settings are a different shape from everything else in this skill: flat key/value on the account (for `account.setting`) or a table-scoped singleton (for `idconfig` and `rank`). They have no surrogate IDs, no cross-references to other objects, and no `description` field for a trace line. The manifest is the sole audit record.

### Endpoints

**Path is `/api/account/setting` (singular; `/api/` not `/v2/`).** Source: `lytics/lio/src/api/rw/account_setting.go`.

```bash
# List all settings (returns 99+ items typically; each is {slug, category, sub_category, value, field, can_be_assigned, subject})
src /api/account/setting      # or: dst /api/account/setting

# Get one setting
dst "/api/account/setting/${SLUG}"

# Update one setting -- body is the raw JSON VALUE (not wrapped in an object)
dst "/api/account/setting/${SLUG}" -X PUT -H "Content-Type: application/json" \
  -d 'true'                             # boolean
dst ... -d '"finance"'                   # string
dst ... -d '["mobile","web"]'            # array
dst ... -d '500'                         # number

# Delete (reset to unset)
dst "/api/account/setting/${SLUG}" -X DELETE
```

For idconfig and rank, use the existing v2 schema endpoints (the `lytics-schema` skill): `/v2/schema/{table}/idconfig` and `/v2/schema/{table}/rank`.

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

Only `value` is user-owned content. The rest (`field`, `category`, `sub_category`, `subject`, `can_be_assigned`) is server-derived descriptor metadata and is stripped during comparison (see Server-Assigned Field Registry in [normalization.md](normalization.md)).

### `can_be_assigned` governs writability

Each setting has a boolean `can_be_assigned`. Settings where this is `false` are read-only from the user's perspective -- the API returns **403** on attempted updates:

> `"This setting %q is not editable, talk to your account manager."`

Behavior in this skill:
- During compare, settings with `can_be_assigned: false` that differ are classified as `drift-readonly` (informational only) and surfaced in the plan -- never as `create` or `update`.
- The skill never attempts a write on `can_be_assigned: false`. If a user explicitly requests `sync setting <slug>` for a read-only setting, refuse with a clear message.

### Writable is not the same as safe to copy

`can_be_assigned: true` only means the API accepts a write. It says nothing about whether copying the value between accounts is safe, and lio's own `Copyable` / `Immutable` flags are not exposed in the JSON. These settings are **excluded from `sync settings`** and only move via an explicit `sync setting <slug>` with a retype-to-confirm gate (same as `idconfig`):

| Setting | Why |
|---------|-----|
| category `security` (2FA, password policy, login) | Copying can lock users out of the destination account |
| category `API` (incl. `api_ip_whitelist`) | A sandbox IP allowlist can lock out prod API access -- including this run's own token, mid-run |
| `cull_user_filter` | Profiles matching it are dropped from the destination nightly |
| `workflow_exclude_segments` | Holds account-scoped segment ids, which mean nothing (or something else) in the destination |
| `enable_schema_patches` | Never PUT it. Switching on goes through `POST /v2/schema/patch/migrate`, which saves in-progress drafts into a patch first; a raw PUT skips that |
| `schema_user_private_fields` | Immutable: any write returns 400 `Field ... is immutable.` -- even re-submitting the current value |

A 400 `Field <slug> is immutable.` means the setting cannot be written by anyone through the API; classify it as `drift-readonly`. Never pick `schema_user_private_fields` for the write-path probe below.

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

1. A setting change can flip the destination's schema-write mode. `enable_schema_patches` itself is writable but excluded from settings sync (see **Writable is not the same as safe to copy**); a mode switch goes through `POST /v2/schema/patch/migrate` outside this skill.
2. `idconfig` changes the profile merge rules that downstream segments and flows depend on.

**After the settings phase completes**, the schema-mode probe (see Schema Fields and Mappings in [writes.md](writes.md)) must be **re-run** before the schema phase executes. The cached pre-settings schema-mode decision is stale if any setting just altered the mode.

### Traceability

Account settings have no `description` or `notes` field in which to embed an `[account-sync]` trace line. The **manifest** is the sole audit record for settings ops. `--no-trace` has no effect on settings; accept the flag silently. This is a documented limitation, not a bug.

### Selectors

| Invocation | Behavior |
|------------|----------|
| `sync settings from <src> to <dst>` | All writable settings (`can_be_assigned: true`) that differ, **minus the exclusion table above**, plus per-table idconfig and rank for every schema table. Bulk-operation gate fires; excluded settings that differ are listed in the plan as `excluded` with the reason. |
| `sync setting <slug> from <src> to <dst>` | Single setting by slug. Refuses if `can_be_assigned: false`. Settings in the exclusion table need a retype-to-confirm gate. |
| `sync idconfig [<table>] from <src> to <dst>` | Per-table idconfig; `<table>` defaults to all tables. Extra confirmation gate fires per table. |
| `sync rank [<table>] from <src> to <dst>` | Per-table field rank; `<table>` defaults to all tables. Standard confirmation gate only. |

`compare` variants (`compare settings from <src> to <dst>`, etc.) are read-only per Compare Mode in [workflow.md](workflow.md).

### Manifest op types

Settings ops use these `type` values in the manifest:

- `account.setting` (natural_key = slug)
- `account.idconfig` (natural_key = table)
- `account.rank` (natural_key = table)

Same envelope as other ops: `{type, natural_key, op, src_id: null, dst_id: null, status, error, timestamp}`. `src_id` and `dst_id` are always `null` for settings -- no surrogate IDs.
