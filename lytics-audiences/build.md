# Build

Turn a natural-language audience description (or structured conditions) into validated FilterQL, size it, and create the segment through the confirmation gate.

Inputs: the description; optional name, table (default `user`), kind (default `segment`), tags.

## Step 0: Should this be advise mode?

If the request is a goal ("drive more conversions") rather than a specific audience ("US users who visited 5+ times"), offer `advise.md` first:
> "It sounds like you have a business goal in mind. Would you like me to analyze your data first to recommend the best targeting strategy? I can look at ML models, field distributions, and existing segments to suggest evidence-based filters."

## Step 1: Parse intent

Extract target attributes, inclusion criteria (what they have/did), exclusion criteria (what they lack/didn't do), and temporal constraints.

Example: "US customers who haven't purchased socks in over a year" -> attribute `country = US`; exclusion: no sock purchases; temporal: over 1 year ago.

## Step 2: Find the fields

List the table's fields (the `lytics-schema` skill covers this in depth):
```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Score candidates by name match, type compatibility, and value distribution. For the example: "US customers" -> `country`, `geo_country`, `country_code` (string); "purchased socks" -> `products_purchased` (set), `purchase_categories` (set), `last_purchase_date` (date).

Confirm values exist with field suggestions. **`q` is required**, and URL-encode it:
```bash
curl -sS -G "${LYTICS_API_URL:-https://api.lytics.io}/api/schema/user/fieldsuggest/${FIELD}" \
  --data-urlencode "q=${QUERY}" -H "Authorization: ${LYTICS_API_TOKEN}"
```
e.g. `/api/schema/user/fieldsuggest/country?q=US`.

Ambiguity: when several candidates are equally strong, compare their sample values and pick the best match from context. Ask the user only on a genuine tie or when a field's purpose is unclear.

## Step 3: Translate to FilterQL

Map each condition by field type (full matrix: `references/field-types.md`; grammar: `references/filterql-grammar.md`):

| Field type | Natural language | FilterQL |
|---|---|---|
| `string` | equals "X" | `field = "X"` |
| `string` | not "X" | `field != "X"` |
| `string` | contains "X" | `field CONTAINS "X"` |
| `string` | like pattern | `field LIKE "pattern*"` |
| `string` | one of A,B,C | `field IN ("A", "B", "C")` |
| `bool` | is true / false | `field = true` / `field = false` |
| `int`/`number` | more than / at least / less than N | `field > N` / `field >= N` / `field < N` |
| `date` | after N days ago | `field > "now-Nd"` |
| `date` | before N days ago | `field < "now-Nd"` |
| `date` | within last N hours | `field > "now-Nh"` |
| `[]string` (set) | has "X" | `field INTERSECTS ("X")` |
| `[]string` (set) | doesn't have "X" | `field NOT INTERSECTS ("X")` or `NOT field INTERSECTS ("X")` |
| any | has any value / is empty | `EXISTS field` / `NOT EXISTS field` |

Date math units are `h`, `d`, `w`, `M` (months), `y`: 1 year = `"now-1y"` = `"now-365d"` = `"now-8760h"`; 90 days = `"now-90d"` = `"now-2160h"`; 1 week = `"now-1w"` = `"now-7d"` = `"now-168h"`.

Composition rules:
- Single condition: `FILTER condition FROM table ALIAS slug`.
- Multiple conditions default to `AND`; groups need parentheses and comma-separated members; `NOT` wraps any condition or group.
- Escape quotes inside values. If the operator doesn't fit the field type, switch to the compatible one.

Slug: lowercase, spaces -> underscores, special characters removed, descriptive but short.

```
FILTER AND (
  country = "US",
  NOT products_purchased INTERSECTS ("socks")
) FROM user ALIAS us_no_socks
```

## Step 4: Validate

Body is raw FilterQL, not JSON:
```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/validate" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: text/plain" \
  --data-binary 'FILTER AND (country = "US", NOT products_purchased INTERSECTS ("socks")) FROM user ALIAS us_no_socks'
```
200 = valid. On failure read the message, fix the FilterQL, retry up to 3 times; then show the FilterQL and error and ask the user.

If the user only wanted a FilterQL expression, stop here and return it.

## Step 5: Size

`POST /api/segment/size` with the same raw FilterQL body (`text/plain`).
- Size 0: warn and suggest broadening.
- More than ~90% of the total: point it out and confirm intent.

## Step 6: Confirmation gate

Summary, including the field mapping and size:
```
## Proposed Audience: US Non-Sock Buyers
**Name**: US Non-Sock Buyers   **Slug**: us_no_socks   **Table**: user   **Kind**: segment
**Description**: US customers who have not purchased socks
**Field Mapping**:
- "US customers" -> `country = "US"` (string, sample values: US, CA, UK)
- "haven't purchased socks" -> `NOT products_purchased INTERSECTS ("socks")` ([]string)
**FilterQL**: FILTER AND (country = "US", NOT products_purchased INTERSECTS ("socks")) FROM user ALIAS us_no_socks
**Estimated Size**: ~45,000 profiles
```
Then the raw payload (field reference: `manage.md`):
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
Ask: "Proceed with creating this segment? (yes/no)"

## Step 7: Create and report

On approval, `POST /v2/segment` with the payload (`--data-binary @body.json`). Report `.data.id` and `.data.slug_name` **from the response**, not the slug you sent: a taken slug is silently renamed to `<slug>_1` and the create still succeeds, and the slug you sent belongs to someone else's segment. If they differ, say so explicitly.
```
Successfully created segment "US Non-Sock Buyers" (id: abc123, slug: us_no_socks)
```
Then offer a snapshot (`snapshot.md`) with the new id.

## Updating instead of creating

1. `GET /v2/segment/${ID}?inline=true`.
2. Show the current FilterQL beside the proposed one.
3. `PUT /v2/segment/${ID}` following the update rules in `manage.md`: keep the segment's `FROM <table>` and `ALIAS <slug>`, and check the response `.data.id` equals `${ID}`, otherwise a new segment was created.

No matching fields at all: say so clearly and ask the user to describe the data differently.
