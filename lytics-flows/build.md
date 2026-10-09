# Build

Use when the user describes a campaign or journey to create: go from business intent to a validated node/edge flow, create it, configure its export steps, and activate it. Follow the advisor pattern: understand the goal, suggest a structure, iterate, then create.

## Flow format

`/v2/flow/ui` takes a **node/edge graph** (TranslatedFlow format):
- **Nodes**: steps in the journey (trigger, delay, export, conditional split, exit).
- **Edges**: connections between steps, optionally carrying a condition. Edge `probability` is ignored.

## Step 1: Understand the campaign goal

Classify the intent:
- "Welcome email series" -> trigger on segment entry, delays between emails.
- "Re-engagement campaign" -> trigger on lapsed users, conditional check, export.
- "A/B test two offers" -> **not buildable here**: A/B split probabilities are ignored by the API (see A/B test below).
- "Multi-channel nurture" -> trigger, delays, conditionals, multiple export channels.

Ask:
- What triggers entry? (entering a segment, being in a segment)
- How many steps/touchpoints?
- Any branching logic? (VIP vs standard, engaged vs not)
- What timing between steps?
- Can users re-enter?

## Step 2: Verify the entry segment

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

If no suitable segment exists, hand off to the `lytics-audiences` skill to create one, then continue.

## Step 3: Design the structure

Present a text diagram and iterate until the user is happy:

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

## Step 4: Build the payload

### Nodes

**Trigger** (always `sequence_id: 0`):
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
- `entry_condition`: `"on_segment_entry"` fires when a user enters the segment (event-based, most common); `"in_segment"` fires for users currently in the segment (snapshot).
- `reentry_delay` is in **seconds**. Minimum 3600 (1 hour).

**Export** (send to an external platform):
```json
{"sequence_id": 1000, "type": "export", "label": "Send Welcome Email", "work_config": {}}
```
`work_config` is configured separately after the flow is created, via the work endpoint (Step 6).

**Delay** (wait between steps):
```json
{"sequence_id": 2000, "type": "delay", "label": "Wait 3 days", "delay": 259200000000000}
```
`delay` is in **nanoseconds**: 1 hour `3600000000000`, 24 hours `86400000000000`, 3 days `259200000000000`, 7 days `604800000000000`.
- Optional `delay_condition` (FilterQL): proceed only when the condition is met.
- Optional `delay_until_enters` (array of segment IDs): wait until the user enters all listed segments.

**Conditional split** (if/else):
```json
{"sequence_id": 3000, "type": "conditional_split", "label": "Opened Welcome?"}
```
Conditions live on the **edges**, not the node.

**A/B test** (`"type": "ab_test"`): **not supported through this API.** `/v2/flow/ui` ignores edge `probability`, so an `ab_test` node saves without error and then sends **every** user down a single branch. Do not build A/B splits; tell the user the split must be set up another way and verified before the flow runs.

**Exit**:
```json
{"sequence_id": 9999, "type": "exit"}
```

### Edges

Simple connection:
```json
{"id": "0-1000", "source": 0, "target": 1000, "type": "connected"}
```

Conditional split edge (FilterQL, see `references/filterql-grammar.md`):
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
**Lower** priority numbers are checked first, and the first matching condition wins, so give the most specific condition the smallest number. The default/fallback edge has `"definition": ""` and `"priority": 1`; it is taken out of the ordering and used only when no other condition matches.

### Step IDs

- Trigger is always `sequence_id: 0`.
- All other IDs are caller-assigned positive integers, unique within the flow.
- Convention: multiples of 1000 (1000, 2000, 3000) for readability.

### Validate before creating

- Every condition's FilterQL is valid.
- No duplicate step IDs (regenerate if so).
- The entry segment exists.
- No `ab_test` node and no edge relying on `probability`.

## Step 5: Confirm and create

Through `references/confirmation-gate.md`, show: the flow diagram, entry segment name and size, step count and types, timing summary, and the raw payload. Then:

```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary @flow.json
```

The flow is created in `draft` state.

## Step 6: Configure export steps

For each export step, configure its work, then publish it. If the export needs a connection or job set up first, use the `lytics-integrations` skill.

```
POST /v2/flow/ui/{FLOW_ID}/step/{STEP_ID}/work          (body: work configuration)
POST /v2/flow/ui/{FLOW_ID}/step/{STEP_ID}/work/publish
```

## Step 7: Activate

Once every export step has published work, activate (through the confirmation gate, warning that the flow starts processing users):

```
POST /v2/flow/ui/{FLOW_ID}
{"state": "running"}
```

Only one version of a flow can be `running` at a time. Publishing a new version automatically sets the old one to `draining`.

## Common campaign patterns

Welcome series:
```
TRIGGER (on_segment_entry: "New Signups")
  -> [Send Welcome] -> [Wait 3d] -> [Send Tips] -> [Wait 7d] -> [Send Offer] -> EXIT
```

Re-engagement:
```
TRIGGER (in_segment: "Lapsed 30d")
  -> [Send Win-Back] -> [Wait 7d]
  -> CONDITIONAL (opened email?)
     YES -> [Send Discount] -> EXIT
     NO  -> [Send Final Notice] -> EXIT
```

Multi-channel nurture:
```
TRIGGER (on_segment_entry: "High Intent")
  -> [Send Email] -> [Wait 2d]
  -> CONDITIONAL (converted?)
     YES -> EXIT
     NO  -> [Push Notification] -> [Wait 3d]
           -> [Retarget on Facebook] -> EXIT
```
