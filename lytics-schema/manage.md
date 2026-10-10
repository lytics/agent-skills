# Manage

Use to browse or change schema fields, mappings, identity configuration, and field rankings, and to publish those changes (directly or through a schema patch).

## Reads (execute immediately)

| Call | Returns |
|---|---|
| `GET /v2/schema` | All schemas (tables) |
| `GET /v2/schema/{table}` | One schema |
| `GET /v2/schema/{table}/field` | All fields |
| `GET /v2/schema/{table}/fieldnames` | Field names only |
| `GET /v2/schema/{table}/field/{field_id}` | One field |
| `GET /v2/schema/{table}/mapping` | All mappings |
| `GET /v2/schema/{table}/mapping/{mapping_id}` | One mapping |
| `GET /v2/schema/{table}/idconfig` | Identity configuration |
| `GET /v2/schema/{table}/rank` | Field rankings |
| `GET /v2/schema/{table}/compare` | The pending (unpublished) draft diff |
| `GET /v2/stream/names` | Available streams |

Present fields as a table: name, type, description, merge operation, identifier/PII flags. Types: `references/field-types.md` (scalar `string`, `bool`, `int`, `number`, `date`; complex `[]string`, `map[string]int`, `map[string]string`, ...; special `geolocation`, `embedding`, `membership`).

## Step 0 for any write: which workflow?

Some accounts require schema patches; others use direct publish. Determine which **before** any change, from the setting itself:

```bash
curl -sS "${LYTICS_API_URL:-https://api.lytics.io}/api/account/setting/enable_schema_patches" \
  -H "Authorization: ${LYTICS_API_TOKEN}" | jq '.data.value'
```

`true` means patches (Workflow A); `false` or `null` means direct publish (Workflow B). Reading settings needs a token with account-settings read access: if the read is refused (401/403), ask the user which mode the account uses rather than guessing. Do **not** probe by listing patches: `GET /v2/schema/patch/{table}` returns 200 on every account, so it reports patches even where they are off.

## Fields

Payload keys are lowercase: `id` (field name), `type`, `shortdesc`, `mergeop`, `is_identifier`, `is_pii`. Capitalized keys are not accepted.

```json
{"id": "field_name", "type": "string", "shortdesc": "Brief description", "mergeop": "latest", "is_identifier": false, "is_pii": false}
```

- **Create**: `POST /v2/schema/{table}/field`. This is an upsert; there is no 409. GET `/v2/schema/{table}/field/{id}` first, and if it exists, confirm the user means to replace it.
- **Update**: `POST /v2/schema/{table}/field/{field_id}`. A **full replace, not a merge**: any omitted key is reset, so `is_identifier` / `is_pii` silently become false. GET first, change only what the user asked for, POST the whole object back. GET reports a server-filled `mergeop` on identifier fields, but POST rejects a merge op on an identifier (`Identifier Field cannot define a Merge Operation.`), so drop it:

  ```bash
  curl -sS "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field/${FIELD_ID}" \
    -H "Authorization: ${LYTICS_API_TOKEN}" | jq '.data | if .is_identifier then del(.mergeop) else . end' > field.json
  # ...edit field.json...
  curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/field/${FIELD_ID}" \
    -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: application/json" \
    --data-binary @field.json
  ```
- **Delete**: `DELETE /v2/schema/{table}/field/{field_id}`.
- Invalid type: list the valid types from `references/field-types.md`.

## Mappings

A mapping connects a source stream field to a target schema field via an LQL expression. **A field without at least one mapping is inert**: it will never receive data.

| Key | Required | Description |
|---|---|---|
| `field` | yes | Target schema field; must reference an existing field |
| `stream` | yes | Source stream (e.g. `default`, `salesforce_contacts`) |
| `expr` | yes | LQL expression that extracts/transforms the value |
| `guard_expr` | no | Condition controlling when the mapping applies (do not prefix with `IF`) |

```json
{"field": "hashed_email", "stream": "click_stream", "expr": "hash.sha256(email(email))", "guard_expr": "email != ''"}
```

- **Create**: `POST /v2/schema/{table}/mapping` (all of `field`, `stream`, `expr`).
- **Update**: `POST /v2/schema/{table}/mapping/{mapping_id}`. **`stream` cannot change** on an existing mapping (rejected with 400); to move a mapping to another stream, delete it and create a new one.
- **Delete**: `DELETE /v2/schema/{table}/mapping/{mapping_id}`.

Common expressions: pass-through `raw_field_name`; set/array `set(raw_field)`; email normalization `email(email_address)`; hashing `hash.sha256(email(email))`; URL parsing `url(page_url)`; type casting `todate(timestamp_field)`.

## Rankings, identity, LQL

- `POST /v2/schema/{table}/rank` with the ranking config updates field rankings.
- `GET /v2/schema/{table}/idconfig` reads identity configuration.
- `POST /v2/schema/lql` with a schema config generates LQL from a schema.

## Workflow A: schema patches (`enable_schema_patches: true`)

A patch groups related changes into a named changeset that is reviewed and applied together, like a git branch for the schema. On these accounts **all** schema changes must go through patches; direct field/mapping edits will not work.

| Call | Does |
|---|---|
| `GET /v2/schema/patch/{table}` | List patches |
| `POST /v2/schema/patch/{table}` | Create; `tag` (kebab-case) and `description` are both required |
| `GET /v2/schema/patch/{table}/{patch_id}` | One patch, with diffs against the live schema |
| `POST /v2/schema/patch/{table}/{patch_id}` | Update patch metadata, e.g. `{"description": "..."}` |
| `DELETE /v2/schema/patch/{table}/{patch_id}` | Delete the patch (discard all its changes) |
| `POST /v2/schema/patch/{table}/{patch_id}/apply` | Apply: publishes a new schema version with all changes |
| `POST /v2/schema/patch/{table}/{patch_id}/field` | Add or update a field (lowercase payload, as above) |
| `POST /v2/schema/patch/{table}/{patch_id}/field/{field_id}` | Update a field in the patch (full field definition) |
| `GET /v2/schema/patch/{table}/{patch_id}/field/{field_id}` | A field in the patch, with diff against live |
| `POST /v2/schema/patch/{table}/{patch_id}/mapping` | Add a mapping |
| `POST /v2/schema/patch/{table}/{patch_id}/mapping/{mapping_id}` | Update a mapping in the patch |
| `POST /v2/schema/patch/{table}/{patch_id}/rank` | Add rank changes |

Patch endpoints return `Attribute 'Field' is required for Field` if you send capitalized keys.

Edit statuses within a patch: `new` (not in live; will be created), `modified` (in live; properties changed), `deleted` (removed on apply), `unmodified` (included for context).

Adding a field with its mapping:

1. Create a patch with a descriptive tag and description (e.g. `add-purchase-fields`).
2. Add the field.
3. Add a mapping for it. Always ask: "Which stream should populate this field, and what is the source field name?" If the user doesn't know, list `GET /v2/stream/names`.
4. Review: GET the patch to see every change vs live.
5. Confirm with the user, showing the diff summary (`references/confirmation-gate.md`).
6. Apply the patch.

## Workflow B: direct publish (patches not enabled)

Edits go into a **shared unpublished draft** and take no effect until published. When creating a field, always prompt for a mapping, then publish both together.

1. **Confirm** via `references/confirmation-gate.md`. Publish ships the **whole shared draft**, including edits other users staged and have not published, so show the full pending diff, not just your change: `GET /v2/schema/{table}/compare`. If it contains changes you did not make, list them and ask whether to publish them too.
2. **Execute** the field/mapping change.
3. **Publish** immediately; `tag` and `description` are both mandatory:

   ```bash
   curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE}/publish" \
     -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: application/json" \
     -d '{"tag": "add-phone-identifier", "description": "What changed and why"}'
   ```

   `tag` is a short kebab-case identifier; `description` explains the change for audit.
4. **Verify** publish succeeded. If it failed, report the error (and suggest checking field validity): the changes are still staged and must be published before they take effect.

**A schema write is never complete without publishing.** Several changes may be batched and published once at the end, but always publish before reporting success.
