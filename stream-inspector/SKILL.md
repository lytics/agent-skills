---
name: stream-inspector
description: Inspect data streams, view stats, and browse recent events. Use when the user wants to list streams, view stream statistics, or browse recent stream events.
metadata:
  arguments: action and optional stream name -- list, get, stats, events
---

# Stream Inspector

## Purpose
Inspect data streams flowing into Lytics -- list available streams, view their statistics, and browse recent events. Useful for debugging data collection, verifying integrations, and understanding incoming data shape.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## API Endpoints

### List Streams
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Get Stream Names
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/names" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Get Stream Fields
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/fields" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Get Specific Stream
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/${STREAM_NAME}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Stream Statistics
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/${STREAM_NAME}/stats" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Recent Events
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/${STREAM_NAME}/events" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

## Behavior

All operations are read-only -- execute immediately.

### List Streams
Show a summary table of all streams:
- Stream name, event count, last event time, field count

### Stream Stats
Display key metrics:
- Total events, events per second/minute/hour
- Error rate, processing latency
- Active/inactive status

### Recent Events
Show the most recent events with:
- Timestamp, key fields, event type
- Highlight any errors or anomalies
- If events are complex, show a summary and offer to drill into specific events

## Use Cases
- "What data is flowing in?" -> List streams + stats
- "Is my integration working?" -> Check stream stats for recent events
- "What does the data look like?" -> Browse recent events
- "Why aren't profiles updating?" -> Check stream for errors

## Error Handling
- **Stream not found**: List available streams
- **No events**: Check if the integration is active, suggest checking job status

## Dependencies
- Uses: `../references/api-client.md`
