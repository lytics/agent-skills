# Settings

Read or change account settings on the current account. For copying settings between accounts, use [sync-settings.md](sync-settings.md) instead; its endpoint, response-shape, and write-workflow sections apply here too.

## Endpoints

`/api/account/setting` (singular, `/api/` not `/v2/`), so errors are in `.message` (`references/api.md`).

| Call | Effect |
|---|---|
| `GET /api/account/setting` | Every public setting: `slug`, `category`, `sub_category`, `value`, `field` (type, label, description), `can_be_assigned` |
| `GET /api/account/setting/{slug}` | One setting |
| `PUT /api/account/setting/{slug}` | Set it. Body is the raw JSON value (`true`, `"finance"`, `["a","b"]`, `500`), not an object |
| `DELETE /api/account/setting/{slug}` | Reset it to unset (204) |

```bash
curl -sS -w '\n%{http_code}\n' -X PUT "${LYTICS_API_URL:-https://api.lytics.io}/api/account/setting/${SLUG}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: application/json" --data-binary 'true'
```

- `can_be_assigned: false` means read-only: a PUT or DELETE returns `403 This setting "<slug>" is not editable, talk to your account manager.` Don't attempt it.
- An unknown slug returns 404. A value that does not match `field.type` returns 400. `400 Field <slug> is immutable.` means no one can change it through the API.
- Read the setting back after every write and confirm `.value` (the server may transform values).
- Side effects (query reloads, content affinity sync, jstag cache flush): see "Write workflow per-setting" in [sync-settings.md](sync-settings.md).

## High-risk settings

Each of these goes through `references/confirmation-gate.md` **and** a retype gate: after the `yes`, the user must type exactly `confirm <slug>`. Any other answer cancels.

| Setting | Risk |
|---|---|
| `api_ip_whitelist` (category `API`, list of CIDR ranges) | Once set, **every authenticated request from an IP outside the list gets `403 Not authorized`**, UI users and this session's own token included, and a locked-out caller cannot change it back. Ask the user for the egress IPs of every client (including this machine) and confirm they are in the list. Clearing it is a `DELETE`. |
| Category `security`: `enforce_two_factor_auth`, `enforce_password_complexity`, `enforce_password_history`, `enforce_password_maxbad`, `password_maxage_days`, `logon_session_days`, `security_session_timeout` | Change how every user of the account logs in; enabling 2FA or lockout rules can keep users out until they comply. |
| `cull_user_filter` | Profiles matching it are dropped from the account nightly. |
| `enable_schema_patches` | Never PUT it. Switching on goes through `POST /v2/schema/patch/migrate` (the `lytics-schema` skill). |

In the summary, show the current value next to the proposed one, and for `api_ip_whitelist` list every range being added and removed.
