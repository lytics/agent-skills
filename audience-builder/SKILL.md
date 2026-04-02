---
name: audience-builder
description: Create or update audience segments from natural language descriptions. Use when the user wants to build, create, or define an audience or segment from a natural language description.
metadata:
  arguments: natural language description of the desired audience
---

# Audience Builder

## Purpose
The primary end-to-end skill. Takes a natural language audience description and produces a validated, sized, and confirmed segment. Composes schema-discovery, filterql-builder, segment-manager, and confirmation-gate.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Inputs
- Natural language description of the desired audience
- Optional: segment name, table (default: `user`), kind (default: `segment`), tags

## End-to-End Flow

### Step 0: Check if Advisor Would Be Better
If the user's request is goal-oriented rather than specific (e.g., "I want to drive more conversions" vs "US users who visited 5+ times"), suggest starting with the `audience-advisor skill` first:
> "It sounds like you have a business goal in mind. Would you like me to analyze your data first to recommend the best targeting strategy? I can look at ML models, field distributions, and existing segments to suggest evidence-based filters."

If the user has a specific audience description, proceed directly to Step 1.

### Step 1: Parse Intent
Extract the key concepts from the natural language description:
- Target attributes (demographics, behaviors, properties)
- Inclusion criteria (what they have/did)
- Exclusion criteria (what they lack/didn't do)
- Temporal constraints (time-based conditions)

Example: "US customers who haven't purchased socks in over a year"
- Attribute: country = US
- Exclusion: no sock purchases
- Temporal: over 1 year ago

### Step 2: Schema Discovery
Use `schema-discovery skill` to find matching fields:

```bash
# Get all fields to find candidates
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Score candidate fields by name match, type compatibility, and value distribution. For the example:
- "US customers" -> look for: `country`, `geo_country`, `country_code` (string type)
- "purchased socks" -> look for: `products_purchased` (set), `purchase_categories` (set), `last_purchase_date` (date)

Fetch value suggestions for top candidates -- the `q` parameter is required:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/schema/user/fieldsuggest/${FIELD}?q=${QUERY}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Example: `/api/schema/user/fieldsuggest/country?q=US`

Confirm field values match (e.g., `country` contains "US", `products_purchased` contains "socks").

### Step 3: Build FilterQL
Use `filterql-builder skill` to construct the filter expression.

Map each concept to a FilterQL condition based on field type (see `../references/field-types.md`):
- String equality: `country = "US"`
- Set non-membership: `NOT products_purchased INTERSECTS ("socks")`
- Date comparison: `last_sock_purchase < "now-1y"`

Compose with AND/OR:
```
FILTER AND (
  country = "US",
  NOT products_purchased INTERSECTS ("socks")
) FROM user ALIAS us_no_socks
```

### Step 4: Validate FilterQL
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/validate" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d 'FILTER AND (country = "US", NOT products_purchased INTERSECTS ("socks")) FROM user ALIAS us_no_socks'
```

If validation fails:
1. Parse the error message
2. Identify the syntax issue
3. Fix the FilterQL
4. Retry (max 3 attempts)
5. If still failing, show the error and ask the user for guidance

### Step 5: Estimate Size
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/size" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d 'FILTER AND (country = "US", NOT products_purchased INTERSECTS ("socks")) FROM user ALIAS us_no_socks'
```

### Step 6: Present Draft (Confirmation Gate)
Show the user a complete summary before creating:

```
## Proposed Audience: US Non-Sock Buyers

**Name**: US Non-Sock Buyers
**Slug**: us_no_socks
**Table**: user
**Kind**: segment

**Description**: US customers who have not purchased socks

**Field Mapping**:
- "US customers" -> `country = "US"` (field type: string, sample values: US, CA, UK)
- "haven't purchased socks" -> `NOT products_purchased INTERSECTS ("socks")` (field type: []string)

**FilterQL**:
FILTER AND (country = "US", NOT products_purchased INTERSECTS ("socks")) FROM user ALIAS us_no_socks

**Estimated Size**: ~45,000 profiles
```

Then show the raw API payload:
```json
{
  "name": "US Non-Sock Buyers",
  "slug_name": "us_no_socks",
  "description": "US customers who have not purchased socks",
  "segment_ql": "FILTER AND (country = \"US\", NOT products_purchased INTERSECTS (\"socks\")) FROM user ALIAS us_no_socks",
  "kind": "segment",
  "table": "user",
  "is_public": true,
  "save_hist": true,
  "tags": []
}
```

Ask for confirmation: "Proceed with creating this segment? (yes/no)"

### Step 7: Execute on Approval
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... approved payload ... }'
```

Report the result:
```
Successfully created segment "US Non-Sock Buyers" (id: abc123)
View at: ${LYTICS_API_URL}/segment/us_no_socks
```

After successful creation, offer an audience snapshot:
"Segment created successfully. Would you like to see an audience snapshot showing the demographic breakdown and field distributions?"
If yes, invoke the `audience-snapshot skill` with the new segment ID.

## Handling Ambiguity

When field mapping is ambiguous (multiple equally strong candidates):
1. Present the top candidates with sample values
2. Let the agent pick the best match based on context -- do NOT prompt the user unless truly ambiguous
3. Only ask the user when there's a genuine tie or the field purpose is unclear

## Updating Existing Segments

If the user wants to update an existing segment:
1. Fetch the current segment: `GET /v2/segment/${ID}?inline=true`
2. Show current FilterQL and proposed changes
3. Use `PUT /v2/segment/${ID}` instead of POST

## Error Handling
- **No matching fields**: Report clearly, suggest the user describe their data differently
- **Validation failure after 3 retries**: Show the FilterQL and error, ask for help
- **Empty segment (size 0)**: Warn and suggest broadening criteria
- **Very large segment (>90% of total)**: Note this and confirm intent

## Dependencies
- Composes: `schema-discovery skill`, `filterql-builder skill`, `segment-manager skill`, `../references/confirmation-gate.md`
- References: `../references/filterql-grammar.md`, `../references/field-types.md`
