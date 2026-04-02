---
name: profile-explorer
description: Interactive profile exploration combining lookup, segments, and event history. Use when the user wants to explore a user profile, view segment memberships, or browse event history for an identity.
metadata:
  arguments: identity to look up or exploration query
---

# Profile Explorer

## Purpose
Interactive profile exploration that combines identity lookup, segment membership analysis, and event history browsing. Provides a comprehensive view of an individual user profile.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Inputs
- Identity field and value (e.g., `email`, `user@example.com`)
- Or: exploration query (e.g., "find a user in the high-value segment")

## Exploration Flow

### Step 1: Look Up Profile
Use `entity-lookup skill`:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Step 2: Get Segment Memberships
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/entity/user/segments/${FIELD}/${VALUE}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Step 3: Present Profile Summary
Display a structured profile view:

```
## Profile: user@example.com

### Identity
- email: user@example.com
- user_id: 12345
- _uid: abc-def-ghi

### Key Attributes
- Name: Jane Smith
- Country: US
- City: Portland, OR
- Created: 2024-01-15
- Last Active: 2025-03-18

### Engagement
- Visit Count: 47
- Avg Visit Time: 3.2 min
- Content Affinity: Technology, Marketing

### Segment Memberships
- High Value Customers (segment)
- Email Subscribers (aspect)
- Q1 Campaign Target (list)

### Recent Events
[Summary from stream data if available]
```

### Step 4: Interactive Exploration
After presenting the summary, the user can:
- "What segments is this user in?" -> Show detailed segment list
- "Show me their purchase history" -> Look up relevant fields
- "Compare with another user" -> Look up second profile
- "Why are they in segment X?" -> Cross-reference segment FilterQL with profile data

## Finding Users

If the user doesn't have a specific identity:
1. Ask what they're looking for
2. Suggest searching by segment: list segment members using segment scan
3. Help them identify the right profile

## Error Handling
- **Profile not found**: Try alternative identity fields, suggest checking spelling
- **Multiple identities**: Show all linked identities, confirm which profile
- **Large profile**: Summarize key fields, offer to show full details on request

## Dependencies
- Composes: `entity-lookup skill`, `segment-manager skill`, `stream-inspector skill`
