---
name: api-response-format
description: Standard Lytics API response envelope and error format documentation
type: reference
---

# API Response Format

## Standard Response Envelope

All Lytics API responses follow this structure:

```json
{
  "data": <response_data>,
  "status": 200,
  "message": "optional status message",
  "request_id": "unique-request-id"
}
```

## Success Responses

### Single Object
```json
{
  "data": { "id": "abc123", "name": "My Segment", ... },
  "status": 200
}
```

### List of Objects
```json
{
  "data": [
    { "id": "abc123", "name": "Segment 1", ... },
    { "id": "def456", "name": "Segment 2", ... }
  ],
  "status": 200
}
```

### Empty/No Content
```json
{
  "data": null,
  "status": 200,
  "message": "deleted"
}
```

## Error Responses

```json
{
  "status": 4xx or 5xx,
  "message": "Human-readable error message",
  "request_id": "unique-request-id"
}
```

### Common Status Codes

| Code | Meaning | Common Causes |
|------|---------|---------------|
| 400 | Bad Request | Invalid payload, malformed FilterQL, missing required fields |
| 401 | Unauthorized | Invalid or missing API token |
| 403 | Forbidden | Token lacks permission for this operation |
| 404 | Not Found | Resource does not exist or belongs to different account |
| 409 | Conflict | Resource with same slug/name already exists |
| 422 | Unprocessable | Validation failed (e.g., invalid segment_ql) |
| 429 | Rate Limited | Too many requests |
| 500 | Server Error | Internal error, retry with backoff |

## Pagination

List endpoints support pagination via query parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `limit` | Max results per page | varies |
| `start` | Offset cursor | 0 |

## Filtering

List endpoints often support query parameters for filtering:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `table` | Filter by table | `?table=user` |
| `kind` | Filter by kind | `?kind=segment` |
| `valid` | Filter by validity | `?valid=true` |
| `sizes` | Include size data | `?sizes=true` |
