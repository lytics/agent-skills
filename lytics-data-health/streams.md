# Streams

Use to inspect the data streams flowing into Lytics: list them, view their stats and fields, and browse recent events. Useful for debugging data collection, verifying integrations, and understanding incoming data shape. All read-only; run immediately.

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/${STREAM_NAME}/events" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

URL-encode the stream name (`references/api.md`). The other calls use the same form.

## Endpoints

| Purpose | Call |
|---|---|
| List streams | `GET /v2/stream` |
| Stream names only | `GET /v2/stream/names` |
| Stream fields | `GET /v2/stream/fields` |
| One stream | `GET /v2/stream/{stream}` |
| Stream statistics | `GET /v2/stream/{stream}/stats` |
| Recent events | `GET /v2/stream/{stream}/events` |

## What to show

- **List**: a summary table -- stream name, event count, last event time, field count.
- **Stats**: total events; events per second/minute/hour; error rate, processing latency; active/inactive status.
- **Recent events**: timestamp, key fields, event type; highlight errors or anomalies. If events are complex, show a summary and offer to drill into specific events.

## Common questions

| Question | Do |
|---|---|
| "What data is flowing in?" | List streams + stats |
| "Is my integration working?" | Check stream stats for recent events |
| "What does the data look like?" | Browse recent events |
| "Why aren't profiles updating?" | Check the stream for errors |

## When it comes back empty

- Stream not found: list the available streams.
- No events: check whether the integration is active and suggest checking job status (health-check mode, or the `lytics-integrations` skill).
