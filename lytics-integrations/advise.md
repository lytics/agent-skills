# Advise

Use when the user needs to choose an integration approach, pick a workflow, or plan field mappings -- e.g. "export my high-value audience to Facebook Custom Audiences", "import contacts from Salesforce", "enrich profiles with Clearbit data". Lytics has 110+ providers with different auth methods, config shapes and field mapping patterns; this mode navigates that. When the plan is agreed, continue in `setup.md`.

## 1. Understand the goal

Classify the intent:
- Platform name (Facebook, Salesforce, Google, ...)
- Direction: import, export, or enrichment
- Data type: audiences, events, profiles, conversions
- Any segment the user referenced

## 2. Discover the provider

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/provider" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Find the matching provider by name. If ambiguous, show the matches and ask. Note whether it shows `is_connected: true` (auth already exists). Not found: list similar providers and ask the user to clarify.

## 3. Check existing auth and connections

`GET /v2/auth` and `GET /v2/connection`.

- Valid auth for this provider: plan to reuse it.
- A connection exists: check whether it's suitable.
- No auth: guide by auth method.

| Auth method | Guidance |
|---|---|
| OAuth2 | "You'll need to complete the OAuth flow in your browser. Go to Settings > Integrations > [Platform] in the Lytics UI to authorize. Once connected, I can set up the job." |
| API key | "You'll need your API key from [Platform]. I can create the auth once you have it." |
| Credentials | "You'll need your username and password for [Platform]." |

OAuth flows cannot be completed in the CLI: always direct the user to the Lytics UI, then pick up the created `auth_id` via the API. Expired auth: suggest re-authorizing in the Lytics UI.

## 4. Recommend a workflow

A provider may have several workflows. Recommend one for the user's goal and explain the tradeoff when more than one could apply:

> "Facebook has two export options:
> 1. **Custom Audiences** -- syncs a segment as a Facebook audience for ad targeting
> 2. **Conversion API** -- sends conversion events for attribution
>
> For your goal of retargeting lapsed users, Custom Audiences is the right choice."

No matching workflow: list the workflows the provider has.

| Goal | Workflow type | Key config |
|---|---|---|
| Retarget audience in ads | Export - Custom Audiences | segment_id, field mappings |
| Send conversion events | Export - Conversion API | event mappings, pixel/tag ID |
| Import CRM contacts | Import - Contact sync | object type, field mappings, identity field |
| Import behavioral events | Import - Event stream | event type, timestamp field |
| Sync to email platform | Export - List sync | segment_id, list ID, field mappings |
| Warehouse export | Export - Table write | dataset, table, write mode, partition |

## 5. Analyze field mappings

**Exports** -- cross-reference the Lytics schema (`GET /v2/schema/user/field`) against the target platform's accepted fields. Suggest mappings by name similarity and type compatibility, and check field coverage in the target segment to predict match rates:

> "I'll map these Lytics fields to Facebook:
> - `email` -> EMAIL (92% coverage -- good for match rates)
> - `first_name` -> FN (85% coverage)
> - `phone` -> PHONE (45% coverage -- supplementary matches)"

Common mappings:

| Lytics field | Facebook | Google Ads | Salesforce | General |
|---|---|---|---|---|
| `email` | EMAIL | hashedEmail | Email | email |
| `first_name` | FN | firstName | FirstName | first_name |
| `last_name` | LN | lastName | LastName | last_name |
| `phone` | PHONE | hashedPhone | Phone | phone |
| `country` | COUNTRY | countryCode | MailingCountry | country |
| `city` | CT | city | MailingCity | city |
| `zip` | ZIP | zipCode | MailingPostalCode | postal_code |

**Imports** -- scan the external source's schema (endpoints in `connections.md`): list tables with `GET /v2/connection/{id}/schema`, columns with `GET /v2/connection/{id}/schema/{table}`, and sample rows with a scan:

```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection/${CONNECTION_ID}/scan" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT * FROM table LIMIT 5", "primary_keys": ["user_id"]}'
```

Then map external columns to Lytics fields:
- Auto-match by name similarity (e.g. `email_address` -> `email`).
- Flag potential identity fields (email, user_id, phone).
- Warn about unmapped fields and suggest whether to include them.

Scan fails: check the auth credentials and network access to the external system.

## 6. Check the segment (exports)

If the user named a segment, verify it exists: `GET /v2/segment?table=user&sizes=true`. If none was named, or it doesn't exist:

> "You'll need a segment to export. Would you like me to help you build one? I can analyze your data and recommend the best audience for your goal."

and hand off to the `lytics-audiences` skill.

## 7. Present the plan

Summarize workflow, auth, segment (with size), field mappings and schedule, e.g.:

```
## Proposed Integration: Export High-Value Users to Facebook Custom Audiences

**Workflow**: facebook_custom_audiences
**Auth**: Facebook OAuth (connected as marketing@acme.com)
**Segment**: High Value Customers (12,400 users)
**Field Mappings**: email -> EMAIL, first_name -> FN, last_name -> LN
**Schedule**: Continuous sync
```

Then build the payloads, gate, create and verify as in `setup.md`.
