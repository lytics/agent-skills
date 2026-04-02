---
name: api-client
description: Shared HTTP calling conventions, auth, and response parsing for Lytics API
---

# API Client Conventions

## Purpose
Defines shared HTTP conventions for all skills that call the Lytics REST API. This skill is referenced (not invoked) by other skills.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token (required)
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Authentication

All requests include the authorization header:
```
Authorization: $LYTICS_API_TOKEN
```

## Making Requests

Use `curl` via the Bash tool for all API calls:

```bash
curl -s -X GET "${LYTICS_API_URL:-https://api.lytics.io}/v2/endpoint" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json"
```

For POST/PUT with body:
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/endpoint" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'
```

## Response Parsing

All responses use the standard envelope (see `reference/api-response-format.md`):
```json
{"data": ..., "status": N, "message": "..."}
```

Parse with `jq`:
- Extract data: `| jq '.data'`
- Check status: `| jq '.status'`
- Get error: `| jq '.message'`

## Error Handling

1. Check HTTP status code -- anything >= 400 is an error
2. Extract `.message` from response body for human-readable error
3. For 401: token is invalid or missing -- ask user to check `LYTICS_API_TOKEN`
4. For 429: rate limited -- wait briefly and retry once
5. For 500: server error -- retry once with backoff, then report to user

## URL Construction

Always use the environment variable with a default:
```
${LYTICS_API_URL:-https://api.lytics.io}
```

Common base paths:
- V2 API: `/v2/...`
- Data API: `/api/...`
