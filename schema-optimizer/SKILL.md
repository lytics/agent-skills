---
name: schema-optimizer
description: Analyze schema field usage, coverage, mappings, and identity config to suggest improvements. Use when the user wants to optimize their schema, find unused fields, improve coverage, or review identity and merge configuration.
metadata:
  arguments: optional focus area -- unused-fields, coverage, identity, merge-ops, mappings, or all
---

# Schema Optimizer

## Purpose
Analyzes the schema for quality issues and suggests improvements. Identifies unused fields, misconfigured merge operations, missing mappings, identity resolution gaps, and PII exposure risks. Read-only analysis with actionable recommendations.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Inputs
- Table (default: `user`)
- Optional focus area: `unused-fields`, `coverage`, `identity`, `merge-ops`, `mappings`, `pii`, or `all`

## Analysis Flow

Run all checks (or a specific focus area), then present a unified report.

### Step 1: Gather Data

Fetch the three core datasets in parallel:

```bash
# All fields with metadata
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# All mappings
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/mapping" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# All segments (to find field references)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Step 2: Gather Field Coverage

```bash
# Field info with presence/absence counts
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/schema/user/fieldinfo" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Step 3: Gather Identity Config

```bash
# Identity resolution config and ranks
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/rank" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/idconfig" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

## Analysis Checks

### Check 1: Unused Fields

Cross-reference fields against segment FilterQL to find fields that exist in the schema but are never referenced in any segment.

1. Parse `segment_ql` from every segment to extract referenced field names
2. Compare against all schema fields
3. Flag fields that are:
   - Not referenced in any segment AND have zero or very low `ents_present`
   - Not referenced in any segment but DO have data (may be useful for future segments)

```
### Unused Fields (12 found)

Never referenced in segments AND empty:
  legacy_score        -- 0 profiles, created 2024-03-01, no mappings
  old_campaign_tag    -- 0 profiles, created 2024-06-15, 1 stale mapping

Never referenced but have data:
  browser_version     -- 45,000 profiles (31%), not in any segment
  referrer_domain     -- 89,000 profiles (61%), not in any segment
  (these may be useful -- review before removing)
```

### Check 2: Inert Fields (no mappings)

A field without a mapping will never receive data from any stream.

1. Get all fields, get all mappings
2. Find fields where no mapping targets that field name
3. Exclude system-managed fields (ManagedBy = "lytics" or similar)

```
### Inert Fields -- No Mappings (3 found)

  custom_score    -- type: number, created 2025-01-10, no mapping exists
  user_tier       -- type: string, created 2025-02-20, no mapping exists
  (these fields will never receive data until a mapping is added)
```

### Check 3: Field Coverage

Identify fields with very low coverage that are used in segments -- this limits audience reach.

```
### Low Coverage Fields Used in Segments

  phone           -- 12% coverage, used in 2 segments
  company_name    -- 8% coverage, used in 1 segment
  (segments using these fields are limited to at most N% of profiles)
```

### Check 4: Identity Resolution

Check identity field configuration:
- Are any fields marked as identifiers? (at least one is needed for profile resolution)
- Is the rank ordering sensible? (higher-priority fields should be more stable identifiers)
- How many identity fields exist relative to total fields?

```
### Identity Resolution

Identity fields: 3 configured
  1. email        -- rank 1, coverage: 92%
  2. _uid         -- rank 2, coverage: 100%
  3. user_id      -- rank 3, coverage: 45%

Observations:
  3 identity fields configured -- looks reasonable
  email is rank 1 with 92% coverage -- good primary identifier
  user_id has 45% coverage -- only useful for profiles from sources that provide it
```

Note: IDConfig (compaction settings) is optional and most accounts don't need it. Only mention it if the user specifically asks about identity compaction.

### Check 5: Merge Operation Review

Flag merge operations that may be misconfigured for the field's data type or usage pattern:

| Field Type | Typical MergeOp | Issue if Wrong |
|-----------|----------------|----------------|
| `string` (name, email) | `latest` | `sum`/`count` would be nonsensical |
| `int` (visit count) | `sum` or `count` | `latest` loses accumulation |
| `number` (score) | `latest` or `max` | `sum` may cause unbounded growth |
| `[]string` (tags, categories) | `merge` | `latest` loses history |
| `date` (last_visit) | `latest` or `max` | `min` would freeze at first value |
| `map[string]int` (action counts) | `merge` or `mapmax` | `latest` loses data |

```
### Merge Operation Review

Potential issues:
  visit_count (int, merge_op: latest)
    -> Recommendation: consider 'sum' or 'count' to accumulate visits

  tags ([]string, merge_op: latest)
    -> Recommendation: consider 'merge' to accumulate tag values

  engagement_score (number, merge_op: sum)
    -> Recommendation: consider 'latest' or 'max' -- summing scores causes unbounded growth
```

### Check 6: PII Exposure

Flag fields marked as PII that appear in segment FilterQL (potential data exposure through segment definitions).

```
### PII in Segments

  email (PII) -- referenced in 3 segments
    "Email Subscribers": EXISTS email
    (EXISTS checks are generally safe -- no value exposure)

  phone (PII) -- referenced in 1 segment
    "Phone Contacts": phone CONTAINS "+1"
    WARNING: FilterQL contains a literal value match on PII field
```

### Check 7: Capacity and Retention

For set and map fields, check if capacity is set and whether it's appropriate relative to actual cardinality.

```
### Capacity Review

  products_purchased ([]string, capacity: 100, actual cardinality: 2,340)
    -> WARNING: Cardinality far exceeds capacity. Values are being dropped.
    -> Recommendation: increase capacity or review if all values are needed

  action_counts (map[string]int, capacity: 0)
    -> WARNING: No capacity limit. Map will grow unbounded.
    -> Recommendation: set a capacity limit
```

## Output Format

```
## Schema Optimization Report (user table)

### Summary
- Total fields: 145
- Unused fields: 12 (8%)
- Inert fields (no mapping): 3
- Low-coverage fields in segments: 5
- Identity issues: 1
- Merge op concerns: 3
- PII exposure warnings: 1
- Capacity warnings: 2

### Priority Recommendations
1. HIGH: 3 fields have no mappings and will never receive data -- add mappings or remove fields
2. MEDIUM: visit_count uses 'latest' merge -- consider 'sum' to accumulate
3. MEDIUM: products_purchased capacity (100) exceeded by cardinality (2,340) -- values being dropped
4. LOW: 12 fields are unused -- review and archive if no longer needed

[Detailed findings per check follow...]
```

## Error Handling
- **Large schema**: If > 500 fields, batch fieldinfo requests. Warn the user this may take a moment.
- **No segments**: If no segments exist, skip the usage analysis and note it.
- **Fieldinfo unavailable**: If fieldinfo endpoint fails, proceed with metadata-only analysis (skip coverage and capacity checks).

## Dependencies
- Composes: `schema-manager skill`, `segment-manager skill`
- References: `../references/field-types.md`, `../references/api-client.md`
