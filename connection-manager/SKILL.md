---
name: connection-manager
description: Browse and manage connections, auth providers, and integration credentials. Use when the user wants to list, view, create, or manage API connections, auth providers, or integration credentials.
metadata:
  arguments: action and relevant parameters -- list-connections, get-connection, create-connection, list-auth, create-auth
---

# Connection Manager

## Purpose
Browse and manage connections (external system configurations) and auth providers (credentials/tokens). Connections define how Lytics communicates with external platforms.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## API Endpoints

### Connections
```bash
# List all connections
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get connection
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Create connection
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... connection config ... }'

# Update connection
curl -s -X PUT "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... updated config ... }'

# Delete connection
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Scan connection (discover available data)
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}/scan" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get connection schema
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}/schema" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get connection table schema
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}/schema/${TABLE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Auth Providers
```bash
# List all auth providers
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get auth by ID
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth/${AUTH_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get auth by type and ID
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth/${TYPE}/${AUTH_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Create auth
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth/${TYPE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... auth credentials ... }'

# Update auth
curl -s -X PUT "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth/${TYPE}/${AUTH_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... updated credentials ... }'

# Delete auth
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth/${AUTH_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Providers (available integration types)
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/provider" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

## Behavior

### For Read Operations (list, get, scan)
Execute immediately. Display connections in a table format showing:
- Connection ID, name, type, status, last used

### For Write Operations (create, update, delete)
Use the confirmation-gate pattern. Auth credentials are sensitive -- never log or display full credential values.

### Connection Discovery Flow
When setting up a new integration:
1. List available providers (`GET /v2/provider`)
2. Create auth for the chosen provider
3. Create connection using the auth
4. Scan connection to discover available data
5. Review connection schema

## Error Handling
- **Auth expired**: Suggest re-creating the auth provider
- **Connection test failure**: Check auth credentials, network access
- **Provider not found**: List available providers

## Dependencies
- Uses: `../references/auth.md`, `../references/api-client.md`, `../references/confirmation-gate.md`
