# Calling the Lytics API

How to make a request and read the answer. Credentials: `auth.md`. Writes: `confirmation-gate.md`.

## Request

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

- Send the token as-is in `Authorization` (no `Bearer` prefix).
- `-w '%{http_code}'` is the only way to see the HTTP status; check it before trusting the body.
- **URL-encode every value you put in a path or query** (emails contain `@`, names contain spaces): `curl -G --data-urlencode "q=${TERM}" ...`, or `jq -rn --arg v "$V" '$v|@uri'` for path segments.
- Send JSON bodies with `-H "Content-Type: application/json" --data-binary @body.json`. A single-quoted `-d '...'` breaks as soon as a value contains an apostrophe.

## Response: two shapes

`/v2/...` and `/api/...` answer differently. Read errors from the right place, or a failed call looks like an empty success.

| | `/v2/...` | `/api/...` |
|---|---|---|
| Success | `{"data": ..., "status": 200, "request_id": "..."}` | `{"data": ..., "status": 200, "message": "success"}` |
| Error | `{"status": 4xx, "errors": [{"code": "BADREQ-001", "message": "...", "level": "warn"}], "request_id": "..."}` | `{"data": null, "status": 4xx, "message": "..."}` |
| Read the error | `.errors[0].message` | `.message` |
| Paging | Endpoint-specific; some return `_meta: {"has_more": true, "next_before": "..."}` | Endpoint-specific |

- A rejected token is answered before the request reaches either API, so a `401` on `/v2` also comes back in the `/api` shape: `{"message": "Not authorized", "status": 401}`.
- Many `/v2` deletes return `204` with no body.
- **A 200 is not always a success.** `/api/entity` answers a missing profile with HTTP 200, `"message": "Not Found"` and a placeholder `{"segments": ["not_found", "all"]}`. Each skill notes the cases that matter to it.

## Errors

| Status | Meaning | What to do |
|---|---|---|
| 400 | Bad request; the message says why (bad payload, unparseable FilterQL, duplicate config) | Fix the request; show the message |
| 401 | Token missing or invalid | Tell the user to check `LYTICS_API_TOKEN` (see `auth.md`) |
| 403 | Token lacks the permission | Name the operation that was refused; don't retry |
| 404 | Not found, or belongs to another account | Check the id and the table |
| 429 | Rate limited | Wait briefly, retry once |
| 5xx | Server error | Retry once with backoff, then report it with the `request_id` |

Never retry a write blindly: a timed-out create may have succeeded. Read back before re-sending.
