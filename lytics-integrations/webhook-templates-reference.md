# Webhook templates: reference

Supporting detail for `webhook-templates.md`: live-verified API behavior, the webhook job blueprints, synthetic fixture defaults and error handling.

## Probing notes

The template API has drifted between the public reference docs and the live runtime. These findings are confirmed against `api.lytics.io`; treat them as ground truth and do not "correct" them from docs alone.

| Unknown | Resolution |
|---|---|
| js1 entry-point name | **`function template(data) { ... }`** (not `transformData`). A missing entry point returns `500` with an empty body. Existing js1 templates on the platform consistently use `template`. |
| `desired_format` required for `/test` | **Yes.** Without it `/test` returns `500` with an empty body and no message. Set it on create or via `PUT`. Value: a JSON sample of the destination's expected payload, URL-encoded as a query param; `{}` works as a fallback. |
| Update verb | **`PUT /v2/template/{id}`** (not `POST`). The API reference says POST; the live endpoint answers `405 Method Not Allowed` with `Allow: GET, OPTIONS, DELETE, PUT, HEAD`. |
| Empty `job_config` on `/test` | The runtime does not pass `ly_job_config` as a global if `job_config` is `{}` or missing. Guard with `try { if (typeof ly_job_config === "string" && ly_job_config) { ... } } catch (e) {}`. Same for `ly_auth_config`. |
| Create body Content-Type | `text/plain` works for both `js1` and `jsonnet` raw bodies. No 415 fallback needed in practice; if one occurs, try `application/javascript` or `application/jsonnet`. |
| `type=js1` accepted? | **Yes**, despite being absent from the API reference enum. `jsonnet` and `handlebars` are also accepted. |
| Source body on GET | **Not retrievable.** `?include_body=true`, `?show_body=true`, `?fields=body`, `/v2/template/{id}/source`, `/body`, `/code`, `/raw` all return metadata only or `405`. Templates are write-only after creation. |
| `hmacSha256` vs `hmacSHA256` | Default to `hmacSha256` (most cited in examples). Accept either when reading existing templates. |
| Webhook job config names and enums | Docs and earlier blueprints drifted from the live API. As of 2026-04-27: workflow slugs `webhook_triggers` / `webhook_enrichment`; `segment_ids` (not `audiences`); `audience_events` with enum `""` / `enters_only` / `exits_only` (not `audience_trigger_events` with `enter`/`exit`); `do_not_retry` as `array[int]` (not a CSV string, not `do_not_retry_for_http_status`); `withbackfill` (not `existing_users`). There is **no `headers` field** -- headers come from the auth provider via `auth_ids[]`. |

## How auth and headers are threaded

Webhook job configs have **no `headers` field**. Headers (`X-API-TOKEN`, `Authorization`, ...) and URL query parameters live on the **auth provider**; at runtime Lytics reads them from the `auth_ids[]` reference and merges them into the outgoing request.

Create an auth provider of type `header_param_auth` (`connections.md`) and populate:
- `webhook_request_headers` -- newline-separated `key: value` text. Qualtrics example:
  ```
  X-API-TOKEN: <secret>
  Content-Type: application/json
  ```
- `webhook_request_params` -- URL query-string format (`key=value&key2=value2`), if the destination needs query-param auth.

For OAuth (`oauth2_client_credentials` auth type), Lytics auto-injects `Authorization: Bearer <token>`. To customize, put a literal `{token}` placeholder (single braces, **not** `{{token}}`) in the auth's `webhook_request_headers` -- e.g. `Authorization: Token token={token}` -- and Lytics substitutes it server-side at request time.

Templates can also read `ly_auth_config` (the auth's full config, JSON-encoded) inside the body -- for HMAC signing or other body-side credential use, separate from header injection.

## Verify the config shape before emitting

`GET /v2/provider` returns the webhook provider but does **not** expose its workflows' `config_routes`, so there is no machine-readable schema to probe. Instead, sanity-check against an existing webhook job in the destination account:

```bash
curl -sS "${LYTICS_API_URL:-https://api.lytics.io}/v2/job?show_all=true" -H "Authorization: ${LYTICS_API_TOKEN}" \
  | jq '.data[] | select(.workflow | test("webhook"; "i")) | {id, name, workflow, config}'
```

If at least one webhook job exists, its `config` keys are ground truth -- trust a live job over docs. If none exist, use the blueprints below; they were verified against a live `webhook_triggers` job and the workflow definitions in `lytics/lio` (`data/workflow/webhook_v2.json`, `data/workflow/webhook_enrichment.json`, and the `WebhookTriggers` / `WebhookEnrichment` structs in `src/api/v2/models/job_configs.go`).

## Job blueprints

Tag keys: **ASK USER**, **INFER FROM DOCS**, **FROM SKILL OUTPUT**, **RESOLVE** (probe Lytics). Annotate any field you could not infer with **"review carefully"** so the user catches it before the job is created.

### Audience triggers (default) -- `webhook_triggers`

```jsonc
{
  "name":        "<ASK USER -- defaults to '<destination> trigger for <segment>'>",
  "description": "<INFER>",
  "workflow":    "webhook_triggers",
  "auth_ids":    ["<auth id from connections.md -- the auth provider holds the credential headers>"],
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

### User enrichment -- `webhook_enrichment`

```jsonc
{
  "name":        "<ASK USER>",
  "description": "<INFER>",
  "workflow":    "webhook_enrichment",
  "auth_ids":    ["<auth id from connections.md>"],
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

Creating either job starts it immediately unless `?run_job=false` is passed (`jobs.md`).

## Synthetic fixture defaults

For each type returned by `GET /v2/schema/user/field`:

| Field type | Default value |
|---|---|
| `string` | `"sample_value"`; identity-like fields get realistic stand-ins (`email` -> `"test@example.com"`, `phone` -> `"+15555550100"`) |
| `int` / `number` | `1` |
| `bool` | `false` |
| `[]string` | `["sample"]` |
| `date` / `ts` | current ISO-8601 timestamp |
| `_segments` | `["test_segment"]` |
| `_id`, `_uid` | `"sample-id"` |

## Error handling

- **404 on a template** -- offer a fuzzy match against `list` (case-insensitive substring on `name`).
- **405 on `POST /v2/template/{id}`** -- the update verb is `PUT`. Retry with `PUT`.
- **500 with an empty body on `/test`** -- almost always `desired_format` unset, or a js1 entry point not named `template`. Check via `GET /v2/template/{id}`; set `desired_format` with `PUT` if missing; rename the function to `template(data)` if needed.
- **HTTP 200 with `data: "ReferenceError: ly_job_config is not defined"`** -- unguarded `JSON.parse(ly_job_config)`. Wrap it in `try { if (typeof ly_job_config === "string" && ly_job_config) { ... } } catch (e) {}` and re-test.
- **HTTP 200 with `data: "ReferenceError: <field>"`** (jsonnet) or a JS exception trace (js1) -- a referenced entity field is missing. Add a default fallback or pick the right field name from the Step 3 schema.
- **400 on create with `type=js1`** -- the account may not accept that enum. Surface a clear error; do not silently switch to `jsonnet`.
- **415 on create/update** -- retry with the alternate Content-Type (`application/javascript` for js1, `application/jsonnet` for jsonnet) and reuse the working value for the session.
- **HMAC mismatch reported by the destination** -- the secret in `ly_auth_config` differs from what the destination expects, or `hmacSha256` gets its inputs in the wrong order/encoding. Surface the destination's error verbatim.
- **WebFetch returns no useful content** (paywall, rate limit, JS-rendered) -- ask the user to paste the relevant docs section.
- **Destination returns 401 from the live job** -- the template works; the problem is the auth provider (`connections.md`).
