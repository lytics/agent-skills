# Connections

Use to browse and manage connections (how Lytics talks to an external system), auth providers (credentials/tokens), and the list of available providers.

Reads (list, get, schema, scan) run immediately; show connections as a table of id, name, type, status, last used. Create, update and delete go through the confirmation gate. Auth credentials are sensitive: never log or display full credential values.

## Connections

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Operation | Request |
|---|---|
| List | `GET /v2/connection` |
| Get | `GET /v2/connection/{connection_id}` |
| Create | `POST /v2/connection` with the connection config |
| Update | `PUT /v2/connection/{connection_id}` with the updated config |
| Delete | `DELETE /v2/connection/{connection_id}` |
| Scan (discover available data) | `POST /v2/connection/{connection_id}/scan` -- optional body `{"query": "SELECT * FROM table LIMIT 5", "primary_keys": ["user_id"]}` to sample rows |
| List tables | `GET /v2/connection/{connection_id}/schema` |
| Table columns | `GET /v2/connection/{connection_id}/schema/{table}` |

Connection test or scan failure: check the auth credentials and network access to the external system.

## Auth providers

| Operation | Request |
|---|---|
| List | `GET /v2/auth` |
| Get by id | `GET /v2/auth/{auth_id}` |
| Get by type and id | `GET /v2/auth/{type}/{auth_id}` |
| Create | `POST /v2/auth/{type}` with the credentials |
| Update | `PUT /v2/auth/{type}/{auth_id}` with the updated credentials |
| Delete | `DELETE /v2/auth/{auth_id}` |

Send credential bodies from a file (`--data-binary @auth.json`, see `references/api.md`) so secrets don't land in shell history or the transcript. OAuth auth cannot be created from the CLI: the user authorizes in the Lytics UI (Settings > Integrations > [Platform]) and you pick up the new id from `GET /v2/auth`. Expired auth: suggest re-creating (or, for OAuth, re-authorizing) it.

## Providers

`GET /v2/provider` lists the available integration types; `is_connected: true` means auth already exists for that provider. Provider not found: list the available providers.

## Discovery flow for a new data-source integration

1. List providers (`GET /v2/provider`).
2. Create auth for the chosen provider.
3. Create a connection using that auth.
4. Scan the connection to discover available data.
5. Review the connection schema.
