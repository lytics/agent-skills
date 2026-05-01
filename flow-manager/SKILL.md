---
name: flow-manager
description: Flow/journey CRUD and step management for campaign orchestration. Use when the user wants to list, view, create, update, or delete flows, journeys, or campaign steps.
metadata:
  arguments: action and relevant parameters -- list, get, create, update, delete, add-step
---

# Flow Manager

## Purpose
Manage flows (customer journeys/campaigns) -- create, update, delete flows and manage their steps including delays, exports, conditionals, A/B tests, and affinity routing.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## API Endpoints

### List Flows
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Get Flow
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Get Flow Version
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}/${VERSION}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Create Flow
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... flow payload ... }'
```

### Update Flow
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... updated flow payload ... }'
```

### Delete Flow
```bash
curl -s -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Create Work for Flow Step
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}/step/${STEP_ID}/work" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... work config ... }'
```

### List Flow States
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/state" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

## Flow Payload

```json
{
  "id": "flow_name",
  "label": "Display Name",
  "description": "What this flow does",
  "entry_segment_id": "segment_id",
  "entry_condition": "on_segment_entry",
  "reentry_allowed": false,
  "reentry_delay": "24h",
  "state": "draft",
  "steps": [
    {
      "id": 1,
      "label": "Step 1",
      "type_hint": "work_export",
      "slug": "step_1",
      "next": 2,
      "work_id": "work_id",
      "work_config": {}
    },
    {
      "id": 2,
      "label": "Wait 24 hours",
      "type_hint": "delay",
      "slug": "delay_step",
      "next": 3,
      "delay": "24h"
    }
  ]
}
```

## Flow States

| State | Description |
|-------|-------------|
| `draft` | Editable, not processing |
| `running` | Actively processing users |
| `draining` | Stopping gracefully, processing remaining users |
| `deleted` | Soft deleted |

## Entry Conditions

| Condition | Description |
|-----------|-------------|
| `in_segment` | Triggers for users currently in the segment |
| `on_segment_entry` | Triggers only when a user enters the segment |

## Step Types

| Type | Description | Key Fields |
|------|-------------|------------|
| `work_export` | Export to external system | `work_id`, `work_config` |
| `delay` | Wait before next step | `delay` (duration string) |
| `conditional` | Split by FilterQL condition | `split_conditions` |
| `affinity` | Route by content affinity | `split_affinities`, `affinity_config_id` |
| `ab_testing` | Random split by probability | `split_probabilities` |
| `work_export_exit` | Export on flow exit | `work_id`, `work_config` |

## Behavior

### For Read Operations
Execute immediately, display flow structure as a visual step chain.

### For Write Operations
Use the confirmation-gate pattern. For state changes (draft -> running, running -> draining), explicitly warn about the implications.

## Error Handling
- **Invalid entry segment**: Verify segment exists first
- **Invalid step references**: Ensure `next` IDs point to existing steps
- **State transition errors**: Only valid transitions are draft->running, running->draining

## Dependencies
- Uses: `../references/auth.md`, `../references/api-client.md`, `../references/confirmation-gate.md`
- Related: `segment-manager skill` (for entry segments), `job-manager skill` (for work steps)
