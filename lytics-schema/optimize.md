# Optimize

Use to analyze schema quality and suggest improvements: unused and inert fields, coverage, identity, merge operations, PII exposure, capacity. Read-only; any fix it recommends is carried out in `manage.md`, through the confirmation gate.

Inputs: table (default `user`); optional focus `unused-fields`, `coverage`, `identity`, `merge-ops`, `mappings`, `pii`, or `all`. Run every check (or the one in focus), then present one report.

## Gather (in parallel)

| Call | Used for |
|---|---|
| `GET /v2/schema/{table}/field` | Fields with metadata |
| `GET /v2/schema/{table}/mapping` | Mappings |
| `GET /v2/segment?table={table}` | Segments, to find field references in `segment_ql` |
| `GET /api/schema/{table}/fieldinfo` | Coverage: presence/absence counts (`ents_present`), cardinality |
| `GET /v2/schema/{table}/rank` | Identity ranks |
| `GET /v2/schema/{table}/idconfig` | Identity config |

- More than 500 fields: batch the fieldinfo requests and warn the user it may take a moment.
- No segments: skip usage analysis and say so.
- fieldinfo fails: continue with metadata only and skip the coverage and capacity checks.

## Checks

1. **Unused fields**. Parse `segment_ql` from every segment for referenced field names and compare with all fields. Flag fields that are (a) in no segment AND have zero or very low `ents_present`, or (b) in no segment but do have data: those may be useful for future segments, so review before removing.
2. **Inert fields (no mappings)**. Fields no mapping targets will never receive data from any stream. Exclude system-managed fields (`ManagedBy` = "lytics" or similar).
3. **Coverage**. Low-coverage fields that segments use limit those segments to at most that share of profiles (e.g. `phone` -- 12% coverage, used in 2 segments).
4. **Identity resolution**. Is at least one field an identifier (needed for profile resolution)? Is the rank order sensible (higher priority = more stable identifier)? How many identity fields relative to total? Report each with rank and coverage, e.g. `email` rank 1, 92%: good primary; `user_id` rank 3, 45%: only useful for profiles from sources that provide it. IDConfig (compaction settings) is optional and most accounts don't need it; mention it only if the user asks about identity compaction.
5. **Merge operations**. Flag ops that don't fit the type or usage:

   | Field type | Typical mergeop | Issue if wrong |
   |---|---|---|
   | `string` (name, email) | `latest` | `sum`/`count` are nonsensical |
   | `int` (visit count) | `sum` or `count` | `latest` loses accumulation |
   | `number` (score) | `latest` or `max` | `sum` may cause unbounded growth |
   | `[]string` (tags, categories) | `merge` | `latest` loses history |
   | `date` (last_visit) | `latest` or `max` | `min` freezes at the first value |
   | `map[string]int` (action counts) | `merge` or `mapmax` | `latest` loses data |

6. **PII exposure**. PII fields referenced in segment FilterQL. `EXISTS email` is generally safe (no value exposure); a literal value match such as `phone CONTAINS "+1"` gets a WARNING.
7. **Capacity and retention**. For set and map fields: capacity far below actual cardinality means values are being dropped (increase capacity or review whether all values are needed); capacity `0` means no limit and unbounded growth (set one).

## Report

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

Before changing a `mergeop` on the user's say-so, remember a field update is a full replace and identifiers must not carry a `mergeop` (see `manage.md`).
