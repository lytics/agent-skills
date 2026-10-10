# Snapshot

Read-only view of who is in a segment: field value distributions, coverage, numeric stats, and comparisons between segments.

Inputs: segment name or id (required); optional fields to analyze (default all) and table (default `user`).

## Step 1: Resolve the segment id

fieldinfo **requires the `id` hash** (e.g. `a1b2c3d4e5f6`); a slug returns HTTP 500. Find the segment by `name` or `slug_name` in `GET /v2/segment?table=user&sizes=true` and take its `id` and current size. Not found: list available segments and suggest checking the name.

## Step 2: Fetch fieldinfo

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${SEGMENT_ID}/fieldinfo?limit=20&table=user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Several segments at once: `GET /api/segment/fieldinfo?ids=${ID1},${ID2}&limit=20&table=user`.

| Param | Default | Max | Meaning |
|---|---|---|---|
| `fields` | all | - | Comma-delimited fields to return |
| `limit` | 20 | 1000 | Term values per field (raise to e.g. 100 for a deep dive) |
| `table` | user | - | Entity table |
| `cached` | true | - | `false` for fresh data |

Response (`/api` envelope; iterate with `jq '.data.segments[].fields[]'`):
```json
{"data": {"segments": [{"id": "segment_id", "fields": [
  {"field": "country", "terms_counts": {"US": 5000, "CA": 2000, "UK": 1500}, "more_terms": false,
   "ents_present": 8500, "ents_absent": 1500, "approx_cardinality": 45, "last_updated": "2026-03-18T12:00:00Z"},
  {"field": "visit_count", "terms_counts": null, "ents_present": 9800, "ents_absent": 200, "approx_cardinality": 350,
   "stats": {"mean": 12.5, "sd": 8.3, "min": 1.0, "max": 150.0, "n": 9800},
   "histograms": [{"data": {"0-10": 4500, "10-20": 3200, "20-50": 1800, "50+": 300}}],
   "last_updated": "2026-03-18T12:00:00Z"}]}]},
 "message": "success", "status": 200}
```

| Key | Meaning |
|---|---|
| `terms_counts` | Top values with counts (categorical) |
| `more_terms` | More values exist beyond `limit` |
| `ents_present` / `ents_absent` | Profiles with / without the field populated |
| `approx_cardinality` | Estimated distinct values |
| `stats` | Numeric only: mean, sd, min, max, n (else null) |
| `histograms` | Numeric/date: bucketed distribution (else null) |
| `last_updated` | When fieldinfo was computed; if old, refetch with `cached=false` |

No fieldinfo returned: the segment may be new or empty; check its size.

## Step 3: Present

```
## Audience Snapshot: High Value Customers
**Size**: 10,000 profiles

### Top Demographics
**country** (98% coverage, 45 distinct values)
  US: 5,000 (50%)  CA: 2,000 (20%)  UK: 1,500 (15%)  Other: ...

### Engagement Metrics
**visit_count** (98% coverage)
  Mean: 12.5 | Std Dev: 8.3 | Min: 1 | Max: 150
  Distribution: 0-10: 46%, 10-20: 33%, 20-50: 18%, 50+: 3%

### Field Coverage
| Field | Coverage | Distinct Values |
```

## Step 4: Highlight patterns

- Dominant values: "87% of this audience is from the US"
- Coverage: "Only 34% have a phone number"
- Numeric skew: "Visit count ranges from 1 to 150, but 79% have fewer than 20"
- With several segments, the key differences.

## Comparing segments

Fetch with `?ids=` and show side by side:
```
| Field | High Value | All Users |
| Avg visit_count | 12.5 | 4.2 |
| US % | 50% | 35% |
| Email coverage | 92% | 68% |
```

## Step 5: Offer next steps

Drill into one field with a higher `limit`, compare against another segment, or narrow the audience based on what was found (`advise.md` / `build.md`).
