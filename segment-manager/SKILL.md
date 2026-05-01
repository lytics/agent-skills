---
name: segment-manager
description: Segment CRUD, validation, and sizing operations. Use when the user wants to list, view, create, update, delete, validate, or size segments.
metadata:
  arguments: action and relevant parameters -- list, get, create, update, delete, validate, size, snapshot
---

# Segment Manager

## Purpose
Full segment lifecycle management -- list, get, create, update, delete, validate FilterQL, and estimate segment size.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## API Endpoints

### List Segments
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&kind=segment&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Query params: `table`, `kind`, `valid`, `sizes`

### Get Segment
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment/${SEGMENT_ID}?sizes=true&inline=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Query params: `sizes` (include size data), `inline` (inline included segments)

### Get Segment Ancestors
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment/${SEGMENT_ID}/ancestors" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Create Segment
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Segment Name",
    "slug_name": "segment_slug",
    "description": "What this segment represents",
    "segment_ql": "FILTER condition FROM user ALIAS segment_slug",
    "kind": "segment",
    "table": "user",
    "is_public": true,
    "tags": [],
    "save_hist": true
  }'
```

### Update Segment
```bash
curl -s -X PUT "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment/${SEGMENT_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... updated fields ... }'
```

### Delete Segment
```bash
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment/${SEGMENT_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Validate FilterQL
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/validate" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d 'FILTER AND (country = "US", visitct > 5) FROM user ALIAS test'
```
Returns 200 on valid, error message on invalid.

### Estimate Segment Size (ad-hoc FilterQL)
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/size" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d 'FILTER condition FROM user'
```
Body is raw FilterQL text, not JSON.

### Get Existing Segment Size
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${SEGMENT_ID}/size" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Segment Field Info -- Audience Snapshot
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${SEGMENT_ID}/fieldinfo?limit=20&table=user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Returns per-field analytics within a segment: value distributions, coverage rates, numeric stats, and histograms.
Query params: `fields` (comma-delimited), `limit` (default 20, max 1000), `table`, `cached`.
For detailed analysis, use the `audience-snapshot skill`.

### Reevaluate Segment
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment/reevaluate" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"id": "segment_id"}'
```

## Segment Payload

Required fields for creation:
```json
{
  "name": "Display Name",
  "slug_name": "url_friendly_slug",
  "description": "Human-readable description",
  "segment_ql": "FILTER ... FROM user ALIAS slug",
  "kind": "segment",
  "table": "user",
  "is_public": true,
  "save_hist": true
}
```

Optional fields:
```json
{
  "tags": ["tag1", "tag2"],
  "groups": ["group_id"],
  "expires_at": "2025-12-31T00:00:00Z",
  "emit_trigger": false,
  "schedule_exit": false
}
```

## Segment Kinds

| Kind | Description | Use Case |
|------|-------------|----------|
| `segment` | Standard audience segment | General audience targeting |
| `aspect` | Building block segment | Reusable filter components |
| `goal` | Business objective | Conversion tracking |
| `list` | Temporal export list | One-time or recurring exports |
| `conversion` | Campaign tracking | Attribution measurement |
| `metric` | Metric segment | Analytics/reporting |
| `managed` | System-managed | Internal platform use |
| `candidate` | Decisioning exclusion | Exclude from decisioning |

## Behavior

### For Read Operations (list, get, size)
Execute immediately and display results.

### For Write Operations (create, update, delete)
Use the confirmation-gate pattern:
1. Build complete payload
2. Show human-readable summary
3. Show raw API payload
4. Wait for user confirmation
5. Execute on approval

### Validation Flow
Before creating/updating a segment:
1. Validate the FilterQL with `POST /api/segment/validate`
2. If invalid, parse error and attempt to fix (max 3 retries)
3. Once valid, estimate size with `POST /api/segment/size`
4. Present validation + size results before proceeding

## Error Handling
- **Invalid FilterQL**: Parse the validation error, identify the issue, suggest fix
- **Slug conflict (409)**: Suggest alternative slug name
- **Empty segment (size 0)**: Warn user, suggest broadening criteria
- **Very large segment**: Note the size and ask user to confirm intent

## Dependencies
- Uses: `../references/auth.md`, `../references/api-client.md`, `../references/confirmation-gate.md`
- References: `../references/filterql-grammar.md`
