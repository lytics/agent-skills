---
name: lytics-agent
description: Top-level Lytics CDP agent - routes user intent to the appropriate skill for audience management, profile exploration, data integration, and schema browsing. Use when the user has a general Lytics question or request that doesn't clearly map to a specific skill.
metadata:
  arguments: natural language request about Lytics CDP operations
---

# Lytics Agent Router

## Purpose
Top-level intent classifier and dispatcher for Lytics CDP operations. Analyzes the user's request and routes to the appropriate specialized skill.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token (required)
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Pre-flight Check
Before routing, verify the environment is configured:
```bash
if [ -z "$LYTICS_API_TOKEN" ]; then
  echo "LYTICS_API_TOKEN is not set. Please set it with: export LYTICS_API_TOKEN=your_token"
  exit 1
fi
```

## Intent Classification

Route based on keywords and intent:

### Audience / Segment Operations
**Triggers**: "create audience", "build segment", "find users who", "people that", "customers who", "target audience", "audience of"
**Route to**: `audience-builder skill`

**Triggers**: "list segments", "show audiences", "get segment", "segment details", "delete segment", "update segment"
**Route to**: `segment-manager skill`

### Audience Analytics / Snapshot
**Triggers**: "describe audience", "audience snapshot", "what does segment look like", "audience breakdown", "analyze segment", "audience profile", "audience analytics", "audience demographics", "who is in this segment"
**Route to**: `audience-snapshot skill`

### Audience Strategy / Advisor
**Triggers**: "best audience for", "optimize audience", "help me target", "who should I target", "improve my segment", "audience strategy", "what audience should", "right audience for", "how to reach", "better audience", "refine segment"
**Route to**: `audience-advisor skill`

### Profile Diagnostics
**Triggers**: "why is user in", "why isn't user in", "why not in segment", "diagnose profile", "what happened to user", "debug segment membership", "explain segment", "trace user"
**Route to**: `profile-investigator skill`

### Profile / Entity Exploration
**Triggers**: "look up user", "find profile", "who is", "show me user", "profile for", "entity lookup"
**Route to**: `profile-explorer skill`

### Schema / Data Model
**Triggers**: "what fields", "schema", "data model", "field types", "available data", "what data do we have"
**Route to**: `schema-manager skill`

### Schema Optimization
**Triggers**: "optimize schema", "unused fields", "schema cleanup", "field usage", "schema health", "improve schema", "inert fields", "missing mappings"
**Route to**: `schema-optimizer skill`

### Schema Discovery (for field mapping)
**Triggers**: "find field for", "what field matches", "map to field"
**Route to**: `schema-discovery skill`

### Integration Strategy / Advisor
**Triggers**: "connect to", "set up integration", "export to", "import from", "sync with", "send data to", "pull data from", "best way to connect", "how do I integrate"
**Route to**: `integration-advisor skill`

### Data Integration / Jobs (existing)
**Triggers**: "list jobs", "job status", "pause job", "resume job", "bounce job", "kill job", "job logs"
**Route to**: `job-manager skill`

### Campaign / Journey Builder
**Triggers**: "create flow", "build campaign", "set up journey", "welcome series", "nurture campaign", "email sequence", "multi-step campaign", "A/B test flow"
**Route to**: `campaign-flow-builder skill`

### Flows CRUD
**Triggers**: "list flows", "get flow", "delete flow", "flow status", "update flow", "pause flow"
**Route to**: `flow-manager skill`

### Export Debugging
**Triggers**: "why wasn't user exported", "export debug", "not showing up in", "didn't sync to", "missing from export", "why no export", "trace export", "export failed"
**Route to**: `export-debugger skill`

### Data Health
**Triggers**: "data health", "is my data flowing", "health check", "any data issues", "pipeline status", "what's broken", "data problems", "check my data", "how's my data"
**Route to**: `data-health-monitor skill`

### Streams / Events
**Triggers**: "stream", "events", "data flowing", "incoming data", "event log"
**Route to**: `stream-inspector skill`

### Connections / Auth
**Triggers**: "connection", "auth", "credentials", "provider"
**Route to**: `connection-manager skill`

### Webhook Templates
**Triggers**: "webhook template", "send to a webhook", "custom webhook destination", "Qualtrics webhook", "Slack webhook", "transform profile to webhook payload", "build a webhook payload", "webhook integration for", "send profiles to a custom URL"
**Route to**: `webhook-template-builder skill`

### Cross-Account Sync / Promotion
**Triggers**: "copy from sandbox to prod", "promote to prod", "sync to prod", "copy segment to another account", "sandbox to production", "promote audience", "promote flow", "copy schema between accounts", "move segment from X to Y", "sync <anything> from <account> to <account>", "copy account settings", "promote settings", "sync settings between accounts", "copy idconfig", "sync account config", "promote account settings", "copy field rankings between accounts"
**Route to**: `account-sync skill`

## Multi-Intent Handling

Some requests combine multiple intents. Sequence skills in order:

- "Create an audience and export to Facebook"
  1. `audience-builder skill` -> create segment
  2. `integration-advisor skill` -> set up export with new segment

- "Find users in the high-value segment and show me one"
  1. `segment-manager skill` -> get segment details
  2. `profile-explorer skill` -> look up a member

- "What fields do we have for purchase data and build a segment from it"
  1. `schema-discovery skill` -> find purchase fields
  2. `audience-builder skill` -> build segment using discovered fields

- "Build a segment in sandbox and promote it to prod"
  1. `audience-builder skill` -> create segment in sandbox
  2. `account-sync skill` -> copy the new segment from sandbox to prod

## Disambiguation

If the intent is unclear:
1. Ask a clarifying question
2. Suggest the most likely interpretation
3. Offer alternatives

Example: "Show me data" could mean:
- Schema/fields -> schema-manager
- Stream events -> stream-inspector
- Profile data -> profile-explorer

Ask: "Would you like to see your schema fields, recent streaming events, or look up a specific profile?"

## Shared Conventions

All skills follow these conventions:
- **Auth**: `Authorization: $LYTICS_API_TOKEN` header on all API calls
- **Base URL**: `${LYTICS_API_URL:-https://api.lytics.io}`
- **Reads**: Execute immediately, display results
- **Writes**: Always use confirmation-gate pattern (summary + payload + approval)
- **Errors**: Parse API errors, suggest fixes, never silently fail
