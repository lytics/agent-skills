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

Pre-flight check, before the first API call of a task:
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

### Multi-Account (lytics-account sync)

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

**Per-profile calls:** never route a two-account call through `LYTICS_API_TOKEN` / `LYTICS_API_URL`. A prefix like `LYTICS_API_URL="$SRC_URL" curl "${LYTICS_API_URL}/..."` does not work: the shell expands `${LYTICS_API_URL}` in curl's arguments *before* the prefix assignment applies, so the call silently goes to whatever account is ambient. Name the profile's own variables in every call instead:

```bash
src() { p=$1; shift; curl -sS -H "Authorization: ${SRC_TOKEN:?SRC_TOKEN unset}" "$@" "${SRC_URL:?SRC_URL unset}${p}"; }
dst() { p=$1; shift; curl -sS -H "Authorization: ${DST_TOKEN:?DST_TOKEN unset}" "$@" "${DST_URL:?DST_URL unset}${p}"; }

src "/v2/segment/${SEGMENT_ID}"
dst /v2/segment -X POST -H "Content-Type: application/json" --data-binary @segment.json
```

The `:?` guards make a missing profile variable fail loudly instead of falling through to another account. Shell state may not persist between tool calls, so define the helpers and resolve `SRC_*` / `DST_*` in the same command that uses them. When a peer skill's snippet uses `${LYTICS_API_URL}` / `${LYTICS_API_TOKEN}`, rewrite it to `src` or `dst` before running it.

**Same-account guard:** before any write, resolve each profile's own aid and refuse to run if they match. `GET /v2/account` returns the token's account, or for a parent token the whole family, where the token's own account is the entry with `aid == parentaid`:

```bash
own_aid='.data | if length == 1 then .[0].aid else (map(select(.aid == .parentaid)) | .[0].aid) end'
SRC_AID=$(src /v2/account | jq -r "$own_aid")
DST_AID=$(dst /v2/account | jq -r "$own_aid")
case "$SRC_AID:$DST_AID" in
  *[!0-9:]*|:*|*:) echo "refusing: an account failed to resolve" ;;
  *) [ "$SRC_AID" != "$DST_AID" ] || echo "refusing: source and destination are the same account" ;;
esac
```

## Rules

- Never persist a user-prompted token to disk.
- Never log or display full token values.
- On 401 (CLI context): tell the user to check `LYTICS_API_TOKEN`.
- On 401 (SaaS context): report a session authentication error.
