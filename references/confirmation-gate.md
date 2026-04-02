---
name: confirmation-gate
description: Draft/confirm pattern for all write operations - shows summary and payload before executing
---

# Confirmation Gate

## Purpose
Every mutation (POST, PUT, DELETE) to the Lytics API must go through this confirmation pattern. This ensures the user sees exactly what will happen and approves before execution.

## Behavior

### Step 1: Build the Complete API Request
Construct the full request including:
- HTTP method and URL
- Headers (Authorization, Content-Type)
- Request body (JSON payload)

### Step 2: Present Human-Readable Summary
Show a clear summary of what will happen:

```
## Proposed Action: [Create/Update/Delete] [Resource Type]

**Name**: [resource name]
**Description**: [what this does]

[Additional context specific to the resource type, e.g.:]
- **Estimated audience size**: ~45,000 profiles
- **Filter logic**: US customers who haven't purchased socks in over a year
- **Field mappings**: country -> "US", products_purchased -> excludes "socks"
```

### Step 3: Present Raw API Payload
Show the exact API call that will be made:

```
POST ${LYTICS_API_URL}/v2/segment

{
  "name": "US Non-Sock Buyers",
  "slug_name": "us_non_sock_buyers",
  "segment_ql": "FILTER AND (...) FROM user ALIAS us_non_sock_buyers",
  "kind": "segment",
  "table": "user",
  "is_public": true,
  "description": "...",
  "tags": [...],
  "save_hist": true
}
```

### Step 4: Ask for Confirmation
Ask the user to confirm:
```
Proceed with this [creation/update/deletion]? (yes/no)
```

If modifications are requested, incorporate them and repeat from Step 2.

### Step 5: Execute on Approval
Only after explicit user approval:
1. Execute the API call
2. Parse the response
3. Report success or failure with the response data

### Step 6: Report Result
On success:
```
Successfully created segment "US Non-Sock Buyers" (id: abc123)
```

On failure:
```
Failed to create segment: [error message from API]
```

## Rules
- NEVER execute a write operation without showing the payload first
- NEVER skip the confirmation step
- If the user says "no" or requests changes, go back to Step 2
- For bulk operations, show each individual action
- For delete operations, emphasize the irreversibility

## Dependencies
- References: `foundation/api-client.md`
