---
name: entity-lookup
description: Look up user profiles by identity field and value. Use when the user wants to find or look up a specific user profile by email, user ID, or other identity field.
metadata:
  arguments: identity field name and value
---

# Entity Lookup

## Purpose
Look up individual user profiles by identity field. Returns the full profile including all fields, segment memberships, and metadata.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## API Endpoints

### V2 Identity Lookup
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/identity/${TABLE}/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Example: `GET /v2/identity/user/email/user@example.com`

### Data API Entity Lookup
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/${TABLE}/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Entity Lookup by Value Only
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/${TABLE}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Searches across all identity fields.

### Entity Segment Memberships
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/${TABLE}/segments/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Identity Lookup (POST)
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/identity/lookup" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"field": "email", "value": "user@example.com", "table": "user"}'
```

### Delete Entity
```bash
# Hard delete
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/${TABLE}/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Soft delete
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/softdelete/${TABLE}/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

## Common Identity Fields
- `email` -- Email address
- `_uid` -- Lytics user ID
- `user_id` -- External user ID
- Check `GET /v2/schema/{table}/idconfig` for account-specific identity fields

## Behavior

### For Lookups (read)
Execute immediately. Display the profile in a structured format:
1. **Identity**: All identity fields and values
2. **Key attributes**: High-value profile fields (name, location, engagement scores)
3. **Segment memberships**: Which segments this user belongs to
4. **Recent activity**: Latest event timestamps

### For Deletes (write)
Use the confirmation-gate pattern. Warn that:
- Hard deletes are irreversible
- Soft deletes can be undone but affect data processing

## Error Handling
- **Profile not found (404)**: Suggest trying different identity fields or checking spelling
- **URL encoding**: URL-encode the value if it contains special characters (e.g., `@` in emails)
- **Multiple matches**: If multiple profiles match, present all and ask user to select

## Dependencies
- Uses: `../references/api-client.md`, `../references/confirmation-gate.md` (for deletes only)
