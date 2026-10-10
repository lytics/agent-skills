# Tokens

List, inspect, create, rotate, or revoke the current account's API tokens. API tokens are auths with `auth_type: "api_token"`; the same `/v2/auth` endpoints also hold integration credentials, so always filter by type.

## Read

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth?auth_type=api_token" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Call | Returns |
|---|---|
| `GET /v2/auth?auth_type=api_token` | Every API token on the account |
| `GET /v2/auth/{id}` | One token |

Each token: `id`, `type` (`"lytics-auth-token"` for API tokens), `label`, `description`, `scopes` (role slugs), `ttl`, `expires`, `created`, `updated`, `last_accessed_at`, `user_id`, `internal`, `status`.

- **The secret is never returned by a read.** It exists only in the create response.
- `expires` of `0001-01-01T00:00:00Z` means the token never expires.
- `internal: true` marks a system-generated token. `/v2/auth` includes them; never revoke one.
- An expired token is rejected with `401 {"message": "Expired Token"}`.

## Create

`POST /api/auth/createtoken` -- an `/api` endpoint, so errors are in `.message`.

- **Requires a user (login) token.** Called with an API token it returns `403 "Not authorized: This endpoint is available only via user tokens."` In the CLI, `LYTICS_API_TOKEN` is usually an API token: tell the user to create the token in the Lytics UI instead, or to supply a user token for this call only.
- Body fields:
  | Field | Rule |
  |---|---|
  | `scopes` | Required, array of role slugs (same slugs as user roles, see [users.md](users.md#roles)). Unknown slug: `400 Unknown roles "<slug>"`. A role the calling user does not hold: `403 User does not have permission to add these roles in token: [...]`. |
  | `label` / `description` | At least one required (400 otherwise). |
  | `expires` | Optional duration string in `h`/`m`/`s` (`"720h"` for 30 days; there is no `d` unit). Negative is rejected. **Omitted means the token never expires**; recommend an expiry. |
  | `alert_enabled` | Optional, default `true`: email the creator and `auth_alerts` users before expiry. Only applies when `expires` is set. |

```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/auth/createtoken" \
  -H "Authorization: ${USER_TOKEN:?a user (login) token is required}" -H "Content-Type: application/json" \
  --data-binary '{"label":"segment-export","description":"nightly export","scopes":["v2_segment_view"],"expires":"720h"}'
```

- **The token value is shown once**, in the response at `.data.config[] | select(.name == "api_key") | .value` (format `at.<id>.<secret>`). It cannot be read back later. Deliver it to the user a single time by the route they choose (e.g. a file path they name, mode 600), and do not repeat it in later messages or logs.
- Grant the fewest roles that do the job; a token with `admin` can manage users and other tokens.

## Rotate

There is no verified in-place edit for a token's scopes or expiry: create a new token, have the user switch every client to it, then revoke the old one.

## Revoke

`DELETE /v2/auth/{id}` returns 204.

- **Permanent.** The token is deleted, not disabled; every client still using it stops authenticating and there is no undo.
- Read `GET /v2/auth/{id}` first and confirm `type == "lytics-auth-token"` and `internal == false` (the v2 response has no `auth_type` field): the same endpoint deletes integration credentials.
- **Never revoke the token this session is using.** For an `at.<id>.<secret>` token the middle segment is its auth id; compare it to the target id without printing the token.
- Confirmation summary: label, description, scopes, `last_accessed_at`, and "Anything using this token will stop working. This cannot be undone."
