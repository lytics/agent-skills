---
name: profile-investigator
description: Diagnose why a user is or isn't in a segment, and trace their data lineage. Use when the user wants to understand segment membership, debug why a profile qualifies or doesn't qualify, or trace data lineage.
metadata:
  arguments: identity and segment name, or diagnostic question
---

# Profile Investigator

## Purpose
Deep diagnostic profile exploration. Answers questions like:
- "Why is this user in segment X?"
- "Why isn't this user in segment Y?"
- "What happened to this user?" (data lineage)
- "What does this user look like?" (full profile + memberships)

Goes beyond basic profile lookup by cross-referencing profile data against segment FilterQL to show exactly which conditions match or fail.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## Inputs
- Identity field and value (e.g., `email`, `user@example.com`)
- Segment name or ID (for membership diagnosis)
- Or a diagnostic question in natural language

## Diagnostic Flows

### Flow A: "Why is/isn't this user in segment X?"

#### Step 1: Look Up the Profile

Fetch the full profile with segment memberships:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/${VALUE}?segments=true&allsegments=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

This returns:
- All profile fields and their values
- `segments` -- list of segment names the user belongs to
- `segments_all` -- list of all segment IDs

Check immediately: is the target segment in the membership list?

#### Step 2: Fetch the Segment's FilterQL

Get the segment with its fully resolved FilterQL (all INCLUDE directives inlined):
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment/${SEGMENT_ID}?inline=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

The `ql_resolved` field contains the complete filter expression with nested segments expanded.

#### Step 3: Evaluate Each Condition Against the Profile

Parse the FilterQL into individual conditions and check each one against the profile's actual field values.

For each condition in the FilterQL, report:

**If the user IS in the segment:**
```
## Why user@example.com IS in "High Value Customers"

FilterQL: FILTER AND (visit_count >= 5, email_engagement > 0.3, country = "US") FROM user

All conditions PASS:
  visit_count >= 5        PASS  (actual: 12)
  email_engagement > 0.3  PASS  (actual: 0.72)
  country = "US"          PASS  (actual: "US")
```

**If the user is NOT in the segment:**
```
## Why user@example.com is NOT in "High Value Customers"

FilterQL: FILTER AND (visit_count >= 5, email_engagement > 0.3, country = "US") FROM user

Condition results:
  visit_count >= 5        PASS  (actual: 12)
  email_engagement > 0.3  FAIL  (actual: 0.15, required: > 0.3)
  country = "US"          PASS  (actual: "US")

The user fails the email_engagement condition. Their value (0.15) is below
the threshold (0.3). This is the reason they are excluded from the segment.
```

#### Step 4: Check Included Segments

If the FilterQL references other segments via INCLUDE, check those memberships too:
```
Segment "High Value Customers" includes "Email Subscribers":
  Email Subscribers membership: YES

  Combined evaluation:
    INCLUDE Email Subscribers   PASS
    visit_count >= 5            PASS  (actual: 12)
    last_purchase > "now-90d"   FAIL  (actual: 2025-01-15, ~63 days ago -- outside 90d window)
```

### Flow B: "What happened to this user?" (Data Lineage)

#### Step 1: Fetch Entity with Explain Mode

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/${VALUE}?explain=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

This returns:
- `entity` -- the resolved profile
- `fragments` -- array of data fragments showing where each piece of data came from
- `keys` -- source references (fragment aliases)

#### Step 2: Present Data Lineage

```
## Data Lineage: user@example.com

### Identity Resolution
Linked identities:
  email: user@example.com
  _uid: abc-def-123
  user_id: 98765

### Data Sources (N fragments)
Fragment 1: stream "web_events" (last seen: 2026-03-18)
  -> visit_count, pages_viewed, last_visit, referrer

Fragment 2: stream "salesforce_contacts" (last seen: 2026-03-15)
  -> first_name, last_name, company, phone

Fragment 3: stream "email_events" (last seen: 2026-03-19)
  -> email_engagement, newsletters, last_email_open
```

### Flow C: Full Profile Summary

#### Step 1: Fetch Profile + Segments

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/${VALUE}?segments=true&allsegments=true&meta=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

#### Step 2: Present Structured Summary

```
## Profile: user@example.com

### Identity
  email: user@example.com
  _uid: abc-def-123

### Key Attributes
  Name: Jane Smith
  Country: US
  Created: 2024-01-15
  Last Active: 2026-03-18
  Visit Count: 12

### Segment Memberships (5 segments)
  - High Value Customers (segment)
  - Email Subscribers (aspect)
  - US Users (aspect)
  - Q1 Campaign (list)
  - Active Last 30 Days (segment)

### NOT in these commonly-checked segments
  [If the user asks about specific segments, show which they're not in and why]
```

## Condition Evaluation

When cross-referencing FilterQL conditions against profile data, handle each operator type:

| FilterQL Condition | How to Check |
|-------------------|--------------|
| `field = "value"` | Compare profile's field value to literal |
| `field > N` | Numeric comparison against profile value |
| `field > "now-Nd"` | Compare profile's date field to calculated threshold |
| `EXISTS field` | Check if field exists and has a non-empty value in profile |
| `NOT EXISTS field` | Check if field is missing or empty |
| `field INTERSECTS ("a", "b")` | Check if profile's set field contains any listed values |
| `field NOT INTERSECTS ("a")` | Check if profile's set field contains none of the listed values |
| `field CONTAINS "substr"` | Check if profile's string field contains the substring |
| `field IN ("a", "b")` | Check if profile's value is in the list |
| `INCLUDE segment_slug` | Check if user is a member of the referenced segment |

For each condition, always show:
- The condition itself
- PASS or FAIL
- The actual value from the profile (or "field not present" if missing)
- For FAIL: what value would be needed to pass

## Error Handling
- **Profile not found**: Try alternative identity fields, suggest checking spelling. URL-encode values with special characters.
- **Segment not found**: List segments with similar names, suggest checking the slug.
- **Complex FilterQL**: For deeply nested expressions, evaluate the top-level conditions first, then drill into failing branches.
- **Missing fields**: If a profile field referenced in FilterQL doesn't exist on the profile, report it clearly -- this is often the root cause.

## Dependencies
- Composes: `entity-lookup skill`, `segment-manager skill`
- References: `../references/filterql-grammar.md`, `../references/auth.md`, `../references/api-client.md`
