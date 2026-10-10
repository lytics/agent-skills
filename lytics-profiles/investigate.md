# Investigate

Use to diagnose why a user is or isn't in a segment, or to trace where a profile's data came from.

Inputs: an identity field and value, plus a segment name or ID for membership questions. FilterQL syntax: `references/filterql-grammar.md`.

## Flow A: Why is/isn't this user in segment X?

### 1. Fetch the profile with memberships

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/$(jq -rn --arg v "$VALUE" '$v|@uri')?segments=true&allsegments=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Returns all profile fields, `segments` (segment names the user belongs to) and `segments_all` (all segment IDs). Check immediately whether the target segment is in the list. A 200 with `message: "Not Found"` and `{"segments": ["not_found", "all"]}` is a missing profile (see `lookup.md`).

### 2. Fetch the segment's resolved FilterQL

`GET /v2/segment/{segment_id}?inline=true` -- `ql_resolved` holds the complete filter with every INCLUDE inlined. If the segment is not found, list segments with similar names and suggest checking the slug.

### 3. Evaluate each condition against the profile

```
## Why user@example.com is NOT in "High Value Customers"

FilterQL: FILTER AND (visit_count >= 5, email_engagement > 0.3, country = "US") FROM user

  visit_count >= 5        PASS  (actual: 12)
  email_engagement > 0.3  FAIL  (actual: 0.15, required: > 0.3)
  country = "US"          PASS  (actual: "US")

The user fails email_engagement: 0.15 is below the 0.3 threshold.
```

For a member, the same table with every condition PASS. For each condition always show: the condition, PASS/FAIL, the actual profile value (or "field not present"), and for FAIL what value would pass.

### 4. Check included segments

If the FilterQL INCLUDEs other segments, report each membership as its own row:

```
  INCLUDE Email Subscribers   PASS  (member)
  visit_count >= 5            PASS  (actual: 12)
  last_purchase > "now-90d"   FAIL  (actual: 2025-01-15, outside the 90d window)
```

For deeply nested expressions, evaluate the top-level conditions first, then drill into failing branches. A referenced field missing from the profile is often the root cause; report it clearly.

### Condition evaluation

| FilterQL condition | How to check |
|---|---|
| `field = "value"` | Compare the profile value to the literal |
| `field > N` | Numeric comparison |
| `field > "now-Nd"` | Compare the date field to the calculated threshold |
| `EXISTS field` | Field exists and is non-empty |
| `NOT EXISTS field` | Field is missing or empty |
| `field INTERSECTS ("a", "b")` | Set field contains any listed value |
| `field NOT INTERSECTS ("a")` | Set field contains none of the listed values |
| `field CONTAINS "substr"` | String field contains the substring |
| `field IN ("a", "b")` | Profile value is in the list |
| `INCLUDE segment_slug` | User is a member of the referenced segment |

## Flow B: What happened to this user? (data lineage)

`GET /api/entity/user/{field}/{value}?explain=true` returns:
- `entity` -- the resolved profile
- `fragments` -- data fragments showing where each piece of data came from
- `keys` -- source references (fragment aliases)

Present it as:

```
## Data Lineage: user@example.com

### Identity Resolution
  email: user@example.com
  _uid: abc-def-123
  user_id: 98765

### Data Sources (N fragments)
Fragment 1: stream "web_events" (last seen: 2026-03-18)
  -> visit_count, pages_viewed, last_visit, referrer
Fragment 2: stream "salesforce_contacts" (last seen: 2026-03-15)
  -> first_name, last_name, company, phone
```
