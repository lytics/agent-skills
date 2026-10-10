# Per-Type Writes

How each object type is written to the destination: segments, schema, flows, jobs, connections, templates, auth. Read before executing Step 7 for that type.

## Per-Type Writes

### Segments
Use the `lytics-audiences` skill conventions (`POST /v2/segment` for create, `PUT /v2/segment/{id}` for update, `DELETE /v2/segment/{id}` never). Before writing:
1. Rewrite any internal-ID references: slug-based `INCLUDE <slug>` is account-stable (no remap); hex-based `INCLUDE \`<hex>\`` must be rewritten to the destination's own hex for that slug (see [Cross-Reference Remapping](dependencies.md#cross-reference-remapping)).
2. Validate the FilterQL against the destination (`POST /api/segment/validate`). If validation fails in destination but passed in source, surface the error and halt -- typically a missing schema field dep that should have been caught in Step 3 ([dependencies.md](dependencies.md)).
3. Apply traceability append.
4. Write (POST for create, PUT for update).
5. Read-after-write verification (GET and diff; see [normalization.md](normalization.md#read-after-write-verification)).

### Schema Fields and Mappings
Before any schema write, determine the destination's schema-write mode (from the `lytics-schema` skill):

```bash
dst /api/account/setting/enable_schema_patches | jq '.data.value'
```

If it is `true`, the destination uses **schema patches**. Otherwise (`false`, `null`) use **direct publish**. Do not probe by listing patches: `GET /v2/schema/patch/{table}` returns 200 on every account, patch-enabled or not.

**Schema-patches path (preferred when available):**
1. Create one patch per sync run: `POST /v2/schema/patch/{table}` with `tag: "sync-from-<src>-<ISO8601>"` and a description listing the run context. The key is `tag`, not `name` -- lio ignores `name`, and `/apply` rejects a patch without a tag.
2. Add every schema field op to the patch via `POST /v2/schema/patch/{table}/{patch_id}/field`.
3. Add every mapping op via `POST /v2/schema/patch/{table}/{patch_id}/mapping`.
4. Before Step 6's confirmation ([workflow.md](workflow.md)), `GET /v2/schema/patch/{table}/{patch_id}` and include its diff in the rendered plan.
5. On approval, `POST /v2/schema/patch/{table}/{patch_id}/apply`.
6. On abort, `DELETE /v2/schema/patch/{table}/{patch_id}` to discard.

**Direct-publish path (when patches are not available):**
Write fields and mappings directly, then publish once per run with a tag like `account-sync-<src>-to-<dst>-<ISO8601>` and a description. A schema write is NOT complete until publish succeeds -- same rule as the `lytics-schema` skill.

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
5. Never auto-start a job. `POST /v2/job` **starts the job immediately unless `?run_job=false` is passed** (`run_job` defaults to `true`), so a synced export would begin sending to the destination platform the moment it is created. Always create with `?run_job=false` and let the user start it via `lytics-integrations` separately. Surface this in the plan.
6. Apply traceability append.
7. Write via `POST /v2/job?run_job=false` or `PUT /v2/job/{workflow}/{id}`. An update clears `description`, the quiet-window fields, `expires_at`, `meta`, `hidden` and `verbose_logging` whenever the body omits them, and a sent `config` replaces the stored one wholesale, so PUT the complete object -- never a partial body.

### Connections
1. Resolve the referenced auth in the destination by `(label, type)`. If missing, block.
2. Copy the connection config verbatim; apply traceability append.
3. Write via `POST /v2/connection` or `PUT /v2/connection/{id}`.

### Templates
Webhook templates (the `lytics-integrations` skill) are referenced by webhook-workflow jobs via `config.template_id`. Templates therefore sync **before** any dependent webhook job; the topological sort enforces this naturally via the dep edge added in Step 3 ([dependencies.md](dependencies.md)).

1. **Resolve destination by `(name, type)`** (`GET /v2/template`, filter, then `GET /v2/template/{id}` for the body).
2. **Probe source-body location** on the GET response. The body may be on `data` directly, on `data.body`, on `data.source`, or require `?include_body=true` / `/v2/template/{id}/source`. Cache the working shape per-account.
3. **Normalize source body on both sides** before diff:
   - Strip trailing whitespace per line
   - Normalize line endings to `\n`
   - Strip trailing blank lines
   - Strip server-assigned fields (`id`, `aid`, `account_id`, `author_id`, `created`, `updated`)
4. **Classify**: equal -> `skip`; differ -> `update` (or `conflict` under `--create-only`); missing in dst -> `create`.
5. **Write**:
   - Create: `POST /v2/template?name=<>&type=<>&description=<>` -- metadata in query string, body raw via `--data-binary`. Use `Content-Type: text/plain` first, fall back to `application/javascript` on 415 (see the `lytics-integrations` skill Probing Notes).
   - Update: `PUT /v2/template/{id}?name=<>&type=<>&description=<>` (the API reference says POST but the live endpoint requires PUT; see the `lytics-integrations` skill Probing Notes).
6. **Read-after-write**: GET the template back, re-normalize, expect zero diff. If the server normalized whitespace differently than we did, record `server_normalized` (not `server_drift`).
7. **Update the in-run map** `(template, name, type) -> dst_id` so dependent webhook jobs can remap `config.template_id` later in the topological order.

If a webhook job's `config.template_id` references a template that doesn't exist in the destination map (e.g., the user selected the job but excluded the template from the selector), halt with a blocker:
> "Job `<job-name>` references template `<src_template_name>` (`<src_template_id>`) which is not present in the destination. Re-run with `sync template <src_template_name> from <src> to <dst>` first, or include the template in your selector."

### Auth Providers
Auth is the trickiest type. Behavior:
- **Match-first**: For every auth referenced by any copied object, look up destination by `(label, type)`. If found, use its ID and proceed.
- **Missing auth**: halt before Step 7 ([workflow.md](workflow.md)) with a blocker listing:
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

## Write-Format Notes

### `is_public` / `public_name` Interdependence

- Setting `is_public: true` auto-populates `public_name` from the slug. Sending your own `public_name` alongside `is_public: true` may or may not be respected.
- Toggling a segment from public -> private via `PUT /v2/segment/{id}` with `is_public: false` does NOT clear `public_name`. The value persists. Probably intentional (external references may depend on it) but worth being aware of.

### Tag / Identifier Format Rules

- Schema patch `tag` must be **kebab-case**. ISO-8601 timestamps are not valid because they contain `:`. Replace `:` with `-` before using an ISO timestamp as part of a tag (e.g., `2026-04-16T20-38-25Z`).
- Segment `slug_name` must be URL-safe; the skill copies it verbatim from source.
- Stream names are case-sensitive and must match exactly.
