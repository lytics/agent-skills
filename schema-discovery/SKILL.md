---
name: schema-discovery
description: Discover and interpret profile schema fields, types, and sample values for field mapping. Use when the user wants to find schema fields, understand field types, or discover what data is available in the profile schema.
metadata:
  arguments: natural language description of the fields to find
---

# Schema Discovery

## Purpose
Fetch and interpret the profile schema to find fields that match natural language descriptions. Used by other skills (especially audience-builder) to map user intent to actual schema fields.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## Inputs
- Natural language description of the data concepts to find (e.g., "country", "purchase history", "email engagement")
- Table name (default: `user`)

## API Endpoints

### List All Fields
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE:-user}/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Returns all fields with their types, descriptions, and merge operations.

### Lightweight Field Names
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE:-user}/fieldnames" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Returns just field names -- use for quick inventory.

### Field Info with Value Distributions
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/schema/${TABLE:-user}/fieldinfo" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Returns field info including value distributions and sample data.

### Field Value Suggestions
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/schema/${TABLE:-user}/fieldsuggest/${FIELD}?q=${QUERY}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Returns suggested values for a specific field matching the query substring. The `q` parameter is **required** -- it performs case-insensitive substring matching against field values.

### Identity Configuration
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE:-user}/idconfig" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Available Streams
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/names" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

## Behavior

### Step 1: Fetch Field Inventory
Call the field names endpoint to get the complete list of available fields.

### Step 2: Score Candidate Fields
For each concept in the user's description, score candidate fields by:
1. **Name match** (highest priority): exact or substring match on field name
2. **Type compatibility**: field type supports the intended operation (see `../references/field-types.md`)
3. **Description match**: field's `ShortDesc` or `LongDesc` matches

### Step 3: Confirm with Value Distributions
For the top 2-3 candidates per concept, fetch field value suggestions to confirm:
- The field contains the expected kind of data
- Sample values match what the user described (e.g., "US" values in a country field)

### Step 4: Return Field Mapping
Return a mapping of:
- Concept -> chosen field name, field type, confidence level, sample values
- Any ambiguities that need user input

## Field Matching Heuristics

Common natural language to field name patterns:
- "country" -> `country`, `geo_country`, `country_code`
- "email" -> `email`, `_e`
- "purchased/bought" -> `products_purchased`, `purchase_categories`, `orders`
- "visited/browsed" -> `urls_visited`, `pages_viewed`, `visit_count`
- "signed up/registered" -> `created`, `signup_date`, `joined`
- "clicked" -> `click_count`, `clicks`
- "score" -> `scores.*`, `engagement_score`

## Error Handling
- If no fields match a concept, report that clearly and suggest the user rephrase or check available fields
- If multiple equally strong candidates exist, present them for user selection
- If the table doesn't exist, report and suggest `user` as default

## Dependencies
- References: `../references/auth.md`, `../references/api-client.md`, `../references/field-types.md`
