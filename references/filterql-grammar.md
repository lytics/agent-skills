---
name: filterql-grammar
description: Complete FilterQL syntax reference for building segment filter expressions
type: reference
---

# FilterQL Grammar Reference

## Full Syntax

```
FILTER <condition> [FROM <table>] [ALIAS <segment_name>]
```

- `FROM` defaults to `user` if omitted
- `ALIAS` assigns a slug name to the segment

## Operators

### Comparison
| Operator | Syntax | Types |
|----------|--------|-------|
| `=` or `==` | `field = "value"` | string, number, bool |
| `!=` | `field != "value"` | string, number, bool |
| `>` | `field > value` | number, date |
| `>=` | `field >= value` | number, date |
| `<` | `field < value` | number, date |
| `<=` | `field <= value` | number, date |

### String
| Operator | Syntax | Description |
|----------|--------|-------------|
| `CONTAINS` | `field CONTAINS "substr"` | Substring match |
| `NOT CONTAINS` | `field NOT CONTAINS "substr"` | No substring match |
| `LIKE` | `field LIKE "pattern"` | Wildcard match (`*` = any) |
| `NOT LIKE` | `field NOT LIKE "pattern"` | No wildcard match |

### Set / Array
| Operator | Syntax | Description |
|----------|--------|-------------|
| `IN` | `field IN ("a", "b")` | Value in list |
| `NOT IN` | `field NOT IN ("a", "b")` | Value not in list |
| `INTERSECTS` | `field INTERSECTS ("a", "b")` | Set intersection |
| `NOT INTERSECTS` | `field NOT INTERSECTS ("a")` | No set intersection |

### Existence
| Operator | Syntax | Description |
|----------|--------|-------------|
| `EXISTS` | `EXISTS field` | Field has a value |
| `NOT EXISTS` | `NOT EXISTS field` | Field is empty/missing |

### Special
| Operator | Syntax | Description |
|----------|--------|-------------|
| `*` | `FILTER *` | Match all records |
| `match_all` | `FILTER match_all` | Match all (alternative) |
| `INCLUDE` | `INCLUDE segment_slug` | Include another segment |
| `NOT INCLUDE` | `NOT INCLUDE segment_slug` | Exclude another segment |

## Boolean Composition

```
FILTER AND (condition1, condition2, ...)
FILTER OR (condition1, condition2, ...)
FILTER NOT condition
FILTER NOT AND (condition1, condition2)
FILTER NOT OR (condition1, condition2)
```

Conditions can be nested:
```
FILTER AND (
  field1 = "value",
  OR (field2 > 5, field3 < 10),
  NOT field4 CONTAINS "x"
)
```

## Date / Time Syntax

### Relative Time (from now)
| Unit | Syntax | Example |
|------|--------|---------|
| Hours | `"now-Nh"` | `"now-24h"` (1 day ago) |
| Days | `"now-Nd"` | `"now-30d"` (30 days ago) |
| Weeks | `"now-Nw"` | `"now-4w"` (4 weeks ago) |
| Months | `"now-NM"` | `"now-3M"` (3 months ago) |
| Years | `"now-Ny"` | `"now-1y"` (1 year ago) |

### Absolute Time
- Unix timestamp (milliseconds): `field > 1393468620175`
- ISO 8601: `field > "2016-04-02T12:00:00Z"`

## Map / Nested Field Access

Dot notation for nested fields:
```
FILTER attributes.cityname = "Portland"
FILTER scores.recency > 10
FILTER flags.web_unsubscribe = false
```

Backticks for keys with special characters:
```
FILTER `actioncounts.Web hit` == 10
FILTER `oldestevents`.`has.period` < "2015-05-04T12:00:00Z"
```

## Special Functions

### Geodistance
```
FILTER geodistance(geo_field, "lat,lon", radius_km)
```
Example: `FILTER geodistance(geolocation, "-30.5,-179.5", 80.5)`

### Time Window
```
FILTER timewindow(field, count, days)
```
Example: `FILTER timewindow(visits, 5, 7)` (5+ visits in last 7 days)

## Examples

Simple equality:
```
FILTER country = "US" FROM user ALIAS us_users
```

Compound with date math:
```
FILTER AND (
  country = "US",
  last_purchase > "now-30d"
) FROM user ALIAS recent_us_buyers
```

Set operations:
```
FILTER AND (
  NOT newsletters INTERSECTS ("Globe Newsletter"),
  domains INTERSECTS ("horizons.globeturnoutgear.com", "globecares.com")
)
```

Nested segment reference:
```
FILTER AND (INCLUDE child_segment_1, INCLUDE child_segment_2) ALIAS combined
```

Complex real-world:
```
FILTER AND (
  aboutme_handle LIKE "rsessel",
  app_yymm.`1602` IN ("2", "1", "6"),
  lytics_content.`Text (literary theory)` >= "0.42",
  AND (
    ly_impressions.`8984a0d225a3c9ad3b87e71cc76b9b93` > "0",
    NOT ly_conversions.`8984a0d225a3c9ad3b87e71cc76b9b93` > "0"
  )
)
```

## Formal Grammar (BNF)

```
Segment    = Expr
Expr       = {"op": Op, "args": Args}
Op         = "and" | "or" | "not" | ">" | ">=" | "<" | "<=" | "=" | "!="
             | "between" | "contains" | "exists" | "in" | "intersects"
             | "include" | "like" | "*"
Args       = [ Node, Node, ... ]
Node       = Expr | Literal | Identifier | SegmentRef
Literal    = {"val":   "..."}
Identifier = {"ident": "..."}
SegmentRef = {"seg":   "..."}
```
