---
name: webhook-template-builder
description: Research-driven authoring of Lytics webhook templates -- fetches destination docs, drafts and tests the transform, and emits a ready-to-go webhook job blueprint. Use when the user wants to send Lytics audience triggers or enrichment requests to a custom webhook destination (e.g., Qualtrics, Slack, custom CRM).
metadata:
  arguments: action and target -- list, get, create, update, delete, test, build <destination | docs URL> [--workflow=trigger|enrichment]
---

# Webhook Template Builder

## Purpose
Author and iterate Lytics webhook templates -- the server-side transforms that reshape a user profile into the body shape required by an arbitrary external webhook destination. The headline mode is `build`: the user names a destination (e.g. "Qualtrics") or pastes a docs URL, and the skill fetches the destination's API docs, infers the required payload + headers + auth model, drafts a template, iterates against `/v2/template/{id}/test`, saves, and emits a ready-to-go webhook job blueprint.

The skill never creates auths, connections, or jobs itself. After the template is saved, it hands off to `connection-manager skill` (auth) and `job-manager skill` (job) -- same orchestrator boundary as `integration-setup skill`.

Two webhook workflows are supported:
- **`webhook_triggers`** (default): event-based; fires on segment enter/exit.
- **`webhook_enrichment`** (`--workflow=enrichment`): request/response; sends a profile and lands the response into a stream.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## Invocation

```
list                                              # GET /v2/template
get <id-or-name>                                  # GET /v2/template/{id}
create <name> --type=js1|jsonnet|handlebars [--desired-format=<json-sample>]   # POST /v2/template (raw body); desired_format required for /test
update <id-or-name>                               # PUT /v2/template/{id}  (PUT, not POST -- API reference is wrong)
delete <id-or-name>                               # DELETE /v2/template/{id}
test <id-or-name> [--profile=<field>=<value> | --synthetic | --json=<file-or-paste>]
build <destination-name | docs-URL> [--workflow=trigger|enrichment]
draft <destination-name | docs-URL>               # alias for build that stops before save
```

Reads (`list`, `get`) execute immediately. Writes (`create`, `update`, `delete`) and the final save in `build` use the confirmation-gate pattern (`../references/confirmation-gate.md`).

## Default Template Language

Default to `js1` (JavaScript). The Lytics js1 runtime expects the entry point to be **`function template(data) { ... }`** (NOT `transformData`, which appears in some external docs but does not match the runtime). Globals: `ly_auth_config` and `ly_job_config` (both JSON strings; `JSON.parse` them defensively -- see Step 5). Helper: `hmacSha256(message, key)` for signed requests.

### Do not pivot languages without confirming

If `js1` returns a non-deterministic error (e.g. `/test` 500 with empty body), **do not silently switch to `jsonnet`**. Diagnose first:
- Confirm `desired_format` is set on the template (see Probing Notes -- this is the most common cause of 500-with-empty-body on `/test`).
- Confirm the function is named `template`, not `transformData`.
- Test `/test` against an existing js1 template on the same account to rule out platform issues.

Only switch to `jsonnet` after surfacing the failure to the user and getting explicit approval. The switch rewrites the entire template body and the user must agree to the language change.

Use `jsonnet` when:
- The user explicitly requests it
- The destination needs a templating feature easier in jsonnet (heavy use of `event.inSeg`, `event.segSlug`, etc.)
- The user approved the switch after a confirmed js1 runtime issue

## Research-Driven Authoring Flow (`build`)

### Step 1: Identify Destination
Parse the user's input. Three forms:
- **Name** ("Qualtrics", "Slack")
- **Docs URL** ("https://api.qualtrics.com/...")
- **Free-form description** ("post a Slack message to #alerts when a user enters segment X")

If the input is a bare name, run a `WebSearch` for `<destination> webhook events API reference` and confirm the top result with the user before continuing.

### Step 2: Fetch Destination Docs
Use `WebFetch` against the destination's API reference. Extract:
- HTTP method and URL pattern (note any path parameters)
- Required headers (auth header style, `Content-Type`, signature/HMAC headers if any)
- Request body shape -- a full JSON example, nested structure, required vs optional fields
- Auth model (API key in header, bearer token, HMAC-signed body, OAuth)
- Rate limits and non-retry status codes (so we can populate `do_not_retry_for_http_status`)

If the docs page is paywalled or empty, ask the user to paste the relevant section.

### Step 3: Pull Sample Profile Context
Ground field references in real schema. Either:
- **Real profile** via `entity-lookup skill` (user provides identity field + value)
- **Synthetic** via `schema-discovery skill` (build a fixture from `GET /v2/schema/user/field`)

Use this to confirm Lytics field names referenced in the draft actually exist.

### Step 4: Show Inferred Payload + Headers
Surface a summary the user can correct before we draft code:

```
Destination: Qualtrics XM Events API
Method: POST
URL pattern: https://{datacenter}.qualtrics.com/eventsubscriptions/{subscription}/events
Headers:
  - X-API-TOKEN: <secret>            -> needs auth provider
  - Content-Type: application/json
Body shape:
  { "events": [ { "type": "...", "user": { "email": "..." }, "data": { ... } } ] }
Auth model: API key in X-API-TOKEN header
Non-retry status codes: 400, 401, 403, 404
```

Surface anything the user must supply (datacenter, subscription IDs, secret values).

### Step 5: Draft the Template
Generate `js1` source using the runtime's expected entry point `function template(data) { ... }`:

```javascript
// Drafted by webhook-template-builder for <destination> on <YYYY-MM-DD>
function template(data) {
  // Defensive: ly_auth_config / ly_job_config may be undefined globals at runtime
  // (e.g., when /test is called with an empty job_config). Always guard with try/catch.
  var auth = {};
  var job  = {};
  try { if (typeof ly_auth_config === "string" && ly_auth_config) { auth = JSON.parse(ly_auth_config); } } catch (e) {}
  try { if (typeof ly_job_config  === "string" && ly_job_config)  { job  = JSON.parse(ly_job_config);  } } catch (e) {}

  return {
    events: [
      {
        type: "user_segment_enter",
        user: { email: data.email || "" },
        data: {
          first_name: data.first_name || "",
          last_name:  data.last_name  || "",
          ltv:        data.ltv        || 0
        }
      }
    ]
  };
}
```

Conventions:
- **Function name is `template`, not `transformData`.** The Lytics js1 runtime returns `500` with an empty body if the entry point is missing. Existing js1 templates on the platform consistently use `template(data)`.
- Use `data.<field>` references for fields confirmed to exist in Step 3.
- Defaults: `|| ""` for strings, `|| 0` for numbers, `|| []` for arrays. Webhook destinations rarely tolerate `null`.
- **Always guard `ly_auth_config` and `ly_job_config` with `typeof === "string"` checks plus `try/catch`.** The `/test` endpoint does not pass these globals when the corresponding key is empty/missing in the request, and an unguarded `JSON.parse(ly_job_config || "{}")` will throw `ReferenceError` at runtime.
- `hmacSha256(message, key)` if the destination signs requests.
- Header comment line for traceability.

Show the source to the user. Iterate on feedback in-memory; do not write to the API yet.

### Step 6: /test Loop
The `/test` endpoint requires an existing template ID, so save a draft first. Use a draft name of the form `_draft_<unix-ts>_<destination-slug>` so it's easy to spot in `list`. **`desired_format` must be set on create** -- without it `/test` returns `500` with an empty body. Use the inferred response shape from Step 4 (a sample of what the destination expects); a minimal `{}` works as a fallback.

```bash
DRAFT_NAME="_draft_$(date +%s)_qualtrics"
# desired_format is a JSON sample of the destination payload; URL-encode it.
DESIRED_FORMAT=$(printf '%s' '{"firstName":"","lastName":"","email":"","embeddedData":{}}' \
  | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")

# Save the draft
curl -s -X POST \
  "${LYTICS_API_URL:-https://api.lytics.io}/v2/template?name=${DRAFT_NAME}&type=js1&description=Draft%20for%20${DESTINATION}&desired_format=${DESIRED_FORMAT}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary @template.js
```

Capture the returned `template_id`. Then test (see Test Workflow below). On feedback, update via `PUT /v2/template/{id}` and re-test. Repeat until the rendered output looks right.

Mention to the user that `_draft_*` templates may show up in their Lytics UI list; they will be renamed in Step 7.

### Step 7: Save (Rename)
Once tests pass, prompt for the final name + description, then run `update` to rename the draft. Show the full payload through the confirmation gate (`../references/confirmation-gate.md`) before writing.

### Step 8: Emit Job Blueprint and Hand Off
Print the full webhook job config payload (see Webhook-Job Hand-Off Blueprint below) with:
- `template_id` populated
- Inferred values (`headers` from Step 4, `do_not_retry_for_http_status` from rate-limit docs)
- Placeholders for the rest (`auth_ids: ["<TODO via connection-manager>"]`, `audiences: ["<segment_id>"]`)

Then explicitly hand off:
> "Template saved as `<final_name>` (`<template_id>`). To wire up the job:
> 1. Run `connection-manager skill` to create a `header_param_auth` provider for the destination. Populate `webhook_request_headers` with `key: value` lines (one per line) covering everything the destination needs (`X-API-TOKEN`, `Content-Type`, etc.). Capture the returned `auth_id`.
> 2. Run `job-manager skill` with the config below, substituting the `auth_id` into `auth_ids[]`. Lytics auto-injects the auth's headers into every outgoing request at job runtime -- the job config itself does NOT have a `headers` field."

## Test Workflow

| Mode | Flag | Source |
|------|------|--------|
| Real profile | `--profile=<field>=<value>` | Composes `entity-lookup skill` (`GET /api/entity/user/<field>/<value>`); use the returned profile as `entity` |
| Synthetic fixture | `--synthetic` | Composes `schema-discovery skill` (`GET /v2/schema/user/field`); build a fixture per type |
| User-supplied JSON | `--json=<file-or-paste>` | Accept a literal JSON entity blob; validate it parses |

The test request body is `{job_config, entity}`. Synthesize `job_config` from a stripped-down version of the eventual webhook job config (`audience_trigger_events`, `webhook_url`, headers, etc.) so the template runs against the actual config it'll see in production. The render output is a string -- that string is the body that would be POSTed to the destination.

### Synthetic Fixture Defaults
For each type returned by `GET /v2/schema/user/field`, fill plausible values:

| Field type | Default value |
|------------|--------------|
| `string` | `"sample_value"`. Identity-y fields use realistic stand-ins (`email` -> `"test@example.com"`, `phone` -> `"+15555550100"`). |
| `int` / `number` | `1` |
| `bool` | `false` |
| `[]string` | `["sample"]` |
| `date` / `ts` | current ISO-8601 timestamp |
| `_segments` | `["test_segment"]` |
| `_id`, `_uid` | `"sample-id"` |

## API Endpoints

### List Templates
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/template" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
List response is metadata-only -- no source body. **Body is not retrievable from any GET endpoint** (see Probing Notes); only `name`, `type`, `description`, `desired_format`, and timestamps are available.

### Get Template
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/template/${TEMPLATE_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
**Returns metadata only** (`id`, `name`, `type`, `description`, `target`, `field_filter`, `desired_format`, `created`, `updated`, `author_id`). The source body is not retrievable via any GET path -- see Probing Notes. If the user wants source-level history, recommend they keep the template body in their own version control.

### Create Template
```bash
curl -s -X POST \
  "${LYTICS_API_URL:-https://api.lytics.io}/v2/template?name=${NAME}&type=${TYPE}&description=${DESCRIPTION}&desired_format=${DESIRED_FORMAT}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary @template.js
```
- Metadata (`name`, `type`, `description`, optional `account_id`, **`desired_format`**) goes in the **query string**.
- Template source goes in the **body** as raw text.
- `type` enum: `js1`, `jsonnet`, `handlebars`. The Lytics API reference page omits `js1`, but it is supported in production. If the API rejects it (`400 invalid type`), see Probing Notes.
- **`desired_format` is required for `/test` to succeed.** It is a sample of the destination's expected payload (a JSON string -- URL-encode it). If empty, `/test` returns `500` with an empty body. Use the inferred body shape from the destination's docs (Step 4); a minimal `{}` works as a placeholder if nothing better is available.

### Update Template
```bash
curl -s -X PUT \
  "${LYTICS_API_URL:-https://api.lytics.io}/v2/template/${TEMPLATE_ID}?name=${NAME}&type=${TYPE}&description=${DESCRIPTION}&desired_format=${DESIRED_FORMAT}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary @template.js
```
**Update is `PUT /v2/template/{id}`, not `POST`.** The Lytics API reference page documents this incorrectly as `POST`; the live API responds to `POST` on this route with `405 Method Not Allowed` and `Allow: GET, OPTIONS, DELETE, PUT, HEAD`. Don't "correct" this back to POST in a refactor.

### Delete Template
```bash
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/template/${TEMPLATE_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Test Template
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/template/${TEMPLATE_ID}/test" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "job_config": {
      "audience_trigger_events": "enter",
      "webhook_url": "https://example.com/webhook"
    },
    "entity": {
      "email": "test@example.com",
      "first_name": "Ada",
      "last_name": "Lovelace",
      "_segments": ["high_value_customers"]
    }
  }'
```
Response: `{data: "<rendered string>", status: 200, request_id: "..."}`. The rendered string is the body that would be POSTed to the destination.

**Test-endpoint quirks worth knowing:**
- If the request body is missing `job_config` entirely, or `job_config` is `{}`, the runtime does NOT pass `ly_job_config` as a global. An unguarded `JSON.parse(ly_job_config || "{}")` then throws `ReferenceError: ly_job_config is not defined`. Always guard with `try { if (typeof ly_job_config === "string" && ly_job_config) { ... } } catch (e) {}` (Step 5 scaffold does this).
- Runtime errors come back via `{data: "<error message>", status: 200}` -- HTTP `200` even when the template threw. Inspect `data` for the prefix `"evaluating snippet: RUNTIME ERROR"` (jsonnet) or a JS exception trace (js1).
- If `/test` returns HTTP `500` with an empty body, the most common cause is `desired_format` being unset on the template. Set it via `PUT` and retry.

## Probing Notes

Several details of the template API drifted between the public reference docs and the live runtime. The findings below are confirmed against `api.lytics.io`. Treat them as ground truth; do not reorder or "correct" them based on docs alone.

| Unknown | Resolution |
|---------|------------|
| js1 entry-point function name | **`function template(data) { ... }`** (NOT `transformData`). The runtime returns `500` with an empty body if the entry point is missing. Existing js1 templates on the platform consistently use `template`. |
| `desired_format` required for `/test` | **Yes.** Without it, `/test` returns `500` with an empty body -- no error message. Set it on create or via `PUT` update. The value is a JSON sample of the destination's expected payload (URL-encode it as a query param). A minimal `{}` works as a fallback. |
| Update verb | **`PUT /v2/template/{id}`** (NOT `POST`). The API reference says POST; the live endpoint responds `405 Method Not Allowed` with `Allow: GET, OPTIONS, DELETE, PUT, HEAD`. |
| Empty `job_config` on `/test` | The runtime does NOT pass `ly_job_config` as a global if `job_config` is `{}` or missing in the test body. Templates must guard with `try { if (typeof ly_job_config === "string" && ly_job_config) { ... } } catch (e) {}`. Same applies to `ly_auth_config`. |
| Create body Content-Type | `text/plain` works for both `js1` and `jsonnet` raw bodies. No 415 fallback needed in practice; if encountered, try `application/javascript` or `application/jsonnet`. |
| `type=js1` accepted? | **Yes**, despite being absent from the API reference enum. `jsonnet` and `handlebars` are also accepted. |
| Source body on GET response | **Not retrievable.** Tried `?include_body=true`, `?show_body=true`, `?fields=body`, `/v2/template/{id}/source`, `/body`, `/code`, `/raw` -- all return metadata-only or `405`. Templates are write-only after creation; keep the source under the user's own version control if they want history. |
| `hmacSha256` vs `hmacSHA256` | Default `hmacSha256` (most-cited in examples). Accept either when reading existing templates. |
| Webhook job config field names + enum values | Public docs and prior blueprint examples have drifted from the live API. `GET /v2/provider` does NOT expose workflow `config_routes` on this API surface; the cleanest sanity check is to list existing webhook jobs (`GET /v2/job?show_all=true`, filter `workflow ~= /webhook/`) and read their `config` shape. As of 2026-04-27 the live names are `webhook_triggers` / `webhook_enrichment` (workflow slugs), `segment_ids` (not `audiences`), `audience_events` with enum `""`/`enters_only`/`exits_only` (not `audience_trigger_events` with `enter`/`exit`), `do_not_retry` as `array[int]` (not CSV string), `withbackfill` (not `existing_users`). There is **no `headers` field** -- headers come from the auth provider via `auth_ids[]`. |

## Webhook-Job Hand-Off Blueprint

Tag-key conventions: **ASK USER**, **INFER FROM DOCS**, **FROM SKILL OUTPUT**, **RESOLVE** (probe Lytics).

### How auth and headers are threaded

Webhook job configs do **NOT** have a `headers` field. Headers (`X-API-TOKEN`, `Authorization`, etc.) and URL query parameters live on the **auth provider**, not on the job. At runtime Lytics extracts them from the `auth_ids[]` reference and merges them into the outgoing request automatically.

When you hand off to `connection-manager skill`, instruct the user to create an auth provider of type `header_param_auth` and populate:

- `webhook_request_headers` -- newline-separated `key: value` text. Example for Qualtrics:
  ```
  X-API-TOKEN: <secret>
  Content-Type: application/json
  ```
- `webhook_request_params` -- URL query string format (`key=value&key2=value2`), if the destination needs query-param auth.

For OAuth (`oauth2_client_credentials` auth type), Lytics auto-injects `Authorization: Bearer <token>`. To customize, put a literal `{token}` placeholder (single braces, NOT `{{token}}`) inside the auth's `webhook_request_headers` -- e.g. `Authorization: Token token={token}` -- and Lytics replaces it server-side at request time.

Templates can ALSO read `ly_auth_config` (the auth's full config blob, JSON-encoded) inside the template body -- this is for HMAC signing or other body-side credential use, separate from header injection.

### Verify the workflow config schema before emitting

The verified slugs as of 2026-04-27 are `webhook_triggers` and `webhook_enrichment`, with the field shapes shown in the blueprints below. **`GET /v2/provider` returns the webhook provider but does NOT expose its workflows' `config_routes`** on this API surface, so there's no clean machine-readable schema endpoint to probe. Instead, sanity-check against an existing webhook job in the destination account before emitting the blueprint:

```bash
# List webhook jobs and inspect their config shape
curl -s "${LYTICS_API_URL}/v2/job?show_all=true" -H "Authorization: ${LYTICS_API_TOKEN}" \
  | jq '.data[] | select(.workflow | test("webhook"; "i")) | {id, name, workflow, config}'
```

If at least one webhook job exists, its `config` keys are ground truth. If none exist, fall through to the blueprints below -- they were verified against a live `webhook_triggers` job and the underlying workflow definitions in `lytics/lio` (`data/workflow/webhook_v2.json`, `data/workflow/webhook_enrichment.json`, and the `WebhookTriggers`/`WebhookEnrichment` Go structs in `src/api/v2/models/job_configs.go`). Field names have drifted from public docs in the past (e.g., the live API uses `audience_events` not `audience_trigger_events`, `segment_ids` not `audiences`, `do_not_retry` as `array[int]` not a CSV string, and has no `headers` field at all) -- when in doubt, trust an existing live job over docs.

### Audience Triggers (`--workflow=trigger`, default)

Corresponds to the `webhook_triggers` workflow. Verified shape:

```jsonc
{
  "name":        "<ASK USER -- defaults to '<destination> trigger for <segment>'>",
  "description": "<INFER>",
  "workflow":    "webhook_triggers",
  "auth_ids":    ["<FROM connection-manager hand-off -- the auth provider holds the credential headers>"],
  "config": {
    "segment_ids":         ["<ASK USER -- segment hex id(s) (NOT slugs)>"],
    "webhook_url":         "<INFER FROM DOCS or ASK USER -- must be HTTPS>",
    "http_method":         "POST",                                  // enum: GET|POST|PUT|PATCH|DELETE
    "audience_events":     "",                                      // enum: "" (both, default), "enters_only", "exits_only"
    "template_id":         "<FROM SKILL OUTPUT -- omit for raw default Lytics payload>",
    "user_fields":         null,                                    // optional: subset of profile fields to export; null = all
    "field_changes":       [],                                      // optional: up to 75 field names whose changes also trigger
    "withbackfill":        false,                                   // include users already in audience
    "include_segs":        false,                                   // include profile's segment membership as `segments_all`
    "batch_requests":      false,
    "batch_size":          10,                                      // max 1000
    "batch_flush_duration": 5,                                      // seconds, max 300
    "worker_count":        5,                                       // max 20
    "do_not_retry":        [400, 401, 403, 404],                    // array[int] -- HTTP statuses to NOT retry
    "cloudevents":         false,                                   // wrap payload in CloudEvents v1.0 envelope
    "cloudevents_type":    null,                                    // default: com.lytics.audience.user.event
    "cloudevents_source":  null                                     // default: /work/id
  }
}
```

### User Enrichment (`--workflow=enrichment`)

Corresponds to the `webhook_enrichment` workflow. Verified shape:

```jsonc
{
  "name":        "<ASK USER>",
  "description": "<INFER>",
  "workflow":    "webhook_enrichment",
  "auth_ids":    ["<FROM connection-manager hand-off>"],
  "config": {
    "segment_ids":     ["<ASK USER -- segment hex id(s)>"],
    "stream":          "webhook_enrichment",                        // optional; lands the response in stream of this name
    "webhook_url":     "<INFER FROM DOCS or ASK USER -- must be HTTPS>",
    "http_method":     "POST",                                      // enum: GET|POST|PUT|PATCH (no DELETE for enrichment)
    "template_id":     "<FROM SKILL OUTPUT>",
    "user_fields":     null,                                        // optional: subset of profile fields to send
    "field_changes":   [],                                          // optional: trigger on field changes (up to 75)
    "withbackfill":    true,                                        // NOTE: defaults to true for enrichment (false for triggers)
    "audience_events": "",                                          // enum: "" (both) | "enters_only" | "exits_only"
    "worker_count":    5,                                           // max 20
    "do_not_retry":    [400, 401, 403, 404]                         // array[int]
  }
}
```

Annotate any field the skill could not infer with **"review carefully"** so the user catches it before `job-manager` writes. **Note:** there is no `headers` field on either workflow's config -- credentials are threaded via `auth_ids[]`. See "How auth and headers are threaded" above.

## Behavior

### For Read Operations (`list`, `get`)
Execute immediately. Display templates in a table format showing: ID, name, type, description, updated.

### For Write Operations (`create`, `update`, `delete`, save step of `build`)
Use the confirmation-gate pattern. Show the full payload (raw source plus query-param metadata) and the resolved curl invocation; require explicit `yes` before writing.

### For `test`
No confirmation needed for a test against an already-saved template -- it's read-only on the destination. Render the response inline. If the test was run against a draft created during `build`, treat the draft itself as having gone through the create gate already.

## Error Handling
- **404 on template** -- offer a fuzzy-match against `list` (case-insensitive substring on `name`).
- **405 on `POST /v2/template/{id}`** -- the update verb is `PUT`, not `POST`. Retry with `PUT`.
- **500 with empty body on `/test`** -- almost always means `desired_format` is unset on the template, OR the js1 entry point is named something other than `template`. Check both via `GET /v2/template/{id}`; set `desired_format` via `PUT` if missing; rename the function in the source if it isn't `template(data)`.
- **`HTTP 200` with `data: "ReferenceError: ly_job_config is not defined"`** -- the template parses an unguarded `JSON.parse(ly_job_config)`. Wrap in `try { if (typeof ly_job_config === "string" && ly_job_config) { ... } } catch (e) {}` and re-test.
- **`HTTP 200` with `data: "ReferenceError: <field>"`** (jsonnet) or a JS exception trace (js1) -- referenced entity field missing. Add a default fallback or pick the right field name from Step 3 schema discovery.
- **400 on create with `type=js1`** -- API may not accept that enum on this account. Surface a clear error to the user; do not silently switch to `jsonnet` (Default Template Language section).
- **415 on create / update** -- Content-Type probe failed; retry with the alternate (`application/javascript` for `js1`, `application/jsonnet` for `jsonnet`). Cache the working value for the session.
- **HMAC mismatch reported by destination** -- secret in `ly_auth_config` differs from the destination's expectation, or `hmacSha256` is being passed inputs in the wrong order/encoding. Surface the destination's error verbatim.
- **WebFetch returns no useful content** (paywall, rate limit, JS-rendered) -- prompt the user to paste the relevant docs section.
- **Destination returns 401 in the live job** -- this skill saved a working template; the issue is auth. Route the user to `connection-manager skill`.

## Dependencies
- Composes: `entity-lookup skill`, `schema-discovery skill`, `connection-manager skill`, `job-manager skill`
- Uses: `../references/auth.md`, `../references/api-client.md`, `../references/confirmation-gate.md`, `../references/api-response-format.md`
- Related: `integration-setup skill` (orchestrator hand-off pattern), `integration-advisor skill` (research-driven advisor pattern)
