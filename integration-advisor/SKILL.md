---
name: integration-advisor
description: Strategic guidance for setting up the right data integration -- workflow selection, field mapping, and configuration. Use when the user needs help choosing the right integration approach, wants advice on field mapping, or needs to plan a data integration.
metadata:
  arguments: description of the desired integration or platform name
---

# Integration Advisor

## Purpose
Guides users from "I want to connect X" to a fully configured, running integration. Goes beyond basic CRUD to advise on which workflow to use, how to map fields intelligently, and how to configure the integration for their specific use case. Lytics has 110+ providers with different auth methods, config shapes, and field mapping patterns -- the advisor navigates this complexity.

Supports:
- **Exports**: "Export my high-value audience to Facebook Custom Audiences"
- **Imports**: "Import contacts from Salesforce"
- **Enrichment**: "Enrich profiles with Clearbit data"

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Integration Architecture

Integrations follow a three-layer model:
```
Provider -- what platform
  → Auth -- how to authenticate
    → Connection -- optional, for data source integrations
      → Job -- what to do, runs a specific workflow
```

## Flow

### Step 1: Understand the Goal

Classify the user's intent:
- Platform name (Facebook, Salesforce, Google, etc.)
- Direction: import, export, or enrichment
- Data type: audiences, events, profiles, conversions
- Any specific segment references

### Step 2: Discover Provider

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/provider" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Find the matching provider by name. If ambiguous, show matching providers and ask user to select. Note whether the provider shows `is_connected: true` (auth already exists).

### Step 3: Check Existing Auth and Connections

```bash
# Check for existing auth credentials
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Check for existing connections
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

- If valid auth exists for this provider, plan to reuse it
- If a connection exists, check if it's suitable
- If no auth exists, guide the user based on auth method:

| Auth Method | Guidance |
|-------------|----------|
| OAuth2 | "You'll need to complete the OAuth flow in your browser. Go to Settings > Integrations > [Platform] in the Lytics UI to authorize. Once connected, I can set up the job." |
| API Key | "You'll need your API key from [Platform]. I can create the auth once you have it." |
| Credentials | "You'll need your username and password for [Platform]." |

**Important**: OAuth flows cannot be completed in the CLI. Always direct users to the Lytics UI for OAuth authorization, then pick up the created auth_id via the API.

### Step 4: Recommend Workflow

Each provider may have multiple workflows. Recommend the right one based on the user's goal:

If multiple workflows could apply, explain the tradeoffs:
> "Facebook has two export options:
> 1. **Custom Audiences** -- syncs a segment as a Facebook audience for ad targeting
> 2. **Conversion API** -- sends conversion events for attribution
>
> For your goal of retargeting lapsed users, Custom Audiences is the right choice."

### Step 5: Analyze Field Mappings

**For exports** -- cross-reference Lytics schema against the target platform's accepted fields:

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/user/field" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Suggest mappings based on field name similarity and type compatibility. Check field coverage in the target segment to predict match rates:

> "I'll map these Lytics fields to Facebook:
> - `email` -> EMAIL (92% coverage -- good for match rates)
> - `first_name` -> FN (85% coverage)
> - `last_name` -> LN (85% coverage)
> - `phone` -> PHONE (45% coverage -- supplementary matches)"

**For imports** -- scan the external data source schema:

```bash
# List tables in the connection
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}/schema" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Get column schema for a specific table
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}/schema/${TABLE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

# Sample data to verify
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}/scan" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT * FROM table LIMIT 5", "primary_keys": ["user_id"]}'
```

Suggest field mappings from external columns to Lytics schema fields:
- Auto-match by name similarity (e.g., `email_address` -> `email`)
- Flag potential identity fields (email, user_id, phone)
- Warn about unmapped fields and suggest whether to include them

### Step 6: Check Segment (for exports)

If the user mentioned a segment, verify it exists:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

If no segment specified for an export, suggest:
> "You'll need a segment to export. Would you like me to help you build one? I can analyze your data and recommend the best audience for your goal."
Then hand off to `audience-advisor skill` or `audience-builder skill`.

### Step 7: Build Job Config and Confirm

Assemble the complete job configuration and present using the confirmation-gate pattern:

```
## Proposed Integration: Export High-Value Users to Facebook Custom Audiences

**Workflow**: facebook_custom_audiences
**Auth**: Facebook OAuth (connected as marketing@acme.com)
**Segment**: High Value Customers (12,400 users)

**Field Mappings**:
  email -> EMAIL
  first_name -> FN
  last_name -> LN

**Schedule**: Continuous sync
```

Then show the raw API payload:
```json
{
  "name": "Export High Value to Facebook",
  "workflow": "facebook_custom_audiences",
  "config": {
    "segment_id": "abc123",
    "field_mappings": { ... }
  },
  "auth_ids": ["auth_456"]
}
```

### Step 8: Execute on Approval

Create resources in dependency order:
```bash
# Create job
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${WORKFLOW}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... approved config ... }'
```

For imports that need a new connection, create the connection first:
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... connection config ... }'
```

### Step 9: Verify

After creation, check job status:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"

curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/job/${JOB_ID}/logs" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Report initial status and suggest monitoring:
> "Job created and running. Initial status: active. Check back in a few minutes for first sync results, or ask me to check job status later."

## Common Integration Patterns

| Goal | Workflow Type | Key Config |
|------|--------------|------------|
| Retarget audience in ads | Export - Custom Audiences | segment_id, field mappings |
| Send conversion events | Export - Conversion API | event mappings, pixel/tag ID |
| Import CRM contacts | Import - Contact sync | object type, field mappings, identity field |
| Import behavioral events | Import - Event stream | event type, timestamp field |
| Sync to email platform | Export - List sync | segment_id, list ID, field mappings |
| Warehouse export | Export - Table write | dataset, table, write mode, partition |

## Field Mapping Heuristics

Common Lytics-to-platform field mappings:

| Lytics Field | Facebook | Google Ads | Salesforce | General |
|-------------|----------|------------|------------|---------|
| `email` | EMAIL | hashedEmail | Email | email |
| `first_name` | FN | firstName | FirstName | first_name |
| `last_name` | LN | lastName | LastName | last_name |
| `phone` | PHONE | hashedPhone | Phone | phone |
| `country` | COUNTRY | countryCode | MailingCountry | country |
| `city` | CT | city | MailingCity | city |
| `zip` | ZIP | zipCode | MailingPostalCode | postal_code |

## Error Handling
- **Provider not found**: List similar providers, ask user to clarify
- **No auth exists**: Guide to Lytics UI for OAuth, or help create API key auth
- **Auth expired**: Suggest re-authorizing in the Lytics UI
- **No matching workflow**: List available workflows for the provider
- **Segment not found**: Suggest creating one with audience-builder or audience-advisor
- **Connection scan fails**: Check auth credentials, network access to external system
- **Job creation fails**: Parse error, check required config fields

## Dependencies
- Composes: `connection-manager skill`, `job-manager skill`, `schema-discovery skill`, `../references/confirmation-gate.md`
- Related: `audience-advisor skill`, `audience-builder skill` (for creating segments to export)
