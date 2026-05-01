---
name: auth
description: Authentication contract and deployment-specific credential resolution for all Lytics API skills
---

# Authentication

## Contract

Every Lytics API call requires an authenticated identity. How that identity is resolved depends on the deployment context. Skills must not hardcode a specific auth mechanism — they reference this contract and the runtime provides the credentials.

All authenticated requests include:
```
Authorization: <token>
```

## Deployment Contexts

### CLI (open-source / Claude Code)

Credentials come from environment variables set by the user before invoking a skill.

| Variable | Required | Description |
|----------|----------|-------------|
| `LYTICS_API_TOKEN` | yes | API authentication token ([how to create one](https://docs.lytics.com/docs/access-tokens)) |
| `LYTICS_API_URL` | no | Base URL (default: `https://api.lytics.io`) |

Pre-flight check (router skills only):
```bash
if [ -z "$LYTICS_API_TOKEN" ]; then
  echo "LYTICS_API_TOKEN is not set. Please set it with: export LYTICS_API_TOKEN=your_token"
  exit 1
fi
```

### SaaS (in-app)

Auth is provided by the platform session. The runtime injects the token — skills must not prompt the user for credentials. `LYTICS_API_URL` is set by the platform to the appropriate internal endpoint.

### Multi-Agent

The orchestrator provides credentials via the agent's environment or execution context. Skills consume them the same way as CLI mode — through `LYTICS_API_TOKEN` / `LYTICS_API_URL` — but the values are injected by the orchestrator rather than set by the user.

### Multi-Account (account-sync)

When operating against two accounts simultaneously, credentials are resolved per-account from a profile config file rather than from the session environment.

**Path:** `~/.lytics/accounts.toml`

```toml
[sandbox]
token = "lyt_xxx"
url = "https://api.lytics.io"   # optional; defaults to https://api.lytics.io

[prod]
token = "lyt_yyy"
```

Profile names are user-chosen; `sandbox` and `prod` are conventions, not requirements.

**Fallback:** if the file is missing, unreadable, or the requested profile name is not found, prompt the user to paste the token for that profile in-session. Session-only; never persist a prompted token.

**Per-call env overrides:** when making API calls, export `LYTICS_API_TOKEN` / `LYTICS_API_URL` for the active profile in a subshell:

```bash
LYTICS_API_TOKEN="$SRC_TOKEN" LYTICS_API_URL="$SRC_URL" \
  curl -s "${LYTICS_API_URL}/v2/segment/${SEGMENT_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

This keeps per-call behavior compatible with `api-client.md` while supporting two accounts in one run.

## Rules

- Never persist a user-prompted token to disk.
- Never log or display full token values.
- On 401 (CLI context): tell the user to check `LYTICS_API_TOKEN`.
- On 401 (SaaS context): report a session authentication error.
