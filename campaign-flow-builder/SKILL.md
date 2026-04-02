---
name: campaign-flow-builder
description: Guided flow/journey creation from business intent -- multi-step campaigns with delays, conditionals, A/B tests, and exports. Use when the user wants to create a campaign, build a journey, or design a multi-step marketing flow.
metadata:
  arguments: description of the desired campaign or journey
---

# Campaign Flow Builder

## Purpose
Guides users from business intent ("I want a welcome email series") to a complete, validated flow with entry segments, delays, conditional branches, A/B tests, and export steps. Follows the advisor pattern: understand the goal, suggest structure, iterate, then create.

Flows are the most complex Lytics object -- this skill makes them approachable.

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Flow API Format

Flows use a **node-edge graph** representation (TranslatedFlow format):
- **Nodes**: Steps in the journey (trigger, delay, export, conditional, A/B test, exit)
- **Edges**: Connections between steps (with optional conditions or probabilities)

## Building a Flow

### Step 1: Understand the Campaign Goal

Classify the user's intent:
- "Welcome email series" -> trigger on segment entry, delays between emails
- "Re-engagement campaign" -> trigger on lapsed users, conditional check, export
- "A/B test two offers" -> trigger, A/B split, two export paths
- "Multi-channel nurture" -> trigger, delays, conditionals, multiple export channels

Ask:
- What triggers entry? (entering a segment, being in a segment)
- How many steps/touchpoints?
- Any branching logic? (VIP vs standard, engaged vs not)
- What timing between steps?
- Can users re-enter?

### Step 2: Verify Entry Segment

The flow needs a trigger segment. Check if it exists:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

If no suitable segment exists, suggest using `audience-builder skill` or `audience-advisor skill` to create one.

### Step 3: Design the Flow Structure

Present a visual text diagram of the proposed flow:

```
TRIGGER: On entry to "New Signups" segment
  |
  v
[Send Welcome Email] (export)
  |
  v
[Wait 3 days] (delay)
  |
  v
[Opened Welcome?] (conditional split)
  |           |
  YES         NO
  |           |
  v           v
[Send Offer] [Send Reminder]
  |           |
  v           v
[EXIT]       [EXIT]
```

Iterate with the user until they're happy with the structure.

### Step 4: Build the Flow Payload

#### Node Types

**Trigger (always sequence_id: 0):**
```json
{
  "sequence_id": 0,
  "type": "trigger",
  "entry_segment_id": "segment-uuid-here",
  "entry_condition": "on_segment_entry",
  "reentry_allowed": false,
  "reentry_delay": 86400
}
```

Entry conditions:
- `"on_segment_entry"` -- fires when user enters the segment (event-based, most common)
- `"in_segment"` -- fires for users currently in the segment (snapshot)

Reentry delay is in **seconds**. Minimum is 3600 (1 hour).

**Export (send to external platform):**
```json
{
  "sequence_id": 1000,
  "type": "export",
  "label": "Send Welcome Email",
  "work_config": {}
}
```
The `work_config` is configured separately after flow creation via the work endpoint.

**Delay (wait between steps):**
```json
{
  "sequence_id": 2000,
  "type": "delay",
  "label": "Wait 3 days",
  "delay": 259200000000000
}
```
Delay is in **nanoseconds**. Common values:
- 1 hour: `3600000000000`
- 24 hours: `86400000000000`
- 3 days: `259200000000000`
- 7 days: `604800000000000`

Optional: `delay_condition` (FilterQL) -- proceed only when condition is met.
Optional: `delay_until_enters` (array of segment IDs) -- wait until user enters all listed segments.

**Conditional Split (if/else branching):**
```json
{
  "sequence_id": 3000,
  "type": "conditional_split",
  "label": "Opened Welcome?"
}
```
Conditions are defined on the **edges**, not the node. See Edges section.

**A/B Test (random split):**
```json
{
  "sequence_id": 4000,
  "type": "ab_test",
  "label": "50/50 Test"
}
```
Probabilities are defined on the **edges**. Must sum to 1.0.

**Exit (end of flow):**
```json
{
  "sequence_id": 9999,
  "type": "exit"
}
```

#### Edge Types

**Simple connection:**
```json
{"id": "0-1000", "source": 0, "target": 1000, "type": "connected"}
```

**Conditional split edge (with FilterQL):**
```json
{
  "id": "3000-4000",
  "source": 3000,
  "target": 4000,
  "type": "connected",
  "condition": {
    "definition": "FILTER AND (email_opened = true) FROM user",
    "label": "Yes",
    "priority": 2
  }
}
```
Higher priority numbers are checked first. The default/fallback edge should have `"definition": ""` and `"priority": 1`.

**A/B test edge (with probability):**
```json
{
  "id": "4000-5000",
  "source": 4000,
  "target": 5000,
  "type": "connected",
  "probability": 0.5
}
```
All probabilities from the same source node must sum to 1.0.

#### Step ID Assignment

- Trigger is always `sequence_id: 0`
- All other IDs are caller-assigned positive integers (must be unique within the flow)
- Convention: use multiples of 1000 (1000, 2000, 3000) for readability

### Step 5: Confirm and Create

Use the confirmation-gate pattern. Show:
- Flow diagram (text visual)
- Entry segment name and size
- Step count and types
- Timing summary
- Raw API payload

```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... flow payload ... }'
```

### Step 6: Configure Export Steps

After the flow is created in draft state, configure the work/export for each export step:

```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}/step/${STEP_ID}/work" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ ... work configuration ... }'
```

Then publish the work:
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}/step/${STEP_ID}/work/publish" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

### Step 7: Activate the Flow

Once all export steps have published work, activate the flow:
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"state": "running"}'
```

**Important**: Only one version of a flow can be `running` at a time. Publishing a new version automatically sets the old one to `draining`.

## Common Campaign Patterns

### Welcome Series
```
TRIGGER (on_segment_entry: "New Signups")
  -> [Send Welcome] -> [Wait 3d] -> [Send Tips] -> [Wait 7d] -> [Send Offer] -> EXIT
```

### Re-engagement
```
TRIGGER (in_segment: "Lapsed 30d")
  -> [Send Win-Back] -> [Wait 7d]
  -> CONDITIONAL (opened email?)
     YES -> [Send Discount] -> EXIT
     NO  -> [Send Final Notice] -> EXIT
```

### A/B Test
```
TRIGGER (on_segment_entry: "Trial Users")
  -> [Wait 1d]
  -> A/B TEST (50/50)
     A -> [Send Offer A] -> EXIT
     B -> [Send Offer B] -> EXIT
```

### Multi-Channel Nurture
```
TRIGGER (on_segment_entry: "High Intent")
  -> [Send Email] -> [Wait 2d]
  -> CONDITIONAL (converted?)
     YES -> EXIT
     NO  -> [Push Notification] -> [Wait 3d]
           -> [Retarget on Facebook] -> EXIT
```

## Flow States

| State | Description | Can Edit? |
|-------|------------|-----------|
| `draft` | Not active, fully editable | Yes -- add/remove/modify steps |
| `running` | Active, processing users | Limited -- can update work_config, labels, conditions; cannot add/remove steps |
| `draining` | Winding down, no new entries | Same as running |
| `deleted` | Permanently deleted | No |

## Error Handling
- **Invalid FilterQL in conditions**: Validate conditions before creating the flow
- **Probabilities don't sum to 1.0**: Adjust and retry
- **Entry segment not found**: Help create one with audience-builder
- **Duplicate step IDs**: Regenerate with unique values
- **Missing work config**: Guide through export step configuration

## Dependencies
- Composes: `segment-manager skill`, `audience-builder skill`, `job-manager skill`
- References: `../references/filterql-grammar.md`, `../references/confirmation-gate.md`, `../references/api-client.md`
