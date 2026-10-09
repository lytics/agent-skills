# Manage

Segment lifecycle: list, get, ancestors, create, update, delete, validate, size, reevaluate. Reads run immediately; create, update, delete, and reevaluate go through `references/confirmation-gate.md`.

## Reads

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&kind=segment&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Operation | Request | Notes |
|---|---|---|
| List | `GET /v2/segment` | Params: `table`, `kind`, `valid`, `sizes` |
| Get | `GET /v2/segment/${ID}?sizes=true&inline=true` | `sizes` adds size data; `inline` inlines included segments |
| Ancestors | `GET /v2/segment/${ID}/ancestors` | |
| Size of a saved segment | `GET /api/segment/${ID}/size` | |
| Size of ad-hoc FilterQL | `POST /api/segment/size` | Raw FilterQL body, `text/plain`, not JSON |
| Validate FilterQL | `POST /api/segment/validate` | Raw FilterQL body, `text/plain`; 200 = valid, otherwise the error message says why |
| Field breakdown | `GET /api/segment/${ID}/fieldinfo?limit=20&table=user` | `id` hash only (slug = 500); params `fields`, `limit` (default 20, max 1000), `table`, `cached`. See `snapshot.md` |

```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/validate" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: text/plain" \
  --data-binary 'FILTER AND (country = "US", visitct > 5) FROM user ALIAS test'
```

## Before any create or update

1. Validate the FilterQL; if invalid, fix from the error message (max 3 retries).
2. Size it. Size 0: warn and suggest broadening. Very large: state the size and confirm intent.
3. Show validation and size in the confirmation-gate summary.

## Create

`POST /v2/segment`:
```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: application/json" \
  --data-binary @segment.json
```
Required:
```json
{
  "name": "Display Name",
  "slug_name": "url_friendly_slug",
  "description": "Human-readable description",
  "segment_ql": "FILTER ... FROM user ALIAS url_friendly_slug",
  "kind": "segment",
  "table": "user",
  "is_public": true,
  "save_hist": true
}
```
Optional: `"tags": ["tag1"]`, `"groups": ["group_id"]`, `"expires_at": "2025-12-31T00:00:00Z"`, `"emit_trigger": false`, `"schedule_exit": false`.

**Slug conflict**: there is no 409 on create. A taken slug is silently renamed to `<slug>_1`, `<slug>_2`, ... and the call still succeeds. Always report `.data.slug_name` and `.data.id` from the response, never the slug you sent. (On update, a taken slug is a 400 `Slug is already used.`)

## Update

An update can silently create a *different* segment or rename this one:
- If `segment_ql` omits `FROM`, the table resets to `user`. For a non-user segment the update then misses the original and **creates a new segment**, and the call still succeeds.
- If the `ALIAS` differs from the current slug and no `slug_name` is sent, the slug is renamed, which breaks every other segment that does `INCLUDE <old_slug>`.

So GET the segment first, keep its `FROM <table>` and `ALIAS <slug>` in the new `segment_ql`, and after the PUT check that the returned `.data.id` equals `${SEGMENT_ID}`. If it doesn't, stop and tell the user a new segment was created.
```bash
curl -sS -w '\n%{http_code}\n' -X PUT "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment/${SEGMENT_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: application/json" \
  --data-binary @segment.json
```

## Delete

`DELETE /v2/segment/${SEGMENT_ID}`. Irreversible: say so at the gate.

## Reevaluate

`POST /v2/segment/reevaluate` with JSON body `{"id": "segment_id"}`.

## Segment kinds

| Kind | Description | Use case |
|---|---|---|
| `segment` | Standard audience segment | General audience targeting |
| `aspect` | Building block segment | Reusable filter components |
| `goal` | Business objective | Conversion tracking |
| `list` | Temporal export list | One-time or recurring exports |
| `conversion` | Campaign tracking | Attribution measurement |
| `metric` | Metric segment | Analytics/reporting |
| `managed` | System-managed | Internal platform use |
| `candidate` | Decisioning exclusion | Exclude from decisioning |
