# Manage

Use for existing flows: list, view, read a version, update, change state, delete, and list flow states. To design a new journey from scratch, use `build.md`.

## Endpoints

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Operation | Request |
|---|---|
| List flows | `GET /v2/flow/ui` |
| Get flow | `GET /v2/flow/ui/{FLOW_ID}` |
| Get one version | `GET /v2/flow/ui/{FLOW_ID}/{VERSION}` |
| Create flow | `POST /v2/flow/ui` (node/edge payload, see `build.md`) |
| Update flow | `POST /v2/flow/ui/{FLOW_ID}` (updated node/edge payload) |
| Activate | `POST /v2/flow/ui/{FLOW_ID}` with `{"state": "running"}` |
| Configure a step's work | `POST /v2/flow/ui/{FLOW_ID}/step/{STEP_ID}/work` |
| Publish a step's work | `POST /v2/flow/ui/{FLOW_ID}/step/{STEP_ID}/work/publish` |
| Delete every version | `DELETE /v2/flow/ui/{FLOW_ID}` -- **permanent, see below** |
| Delete one version | `DELETE /v2/flow/ui/{FLOW_ID}/{VERSION}` |
| List flow states | `GET /v2/flow/state` |

## Reads

Execute immediately. Display the flow as a visual step chain (trigger -> steps -> exits, with condition labels and priorities on each branch).

## Writes

All go through `references/confirmation-gate.md`.

- **Update**: write the node/edge (TranslatedFlow) format, never the internal `steps` model below. Before sending, check every edge's `source`/`target` is an existing `sequence_id`, condition FilterQL is valid, and no `ab_test` node or edge `probability` is relied on (it is ignored; one branch gets every user).
- **Condition priority**: lower numbers are checked first, first match wins; the fallback edge (`"definition": ""`, `"priority": 1`) is used only when nothing else matches. When editing conditions, re-check the order.
- **State changes**: valid transitions are `draft` -> `running` and `running` -> `draining`. Warn explicitly: `running` starts processing users; `draining` stops new entries while remaining users finish. Only one version can be `running`; publishing a new version automatically sets the old one to `draining`.
- **Delete**: `DELETE /v2/flow/ui/{FLOW_ID}` without a version hard-deletes **every version** of the flow, including a running one. There is no soft delete and no undo. Say so in the confirmation gate, and offer `DELETE /v2/flow/ui/{FLOW_ID}/{VERSION}` if the user only means one version.

```bash
curl -sS -w '\n%{http_code}\n' -X DELETE "${LYTICS_API_URL:-https://api.lytics.io}/v2/flow/ui/${FLOW_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

## Flow states

| State | Meaning | Editable? |
|---|---|---|
| `draft` | Not active, not processing | Yes: add/remove/modify steps |
| `running` | Actively processing users | Limited: can update `work_config`, labels, conditions; cannot add/remove steps |
| `draining` | Stopping gracefully: no new entries, remaining users processed | Same as `running` |
| `deleted` | Marked deleted. Not the result of `DELETE /v2/flow/ui/{FLOW_ID}`, which removes the flow outright | No |

## Entry conditions

| Condition | Meaning |
|---|---|
| `on_segment_entry` | Fires only when a user enters the segment (event-based) |
| `in_segment` | Fires for users currently in the segment (snapshot) |

## Errors to expect

- Entry segment invalid: verify it exists first (`GET /v2/segment`); create it with the `lytics-audiences` skill.
- Edge or step references a missing step: fix the IDs.
- State transition refused: only `draft` -> `running` and `running` -> `draining` are valid.
- Export step missing work config: configure and publish its work (see `build.md` Step 6).

## Reference: internal `/v2/flow` representation (read-only)

The internal flow model uses a `steps` array with `type_hint`. It is documented here only so you can recognise it when reading; **do not send it to `/v2/flow/ui`** -- writes use the node/edge format in `build.md`. Field names and units differ from the node/edge format (e.g. durations as strings like `"24h"` here vs seconds/nanoseconds there).

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
    {"id": 1, "label": "Step 1", "type_hint": "work_export", "slug": "step_1", "next": 2,
     "work_id": "work_id", "work_config": {}},
    {"id": 2, "label": "Wait 24 hours", "type_hint": "delay", "slug": "delay_step", "next": 3,
     "delay": "24h"}
  ]
}
```

| `type_hint` | Meaning | Key fields | Node/edge equivalent |
|---|---|---|---|
| `work_export` | Export to external system | `work_id`, `work_config` | `export` node |
| `delay` | Wait before next step | `delay` (duration string) | `delay` node (nanoseconds) |
| `conditional` | Split by FilterQL condition | `split_conditions` | `conditional_split` node + edge conditions |
| `affinity` | Route by content affinity | `split_affinities`, `affinity_config_id` | none documented for `/v2/flow/ui` |
| `ab_testing` | Random split by probability | `split_probabilities` | `ab_test` -- unsupported via `/v2/flow/ui` (probability ignored) |
| `work_export_exit` | Export on flow exit | `work_id`, `work_config` | none documented for `/v2/flow/ui` |

In this model, each step's `next` must point to an existing step `id`.
