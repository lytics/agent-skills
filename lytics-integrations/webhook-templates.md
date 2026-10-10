# Webhook templates

Use to send audience triggers or enrichment requests to a custom webhook destination (Qualtrics, Slack, a custom CRM, ...), or to list, get, create, update, delete or test webhook templates. A template is the server-side transform that reshapes a user profile into the body the destination expects.

The headline flow is `build`: the user names a destination or pastes a docs URL; you fetch its API docs, infer payload + headers + auth model, draft a template, iterate against `/v2/template/{id}/test`, save it, and emit a webhook job blueprint. This mode never creates auths, connections or jobs itself: after the save, hand off to `connections.md` (auth) and `jobs.md` (job).

Two webhook workflows:
- **`webhook_triggers`** (default): event-based; fires on segment enter/exit.
- **`webhook_enrichment`**: request/response; sends a profile and lands the response in a stream.

Live-verified API quirks, the job blueprints and error handling are in `webhook-templates-reference.md` -- read it before emitting a blueprint or when a call misbehaves.

## Operations

| Operation | Request |
|---|---|
| list | `GET /v2/template` |
| get | `GET /v2/template/{id}` |
| create | `POST /v2/template` -- metadata in the query string, raw source as the body; `desired_format` needed for `/test` |
| update | `PUT /v2/template/{id}` -- **PUT, not POST** (the API reference is wrong) |
| delete | `DELETE /v2/template/{id}` |
| test | `POST /v2/template/{id}/test` with `--profile=<field>=<value>`, `--synthetic` or `--json=<file-or-paste>` |
| build | `<destination-name or docs-URL>`, trigger (default) or enrichment workflow |
| draft | Same as build, but stops before the save |

Reads (list, get) run immediately; show templates as a table of id, name, type, description, updated. Writes (create, update, delete, and the save in `build`) go through `references/confirmation-gate.md`: show the full payload (raw source plus query-param metadata) and the resolved curl, and require an explicit `yes`. A test against an already-saved template needs no confirmation (it is read-only on the destination); render the response inline. A draft created during `build` has already been through the create gate.

**list / get return metadata only** (`id`, `name`, `type`, `description`, `target`, `field_filter`, `desired_format`, `created`, `updated`, `author_id`). The source body is not retrievable from any GET path; templates are write-only after creation. If the user wants source history, recommend keeping the template body in their own version control.

### Create and update

```bash
curl -sS -X POST \
  "${LYTICS_API_URL:-https://api.lytics.io}/v2/template?name=${NAME}&type=${TYPE}&description=${DESCRIPTION}&desired_format=${DESIRED_FORMAT}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-binary @template.js
```

- Metadata (`name`, `type`, `description`, optional `account_id`, **`desired_format`**) goes in the **query string**; the template source goes in the **body** as raw text (`text/plain` works for `js1` and `jsonnet`).
- `type` enum: `js1`, `jsonnet`, `handlebars`. The API reference omits `js1`, but production accepts it.
- **`desired_format` is required for `/test`.** It is a JSON sample of the destination's expected payload (URL-encode it). Without it `/test` returns `500` with an empty body. Use the inferred body shape from build Step 4; a minimal `{}` works as a fallback.
- Update is the same request with `-X PUT` to `/v2/template/{id}?name=...&type=...&description=...&desired_format=...`. `POST` on that route returns `405 Method Not Allowed` (`Allow: GET, OPTIONS, DELETE, PUT, HEAD`). Don't "correct" it back to POST.

### Test

```bash
curl -sS -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/template/${TEMPLATE_ID}/test" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "job_config": {"audience_events": "enters_only", "webhook_url": "https://example.com/webhook"},
    "entity": {"email": "test@example.com", "first_name": "Ada", "last_name": "Lovelace", "_segments": ["high_value_customers"]}
  }'
```

The body is `{job_config, entity}`. Synthesize `job_config` from a stripped-down version of the eventual webhook job config (blueprint field names in `webhook-templates-reference.md`) so the template runs against the config it will see in production. Response: `{data: "<rendered string>", status: 200, request_id: "..."}` -- the rendered string is the body that would be POSTed to the destination.

| Test source | Flag | How |
|---|---|---|
| Real profile | `--profile=<field>=<value>` | `GET /api/entity/user/<field>/<value>` (the `lytics-profiles` skill); use the returned profile as `entity` |
| Synthetic fixture | `--synthetic` | `GET /v2/schema/user/field` (the `lytics-schema` skill); build a fixture per type (defaults in `webhook-templates-reference.md`) |
| User-supplied JSON | `--json=<file-or-paste>` | Accept a literal JSON entity blob; validate it parses |

Test-endpoint quirks:
- **A template that threw still returns HTTP 200**: `{data: "<error message>", status: 200}`. Inspect `data` for the prefix `"evaluating snippet: RUNTIME ERROR"` (jsonnet) or a JS exception trace (js1).
- `job_config` missing or `{}` -> the runtime does not pass `ly_job_config` as a global, and an unguarded `JSON.parse(ly_job_config || "{}")` throws `ReferenceError: ly_job_config is not defined`. Same for `ly_auth_config`. Guard as in the Step 5 scaffold.
- HTTP `500` with an empty body -> most commonly `desired_format` unset; set it via `PUT` and retry.

## Template language

Default to `js1` (JavaScript). The js1 runtime expects the entry point **`function template(data) { ... }`** -- not `transformData`, which appears in some external docs but does not match the runtime (a missing entry point returns `500` with an empty body). Globals: `ly_auth_config` and `ly_job_config` (both JSON strings; parse defensively). Helper: `hmacSha256(message, key)` for signed requests.

**Do not pivot languages without confirming.** If js1 returns a non-deterministic error (e.g. `/test` 500 with an empty body), do not silently switch to `jsonnet`. Diagnose first: confirm `desired_format` is set; confirm the function is named `template`; run `/test` against an existing js1 template on the same account to rule out platform issues. Switch to `jsonnet` only after surfacing the failure and getting explicit approval -- the switch rewrites the whole template body.

Use `jsonnet` when the user explicitly requests it, when the destination needs a feature easier in jsonnet (heavy use of `event.inSeg`, `event.segSlug`, etc.), or when the user approved the switch after a confirmed js1 runtime issue.

## Build flow

### Step 1: Identify the destination

Input is a name ("Qualtrics", "Slack"), a docs URL, or a free-form description ("post a Slack message to #alerts when a user enters segment X"). For a bare name, `WebSearch` for `<destination> webhook events API reference` and confirm the top result with the user before continuing.

### Step 2: Fetch the destination docs

`WebFetch` the destination's API reference and extract:
- HTTP method and URL pattern (note path parameters).
- Required headers (auth header style, `Content-Type`, signature/HMAC headers).
- Request body shape -- a full JSON example, nesting, required vs optional fields.
- Auth model (API key in header, bearer token, HMAC-signed body, OAuth).
- Rate limits and non-retry status codes (for the job's `do_not_retry`).

Paywalled, rate-limited, JS-rendered or empty page: ask the user to paste the relevant section.

### Step 3: Pull sample profile context

Ground field references in the real schema: a real profile via the `lytics-profiles` skill (user gives identity field + value), or a synthetic fixture via the `lytics-schema` skill (`GET /v2/schema/user/field`). Confirm every Lytics field the draft references exists.

### Step 4: Show the inferred payload and headers

Let the user correct this before drafting code, and call out everything they must supply (datacenter, subscription ids, secret values):

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

### Step 5: Draft the template

```javascript
// Drafted for <destination> on <YYYY-MM-DD>
function template(data) {
  // ly_auth_config / ly_job_config may be undefined globals at runtime
  // (e.g. when /test is called with an empty job_config). Always guard.
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
- Entry point is `template`, not `transformData`.
- Use `data.<field>` only for fields confirmed in Step 3.
- Defaults: `|| ""` for strings, `|| 0` for numbers, `|| []` for arrays -- webhook destinations rarely tolerate `null`.
- Always guard `ly_auth_config` / `ly_job_config` with a `typeof === "string"` check plus `try/catch`.
- `hmacSha256(message, key)` if the destination signs requests.
- A header comment line for traceability.

Show the source and iterate on feedback in memory; do not write to the API yet.

### Step 6: /test loop

`/test` needs an existing template id, so save a draft first (through the create gate) named `_draft_<unix-ts>_<destination-slug>` so it's easy to spot in `list`, with `desired_format` set:

```bash
DRAFT_NAME="_draft_$(date +%s)_qualtrics"
# desired_format is a JSON sample of the destination payload; URL-encode it.
DESIRED_FORMAT=$(printf '%s' '{"firstName":"","lastName":"","email":"","embeddedData":{}}' \
  | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")
curl -sS -X POST \
  "${LYTICS_API_URL:-https://api.lytics.io}/v2/template?name=${DRAFT_NAME}&type=js1&description=Draft%20for%20${DESTINATION}&desired_format=${DESIRED_FORMAT}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: text/plain" --data-binary @template.js
```

Capture the returned `template_id`, test, and on feedback `PUT /v2/template/{id}` and re-test until the rendered output looks right. Tell the user `_draft_*` templates may show up in their Lytics UI list until Step 7 renames them.

### Step 7: Save (rename)

Once tests pass, ask for the final name and description, then `update` to rename the draft -- full payload through the confirmation gate.

### Step 8: Emit the job blueprint and hand off

Check the live config shape first (`webhook-templates-reference.md`), then print the full webhook job payload with `template_id` filled in, inferred values (`webhook_url`, `http_method`, `do_not_retry` from the rate-limit docs), and placeholders for the rest (`auth_ids: ["<TODO: auth id from connections.md>"]`, `segment_ids: ["<segment_id>"]`). Headers inferred in Step 4 go on the auth provider, not the job. Then hand off explicitly:

> Template saved as `<final_name>` (`<template_id>`). To wire up the job:
> 1. Create a `header_param_auth` auth provider for the destination (`connections.md`). Put every header the destination needs (`X-API-TOKEN`, `Content-Type`, ...) in `webhook_request_headers` as `key: value` lines, one per line. Capture the returned `auth_id`.
> 2. Create the job with the config below (`jobs.md`), substituting that `auth_id` into `auth_ids[]`. Lytics auto-injects the auth's headers into every outgoing request at runtime -- the job config itself has **no `headers` field**.

A destination returning 401 from the live job is an auth problem, not a template problem: fix the auth provider (`connections.md`).
