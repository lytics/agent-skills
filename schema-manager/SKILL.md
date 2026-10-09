---
name: schema-manager
description: Browse and modify schema fields, mappings, identity config, and field rankings. Use when the user wants to list, view, create, or modify schema fields, mappings, identity configuration, or field rankings.
metadata:
  arguments: action and relevant parameters -- list-fields, get-field, create-field, list-mappings, create-mapping, publish
---

# Schema Manager

## Purpose
Browse and modify the profile schema -- fields, mappings, identity configuration, and field rankings. Use this when users want to understand their data model, add new fields, or modify field mappings.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## API Endpoints

### Schema Overview
```bash
# List all schemas (tables)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get specific schema
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Fields
```bash
# List all fields
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get field names only
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/fieldnames" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get specific field
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field/${FIELD_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Create field
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "field_name",
    "type": "string",
    "shortdesc": "Brief description",
    "mergeop": "latest",
    "is_identifier": false,
    "is_pii": false
  }'

# Update field -- this is a full replace, not a merge. Any key you omit is reset,
# so `is_identifier` / `is_pii` silently become false if left out.
# GET the field first, change only what the user asked for, and POST the whole object back.
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field/${FIELD_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" | jq '.data' > field.json
# ...edit field.json...
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field/${FIELD_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary @field.json

# Delete field
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field/${FIELD_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Mappings

A mapping connects a source stream field to a target schema field via an LQL expression. **A field without at least one mapping is inert** -- it will never receive data.

```bash
# List mappings
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/mapping" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get specific mapping
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/mapping/${MAPPING_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Create mapping -- all three fields (field, stream, expr) are required
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/mapping" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "field": "email",
    "stream": "default",
    "expr": "email(email_address)"
  }'

# Create mapping with guard condition
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/mapping" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "field": "hashed_email",
    "stream": "click_stream",
    "expr": "hash.sha256(email(email))",
    "guard_expr": "email != '\'\''"
  }'

# Update mapping -- `stream` cannot change on an existing mapping (rejected with 400).
# To move a mapping to another stream, delete it and create a new one.
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/mapping/${MAPPING_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "field": "email",
    "stream": "default",
    "expr": "email(raw_email)"
  }'

# Delete mapping
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/mapping/${MAPPING_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

**Mapping payload fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `field` | YES | Target schema field name -- must reference an existing field |
| `stream` | YES | Source stream name (e.g., `default`, `salesforce_contacts`) |
| `expr` | YES | LQL expression to extract/transform the value (e.g., `set(raw_field)`, `email(email_address)`) |
| `guard_expr` | No | Optional condition controlling when this mapping applies (do not prefix with "IF") |

**Common LQL expressions for mappings:**
- Simple pass-through: `raw_field_name`
- Set/array: `set(raw_field)`
- Email normalization: `email(email_address)`
- Hashing: `hash.sha256(email(email))`
- URL parsing: `url(page_url)`
- Type casting: `todate(timestamp_field)`

### Schema Patches

Schema patches group related changes into a named changeset that can be reviewed and applied together -- like a git branch for schema changes. Accounts with `enable_schema_patches: true` **must** use patches for all schema changes. See "Determining the Write Workflow" in the Behavior section.

**Patch lifecycle**: Create patch -> Add changes -> Review diff -> Apply

```bash
# List all patches for a table
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Create a new patch -- `tag` (kebab-case identifier) and `description` are both required.
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "tag": "add-purchase-fields",
    "description": "Add purchase tracking fields and mappings for Shopify integration"
  }'

# Get a specific patch (includes diffs against live schema)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Update patch metadata
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"description": "Updated description"}'

# Delete a patch (discard all changes)
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Apply a patch (publishes a new schema version with all changes)
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}/apply" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

**Add fields to a patch:**

> **Patch endpoint payload shape is lowercase.** Use `id` (the field name), `type`, `shortdesc`, `mergeop`, `is_identifier`, `is_pii`. The capitalized shape (`Field`, `Type`, `ShortDesc`, ...) shown in the non-patch direct-write examples below is NOT accepted here -- patch endpoints will return `Attribute 'Field' is required for Field` if you send capitalized keys.

```bash
# Add or update a field in the patch
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "purchase_total",
    "type": "number",
    "shortdesc": "Total purchase amount",
    "mergeop": "sum",
    "is_identifier": false,
    "is_pii": false
  }'

# Update an existing field in the patch
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}/field/${FIELD_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... full field definition ... }'

# Get a field from the patch (shows diff against live)
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}/field/${FIELD_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

**Add mappings to a patch:**
```bash
# Add a mapping in the patch
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}/mapping" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "field": "purchase_total",
    "stream": "shopify_orders",
    "expr": "total_price"
  }'

# Update an existing mapping in the patch
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}/mapping/${MAPPING_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... mapping definition ... }'
```

**Add rank changes to a patch:**
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/patch/${TABLE}/${PATCH_ID}/rank" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... rank config ... }'
```

**Edit statuses within a patch:**

| Status | Meaning |
|--------|---------|
| `new` | Does not exist in live schema -- will be created |
| `modified` | Exists in live schema -- properties have been changed |
| `deleted` | Marked for removal when patch is applied |
| `unmodified` | Included for context, no changes from live |

### Identity Configuration
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/idconfig" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Field Rankings
```bash
# Get field rankings
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/rank" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Update field rankings
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/rank" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... ranking config ... }'
```

### Publish Schema Changes
Publish requires a tag and description. Both are mandatory.
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/publish" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "tag": "short-kebab-tag",
    "description": "Human-readable description of what changed"
  }'
```
The `tag` should be a short kebab-case identifier (e.g., `add-phone-identifier`). The `description` should explain the changes for audit purposes.

### Generate LQL from Schema
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/lql" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... schema config ... }'
```

## Field Types

See `../references/field-types.md` for the complete type reference including:
- Scalar: `string`, `bool`, `int`, `number`, `date`
- Complex: `[]string`, `map[string]int`, `map[string]string`, etc.
- Special: `geolocation`, `embedding`, `membership`

## Behavior

### For Read Operations (list, get, browse)
Execute immediately. Present fields in a readable table format showing:
- Field name, type, description, merge operation, identity/PII flags

### Determining the Write Workflow

Some accounts require schema patches (account setting `enable_schema_patches: true`). Others use the direct publish workflow. **You must determine which mode the account uses before making any schema changes.**

Check the setting itself:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/account/setting/enable_schema_patches" \
  -H "Authorization: ${LYTICS_API_TOKEN}" | jq '.data.value'
```
`true` means patches; `false` or `null` means direct publish. Reading settings needs a token with account-settings read access -- if the read is refused (401/403), ask the user which mode the account uses rather than guessing. Do **not** probe by listing patches: `GET /v2/schema/patch/{table}` returns 200 on every account, so it reports patches even where they are off.

### Write Workflow A: Schema Patches (when enabled)

When the account has schema patches enabled, **all schema changes must go through patches**. Direct field/mapping edits will not work.

**Complete workflow for adding a new field with mapping:**

1. **Create a patch** with a descriptive name
2. **Add the field** to the patch
3. **Add a mapping** for the field to the patch -- a field without a mapping is inert and will never receive data. Always ask: "Which stream should populate this field, and what is the source field name?"
4. **Review** the patch diff (GET the patch to see all changes vs live schema)
5. **Confirm** with the user (show the diff summary)
6. **Apply** the patch (this publishes a new schema version)

If the user doesn't know the stream name, list available streams:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/stream/names" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Write Workflow B: Direct Publish (when patches are not enabled)

When the account does not use schema patches, edits go into a shared unpublished draft and must be published manually.
Schema changes are **staged until published** -- they do not take effect until you publish.

When creating a new field, **always prompt for a mapping** -- a field without a mapping is inert. Then publish both together.

Every write operation MUST follow this sequence:

1. **Confirm**: Use the confirmation-gate pattern. Show what will change and get user approval. Publish ships the **whole shared draft**, including edits other users have staged and not yet published -- so before confirming, show the full pending diff, not just your own change:
   ```bash
   curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/compare" \
     -H "Authorization: ${LYTICS_API_TOKEN}"
   ```
   If the draft contains changes you did not make, list them and ask whether to publish them too.
2. **Execute**: Make the field/mapping change via the API.
3. **Publish**: Immediately publish the changes. A schema write is NOT complete until publish succeeds.
   ```bash
   curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/publish" \
     -H "Authorization: ${LYTICS_API_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{"tag": "descriptive-tag", "description": "What changed and why"}'
   ```
4. **Verify**: Confirm publish succeeded. If it fails, report the error -- the changes are still staged and need to be published before they take effect.

**Never consider a schema write operation complete without publishing.** If multiple changes are being made in sequence, you may batch them and publish once at the end, but always publish before reporting success.

## Error Handling
- **Field already exists**: there is no 409 -- field POST is an upsert and silently replaces the existing field. GET `/v2/schema/{table}/field/{id}` before creating, and if it exists, confirm the user means to replace it
- **Invalid type**: List valid types from `../references/field-types.md`
- **Publish failures**: Show error details, suggest checking field validity

## Dependencies
- Uses: `../references/auth.md`, `../references/api-client.md`, `../references/confirmation-gate.md`
- References: `../references/field-types.md`
