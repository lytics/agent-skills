# Users

List the users of the current account and their roles, invite a user, change a user's roles, or remove a user from the account. Every call acts on the account the token belongs to.

All endpoints here are `/v2`: read errors from `.errors[0].message` (`references/api.md`).

## Read

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/user" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Call | Returns |
|---|---|
| `GET /v2/user` | Every user on this account: `id`, `email`, `name`, `last_logon`, `created`, and `accounts[]` |
| `GET /v2/user/{id-or-email}` | One user. **404 when the user is not on this account**, even if the email exists elsewhere. URL-encode the email (`@`). |
| `GET /v2/user/me` | The caller. Needs a user (login) token; an API token gets 401. |
| `GET /v2/account/{aid}?roles=true` | The account, plus `roles_available[]`: `slug`, `name`, `description`, `type`, `can_be_assigned`, `can_be_shown`, `permissions`. Without `roles=true` the list is omitted. |

A user's roles live per account in `accounts[]` (`aid`, `account_id`, `roles`, `granted_by`, `expiration`); read this account's entry, not the first one:

```bash
jq --argjson aid "$AID" '.data[] | {email, roles: ((.accounts // [])[] | select(.aid == $aid) | .roles)}'
```

`accounts[]` only lists the accounts the caller can see, so it is not a full picture of the user's access elsewhere.

## Roles

- **Read the account's role list, don't hardcode it.** An account package can replace the whole default role set, so the valid slugs differ per account. Offer only `roles_available` entries with `can_be_assigned: true`.
- Role `type` is `composite`, `base`, or `additional`. Two main families: legacy bundles (`type: "composite"`, e.g. `admin`, `marketer`, `data_manager`, `observer`) and granular `v2_*` roles (`type: "base"`), mostly in `view`/`manage` pairs (`v2_segment_view` / `v2_segment_manage`, `v2_flow_view` / `v2_flow_manage`, ...). `manage` is the read/write half of a pair.
- `authed2` is the baseline role. The server adds it to every user-account role list, so it is always present and never needs sending.
- **The server does not validate role slugs on users.** A misspelled slug is stored as-is and grants nothing. Check every slug against `roles_available` before writing.

## Writes

Every write goes through `references/confirmation-gate.md`. In the summary, show the user's **current** roles on this account next to the proposed ones.

### Set a user's roles

```bash
curl -sS -w '\n%{http_code}\n' -X POST \
  "${LYTICS_API_URL:-https://api.lytics.io}/v2/user/$(jq -rn --arg v "$USER_KEY" '$v|@uri')/roles" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: application/json" \
  --data-binary '["v2_segment_view","v2_flow_manage"]'
```

- Body is a bare JSON array of slugs. `{id-or-email}` in the path.
- **Full replace** of the user's roles on this account. To add one role, send the current list plus the new one. An empty array is rejected with 400.
- 404 if the user is not already on this account; this endpoint never adds anyone.
- Read back with `GET /v2/user/{id}` and confirm this account's `roles`.

### Invite or add a user

`POST /v2/user` with `{"email": "...", "name": "...", "roles": ["..."]}`. Add `?suppress=true` to skip the invitation email.

- 201 = a new Lytics user was created; 200 = an existing user (by email) was added to this account.
- **The same roles are also written on every child account** of the current account. Say so in the confirmation summary when the account has children (`GET /v2/account` lists the family).
- **Do not use it on someone already on this account.** It resets their roles here (and on the child accounts) to the roles in the body, or to only `authed2` when `roles` is omitted. To change a member's roles, use the roles endpoint above.

### Remove a user from the account

`DELETE /v2/user/{id-or-email}` returns 204.

- Removes access to **this account only**. If the user then has no accounts left, **the user record itself is deleted**. Neither step can be undone: getting them back means a new invite and re-entering their roles.
- The API has no last-admin check. Before confirming, list the users and refuse if the removal (or a role change that drops `admin`) would leave no user with `admin` on the account.
- Refuse to remove, or drop `admin` from, the caller (`GET /v2/user/me`) unless the user explicitly asks for exactly that: it can lock them out of managing the account.
- In the confirmation, state plainly: "This removes <email> from <account> and cannot be undone." List the roles they will lose.
