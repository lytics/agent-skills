---
name: field-types
description: Schema field data types, operator compatibility matrix, and merge operations
type: reference
---

# Field Types & Operator Compatibility

## Scalar Types

| Type | Description | Compatible Operators |
|------|-------------|---------------------|
| `string` | Text data | `=`, `!=`, `CONTAINS`, `NOT CONTAINS`, `LIKE`, `NOT LIKE`, `IN`, `NOT IN`, `EXISTS`, `NOT EXISTS` |
| `bool` | Boolean | `=`, `!=`, `EXISTS`, `NOT EXISTS` |
| `int` | Integer | `=`, `!=`, `>`, `>=`, `<`, `<=`, `EXISTS`, `NOT EXISTS` |
| `number` / `float` | Floating point | `=`, `!=`, `>`, `>=`, `<`, `<=`, `EXISTS`, `NOT EXISTS` |
| `date` / `time` / `datetime` | Temporal | `>`, `>=`, `<`, `<=`, `EXISTS`, `NOT EXISTS` (use date math: `"now-Nh"`) |

## Complex Types

| Type | Description | Compatible Operators |
|------|-------------|---------------------|
| `[]string` | String array (set) | `INTERSECTS`, `NOT INTERSECTS`, `IN`, `NOT IN`, `EXISTS`, `NOT EXISTS` |
| `[]time` | Time array | `>`, `<`, `EXISTS`, `NOT EXISTS` |
| `ts[]string` | Time-ordered string array | `INTERSECTS`, `NOT INTERSECTS`, `EXISTS`, `NOT EXISTS` |
| `map[string]int` | String-to-integer map | Access via dot notation: `field.key > 5`, `EXISTS` |
| `map[string]number` | String-to-number map | Access via dot notation: `field.key >= 0.5`, `EXISTS` |
| `map[string]string` | String-to-string map | Access via dot notation: `field.key = "val"`, `EXISTS` |
| `map[string]bool` | String-to-boolean map | Access via dot notation: `field.key = true`, `EXISTS` |
| `map[string]time` | String-to-time map | Access via dot notation: `field.key > "now-24h"`, `EXISTS` |
| `map[string]value` | Generic value map | Access via dot notation, `EXISTS` |

## Special Types

| Type | Description | Compatible Operators |
|------|-------------|---------------------|
| `membership` | Segment membership | Internal use |
| `geolocation` | Geographic coordinates | `geodistance()` function |
| `embedding` | Vector embedding | Internal use |
| `dynamic` | Dynamic type | Depends on runtime value |
| `flows` | Flow data | Internal use |
| `[]timebucket` | Time bucket array | `timewindow()` function |

## Operator-to-Type Quick Reference

Use this when translating natural language to FilterQL:

| Natural Language | Field Type | FilterQL Pattern |
|-----------------|------------|-----------------|
| "is/equals/matches" | `string` | `field = "value"` |
| "is not" | `string` | `field != "value"` |
| "contains/includes (substring)" | `string` | `field CONTAINS "substr"` |
| "starts with/ends with" | `string` | `field LIKE "prefix*"` / `field LIKE "*suffix"` |
| "is true/false" | `bool` | `field = true` / `field = false` |
| "greater than/more than" | `int`, `number` | `field > value` |
| "less than/fewer than" | `int`, `number` | `field < value` |
| "at least/minimum" | `int`, `number` | `field >= value` |
| "at most/maximum" | `int`, `number` | `field <= value` |
| "after/since (date)" | `date` | `field > "now-Nd"` or `field > "ISO-date"` |
| "before (date)" | `date` | `field < "now-Nd"` or `field < "ISO-date"` |
| "within last N days" | `date` | `field > "now-Nd"` |
| "has/have (set membership)" | `[]string` | `field INTERSECTS ("value")` |
| "does not have" | `[]string` | `NOT field INTERSECTS ("value")` or `field NOT INTERSECTS ("value")` |
| "is one of" | `string` | `field IN ("a", "b", "c")` |
| "is not one of" | `string` | `field NOT IN ("a", "b", "c")` |
| "has any value" | any | `EXISTS field` |
| "is empty/missing" | any | `NOT EXISTS field` |
| "near location" | `geolocation` | `geodistance(field, "lat,lon", radius_km)` |
| "N+ events in last M days" | `[]timebucket` | `timewindow(field, N, M)` |

## Merge Operations

Fields have merge operations that determine how values are combined during identity resolution:

| Operation | Description | Applicable Types |
|-----------|-------------|-----------------|
| `sum` | Sum values | `int`, `number` |
| `count` | Count occurrences | `int` |
| `max` | Keep maximum | `int`, `number`, `date` |
| `min` | Keep minimum | `int`, `number`, `date` |
| `latest` | Keep newest value | all scalar types |
| `oldest` | Keep first value | all scalar types |
| `merge` | Merge structures | sets, maps |
| `capped` | Limited merge | sets |
| `mapmax` | Max per map key | maps |
| `mapmin` | Min per map key | maps |
| `latestmap` | Latest per key | maps |
| `oldestmap` | Oldest per key | maps |
