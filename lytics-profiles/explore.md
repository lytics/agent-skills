# Explore

Use for a comprehensive, interactive view of one profile: identity, attributes, segment memberships, and activity.

Input: an identity field and value (e.g. `email`, `user@example.com`), or an exploration query (e.g. "find a user in the high-value segment").

## Step 1: Fetch profile and memberships

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/$(jq -rn --arg v "$VALUE" '$v|@uri')?segments=true&allsegments=true&meta=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

Memberships alone: `GET /api/entity/user/segments/{field}/{value}`.

A 200 with `message: "Not Found"` and `{"segments": ["not_found", "all"]}` is a missing profile, not a real one (see `lookup.md`). Try alternative identity fields and suggest checking spelling.

## Step 2: Present a structured summary

```
## Profile: user@example.com

### Identity
- email: user@example.com
- user_id: 12345
- _uid: abc-def-ghi

### Key Attributes
- Name, Country, City, Created, Last Active

### Engagement
- Visit Count, Avg Visit Time, Content Affinity

### Segment Memberships (N)
- High Value Customers (segment)
- Email Subscribers (aspect)
- Q1 Campaign Target (list)

### Recent Events
[Summary from stream data if available]
```

- **Multiple identities**: show all linked identities, confirm which profile.
- **Large profile**: summarize key fields, offer the full details on request.

## Step 3: Follow-ups

- "What segments is this user in?" -> detailed segment list
- "Show me their purchase history" -> look up the relevant fields
- "Compare with another user" -> look up the second profile the same way
- "Why are they in segment X?" -> `investigate.md`
- "Where did this field come from?" -> `investigate.md` (data lineage)

## Finding a user without an identity

1. Ask what they're looking for.
2. Suggest listing members of a relevant segment (segment scan, via the `lytics-audiences` skill).
3. Help them pick the right profile, then continue from Step 1.
