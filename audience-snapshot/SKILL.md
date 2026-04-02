---
name: audience-snapshot
description: Analyze what an audience looks like -- demographic breakdowns, top field values, coverage rates, and distributions. Use when the user wants to understand audience composition, view segment demographics, or analyze field coverage for a segment.
metadata:
  arguments: segment name or ID, optionally specific fields to analyze
---

# Audience Snapshot

## Purpose
Provides an analytics view of an audience segment -- what do the people in this segment look like? Shows field value distributions, coverage rates, numeric statistics, and highlights notable patterns. This is a read-only operation.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Inputs
- Segment name or ID (required)
- Specific fields to analyze (optional -- defaults to all fields)
- Table (optional -- defaults to `user`)

## API Endpoints

### Segment Field Info by ID
**Important**: This endpoint requires the segment's `id` hash (e.g., `a1b2c3d4e5f6`), NOT the slug name. Using a slug will return HTTP 500. Always resolve the segment ID first via `GET /v2/segment`.
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${SEGMENT_ID}/fieldinfo?limit=20&table=user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Segment Field Info for Multiple Segments
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/fieldinfo?ids=${ID1},${ID2}&limit=20&table=user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Query Parameters

| Parameter | Default | Max | Description |
|-----------|---------|-----|-------------|
| `fields` | all | - | Comma-delimited list of specific fields to return |
| `limit` | 20 | 1000 | Number of term values per field |
| `table` | user | - | Entity table name |
| `cached` | true | - | Use cached results; set false for fresh data |

### Response Shape

Response uses the standard API envelope. The fieldinfo data is inside `data.segments`:

```json
{
  "data": {
    "segments": [
      {
        "id": "segment_id",
        "fields": [
          {
            "field": "country",
            "terms_counts": {"US": 5000, "CA": 2000, "UK": 1500},
            "more_terms": false,
            "ents_present": 8500,
            "ents_absent": 1500,
            "approx_cardinality": 45,
            "last_updated": "2026-03-18T12:00:00Z"
          },
          {
            "field": "visit_count",
            "terms_counts": null,
            "ents_present": 9800,
            "ents_absent": 200,
            "approx_cardinality": 350,
            "stats": {"mean": 12.5, "sd": 8.3, "min": 1.0, "max": 150.0, "n": 9800},
            "histograms": [{"data": {"0-10": 4500, "10-20": 3200, "20-50": 1800, "50+": 300}}],
            "last_updated": "2026-03-18T12:00:00Z"
          }
        ]
      }
    ]
  },
  "message": "success",
  "status": 200
}
```

Parse with `jq '.data.segments[].fields[]'` to iterate over fields.

**Per-field response keys:**

| Key | Type | Description |
|-----|------|-------------|
| `field` | string | Field name |
| `terms_counts` | object | Top values with counts (categorical fields) |
| `more_terms` | bool | Whether more values exist beyond the limit |
| `ents_present` | int | Profiles with this field populated |
| `ents_absent` | int | Profiles missing this field |
| `approx_cardinality` | int | Estimated distinct value count |
| `stats` | object or null | Numeric fields only: mean, sd, min, max, n |
| `histograms` | array or null | Numeric/date fields: bucketed distributions |
| `last_updated` | timestamp | When field info was last computed |

## Behavior

### Step 1: Resolve Segment ID
The fieldinfo endpoint **requires the segment's `id` hash** -- slug names will return HTTP 500. Always resolve first:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Find the matching segment by name or slug_name, extract its `id` field (hex hash) and current size.

### Step 2: Fetch Field Info
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${SEGMENT_ID}/fieldinfo?limit=20&table=user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
If the user specified particular fields, add `&fields=field1,field2,field3`.
For deeper analysis on specific fields, increase the limit: `&limit=100`.

### Step 3: Present Audience Snapshot

Organize the results into a readable summary:

```
## Audience Snapshot: High Value Customers
**Size**: 10,000 profiles

### Top Demographics
**country** (98% coverage, 45 distinct values)
  US: 5,000 (50%)
  CA: 2,000 (20%)
  UK: 1,500 (15%)
  DE: 800 (8%)
  Other: 700 (7%)

**city** (85% coverage, 1,200 distinct values)
  New York: 800 (8%)
  Toronto: 600 (6%)
  London: 500 (5%)
  ...

### Engagement Metrics
**visit_count** (98% coverage)
  Mean: 12.5 | Std Dev: 8.3
  Min: 1 | Max: 150
  Distribution: 0-10: 46%, 10-20: 33%, 20-50: 18%, 50+: 3%

### Field Coverage
| Field | Coverage | Distinct Values |
|-------|----------|----------------|
| email | 92% | 9,800 |
| country | 98% | 45 |
| city | 85% | 1,200 |
| visit_count | 98% | 350 |
| products_purchased | 67% | 890 |
```

### Step 4: Highlight Notable Patterns
Call out interesting findings:
- Dominant values: "87% of this audience is from the US"
- High/low coverage: "Only 34% have a phone number"
- Numeric outliers: "Visit count ranges from 1 to 150, but 79% have fewer than 20"
- Comparisons: If analyzing multiple segments, highlight key differences

### Step 5: Offer Follow-Up Actions
After presenting the snapshot, suggest next steps:
- "Would you like to drill into a specific field with more detail?"
- "Want to compare this audience against another segment?"
- "Should I narrow this audience further based on what we see?"

## Comparing Segments
When comparing two or more segments, fetch fieldinfo for each and present side-by-side:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/fieldinfo?ids=${ID1},${ID2}&limit=20" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Present differences:
```
### Comparison: High Value vs All Users
| Field | High Value | All Users |
|-------|-----------|-----------|
| Avg visit_count | 12.5 | 4.2 |
| US % | 50% | 35% |
| Email coverage | 92% | 68% |
```

## Error Handling
- **Segment not found**: List available segments, suggest checking the name
- **No field info available**: Segment may be too new or empty -- check segment size first
- **Stale data**: If `last_updated` is old, suggest refetching with `cached=false`

## Dependencies
- Uses: `../references/api-client.md`
- Related: `segment-manager skill` for segment lookup, `audience-builder skill` for creating segments
