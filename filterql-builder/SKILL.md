---
name: filterql-builder
description: Translate structured conditions into valid FilterQL expressions. Use when the user wants to write, build, or validate a FilterQL query or filter expression.
metadata:
  arguments: structured description of filter conditions
---

# FilterQL Builder

## Purpose
Translate structured conditions into valid FilterQL syntax. Takes field/operator/value tuples with AND/OR grouping and produces a syntactically correct FilterQL string.

## Environment
- None required (pure construction, no API calls)

## Inputs
- Conditions: list of (field, operator, value) tuples
- Grouping: AND/OR/NOT composition
- Table: target table (default: `user`)
- Alias: segment slug name

## Behavior

### Step 1: Map Each Condition to FilterQL Syntax

For each condition, use the type-operator compatibility matrix from `../references/field-types.md`:

| Field Type | Natural Language | FilterQL |
|-----------|-----------------|----------|
| `string` | equals "X" | `field = "X"` |
| `string` | not "X" | `field != "X"` |
| `string` | contains "X" | `field CONTAINS "X"` |
| `string` | like pattern | `field LIKE "pattern*"` |
| `string` | one of A,B,C | `field IN ("A", "B", "C")` |
| `bool` | is true | `field = true` |
| `bool` | is false | `field = false` |
| `int`/`number` | more than N | `field > N` |
| `int`/`number` | at least N | `field >= N` |
| `int`/`number` | less than N | `field < N` |
| `date` | after N days ago | `field > "now-Nd"` |
| `date` | before N days ago | `field < "now-Nd"` |
| `date` | within last N hours | `field > "now-Nh"` |
| `[]string` (set) | has "X" | `field INTERSECTS ("X")` |
| `[]string` (set) | doesn't have "X" | `field NOT INTERSECTS ("X")` |
| any | has any value | `EXISTS field` |
| any | is empty | `NOT EXISTS field` |

### Step 2: Compose Conditions

Wrap conditions in AND/OR/NOT:
```
FILTER AND (
  condition1,
  condition2,
  OR (condition3, condition4)
) FROM table ALIAS slug_name
```

Rules:
- Single condition: `FILTER condition FROM table ALIAS slug`
- Multiple conditions default to AND
- NOT can wrap any single condition or group
- Parentheses required for AND/OR groups
- Comma-separate conditions within groups

### Step 3: Generate Slug Name

Convert the alias to a valid slug:
- Lowercase
- Replace spaces with underscores
- Remove special characters
- Keep it descriptive but concise

### Step 4: Output

Return the complete FilterQL string:
```
FILTER AND (country = "US", visitct > 5) FROM user ALIAS us_active_visitors
```

## Date Math Reference

| Period | Syntax | Example |
|--------|--------|---------|
| Hours | `"now-Nh"` | `"now-24h"` = 1 day ago |
| Days | `"now-Nd"` | `"now-30d"` = 30 days ago |
| Weeks | `"now-Nw"` | `"now-4w"` = 4 weeks ago |
| Months | `"now-NM"` | `"now-6M"` = 6 months ago |
| Years | `"now-Ny"` | `"now-1y"` = 1 year ago |

Common conversions:
- 1 year = `"now-1y"` or `"now-8760h"` or `"now-365d"`
- 90 days = `"now-90d"` or `"now-2160h"`
- 1 week = `"now-1w"` or `"now-7d"` or `"now-168h"`

## Error Handling
- If a field type is incompatible with the requested operator, suggest the correct operator
- If values contain quotes, escape them
- If the FilterQL is syntactically invalid, identify and fix the issue

## Dependencies
- References: `../references/filterql-grammar.md`, `../references/field-types.md`
