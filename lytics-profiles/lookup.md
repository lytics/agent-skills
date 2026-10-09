# Lookup

Use to find one profile by identity, list its segment memberships, or delete it.

## Endpoints

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/identity/${TABLE}/${FIELD}/$(jq -rn --arg v "$VALUE" '$v|@uri')" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Purpose | Request | Notes |
|---|---|---|
| V2 identity lookup | `GET /v2/identity/{table}/{field}/{value}` | e.g. `/v2/identity/user/email/user@example.com`. Returns 404 when not found. |
| Data API entity lookup | `GET /api/entity/{table}/{field}/{value}` | Full profile: fields, segment memberships, metadata. Not found = 200 placeholder (below). |
| Lookup by value only | `GET /api/entity/{table}/{value}` | Looks the value up as `_uid` only -- does **not** search other identity fields. For an email or external id, use the field/value form. |
| Segment memberships | `GET /api/entity/{table}/segments/{field}/{value}` | |
| Identity lookup (POST) | `POST /v2/identity/lookup` | Body: `{"field": "email", "value": "user@example.com", "table": "user"}` |

Common identity fields: `email` (email address), `_uid` (Lytics user ID), `user_id` (external user ID). Check `GET /v2/schema/{table}/idconfig` for the account's own identity fields.

## Not found

`/api/entity` does **not** return 404. It returns HTTP 200 with `message: "Not Found"` (or `"Timed out"`) and a placeholder body `{"segments": ["not_found", "all"]}`. Never present that as a real profile in segment `all`. Check `.message` and the `not_found` segment, or use `/v2/identity`, which does return 404. Then suggest other identity fields or checking spelling.

If multiple profiles match, present all and ask the user to select.

## Presenting a profile

Reads execute immediately. Display:
1. **Identity**: all identity fields and values
2. **Key attributes**: high-value fields (name, location, engagement scores)
3. **Segment memberships**: which segments this user belongs to
4. **Recent activity**: latest event timestamps

## Delete (write)

Use `references/confirmation-gate.md`. Warn that **both** kinds are irreversible through the API.

```bash
# Hard delete -- asynchronous. Returns a request_id; poll /api/entity/deletestatus/{request_id}.
# Defaults to conflicts=true: a greedy identity traversal that can reach identifiers beyond
# the single profile a lookup shows. Pass ?conflicts=false to keep it narrow.
curl -sS -w '\n%{http_code}\n' -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/${TABLE}/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Soft delete
curl -sS -w '\n%{http_code}\n' -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/softdelete/${TABLE}/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

- **Hard delete** removes the profile. Because the default `conflicts=true` traverses identities greedily, say so in the gate and offer `?conflicts=false`.
- **Soft delete** cannot be undone either: the undelete endpoint is deprecated and returns 401, with no replacement.
- Soft delete returns 200 even when no such profile exists, so a 200 does not confirm anything was deleted. Look the profile up first.
