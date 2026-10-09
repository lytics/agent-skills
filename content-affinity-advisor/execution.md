# Execution: carrying out an advisement plan

Input is a plan file from `advise`. Only actions with `status: approved` run. Run them in plan order and respect `depends_on`. Endpoint details and setting keys are in `api-notes.md`.

## Rules for every action
1. **Pre-check.** Re-read the current state; it may have changed since the assessment. If the action is already done, mark it `done` and skip it. If the state conflicts with the plan, stop and ask.
2. **Dependency check.** Before blocking a topic or changing or deleting an Affinity, search user segments and flows for references to it (`GET /api/segment?table=user`, `GET /v2/flow/ui`). List anything affected in the confirmation summary.
3. **Snapshot.** Save the current value (setting, config, Affinity, rule, or page topics) to `content-exec-<account>-<YYYY-MM-DD>/before/<action id>.json`.
4. **Confirm.** Use `../references/confirmation-gate.md`: plain-language summary, then the exact request, then wait for yes or no. Each high-risk action gets its own confirmation; low-risk actions of the same type may be confirmed together if the user asks.
5. **Execute,** then record the response in `after/<action id>.json`.
6. **Update the plan:** `status: done` (or `failed`, with the error), and the date.
7. **Rollback note.** Record how to undo the action, using the snapshot.

### Dry-run / script mode
If `--dry-run` is set, the token is read-only, or the user prefers to run changes themselves, do not call write endpoints. Instead, generate `content-exec-<account>-<YYYY-MM-DD>.sh` that:
- reads `LYTICS_API_TOKEN` / `LYTICS_API_URL` from the environment (never embed a token)
- is **dry-run by default** (prints each request) and only sends with `--apply`
- logs every request and response to a file
- is idempotent (re-reads current state and merges, rather than blindly overwriting)

## Playbooks

### `block_domains` / `block_paths` / `block_pages` / `allow_params`
- **Setting keys:** `content_blacklist_domains`, `content_blacklist_paths`, `content_blocked_pages`, `content_allowed_params`.
- **Merge, don't replace.** Read the current value, add the new entries, de-duplicate, then write the full list:
```bash
curl -s "${LYTICS_API_URL}/api/account/setting/content_blacklist_domains" -H "Authorization: ${LYTICS_API_TOKEN}"
curl -s -X PUT "${LYTICS_API_URL}/api/account/setting/content_blacklist_domains" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: application/json" \
  -d '["admin.example-agency.com","preprod.example.com"]'
```
- **Effect:** this stops *new* collection. Pages already in the content table stay there. Their topics keep contributing until the page is re-classified, or the topics are zeroed on that page.
- **Verify:** no new docs from those hosts or paths in a later scan.

### `block_topics`
- **Where:** use whichever list the customer already uses.
  - Account setting `topic_blacklist`.
  - Or the layer's `blacklisted_topics` (`PUT /api/content/config/:id` with the merged list).
  - If both are empty, prefer the layer config for a non-default layer, and the account setting for the default layer.
- **Dependencies:** check for Affinities and audiences that use the topic. If one does, the plan must already include the matching Affinity or audience update.
- **Verify:** after the next topic-matrix rebuild (~24h), the topic is gone from `/api/content/topic`. Profiles drop it as they update.

### `allow_topics`
- Same as `block_topics`, using `topic_whitelist` or the layer's `whitelisted_topics`.
- Publishing an Affinity on the default layer already allowlists its topics, so don't duplicate those.

### `update_layer_config`
- `PUT /api/content/config/:id` with only the changed fields: `num_topics`, `explicit_affinities`, `inferred_affinities`, `use_activity_counts`, `limit_affinities`, `only_allowed_topics`.
- **High risk:** this changes how every profile on the layer is scored. Explain the before and after behaviour in plain language, and confirm on its own.

### `custom_topic_rule`
- `POST /v2/content/customtopic`:
```json
{"type":"filterql","filter_ql":"FILTER url CONTAINS \"/mortgages/\" FROM content","config_id":"<layer id>","topics":[{"label":"Mortgages","value":1.0}]}
```
- **Always set `value`.** It becomes the page's relevance for that topic, and 0 means the topic has no effect.
- Validate FilterQL on the content table first (`POST /api/segment/size` with `... FROM content` shows how many pages match).
- For URL-pattern rules (`"type":"url"`), test on one rule first. Create-time validation of URL patterns has not been verified (see `api-notes.md`).
- **Rules only apply when a page is classified.** Follow with `reclassify_pages` for existing pages.
- **To change a rule,** delete it and recreate it (there's no update).

### `page_topic_edit`
- Set: `POST /api/content/doc/hashedurl/<hashedurl>/topic/<Label>?relevance=1.0`
- Remove: `DELETE /api/content/doc/hashedurl/<hashedurl>/topic/<Label>` (zeroes it)
- Use `hashedurl` from the content scan. URL-encode labels.
- Only for a small, named set of high-value pages. If the plan lists more than ~25 pages, propose a custom topic rule instead.

### `reclassify_pages`
- `POST /api/content/doc/classify?url=<url>` for each page. This re-runs the classifiers, including custom topic rules, and saves the result.
- **Throttle.** One request at a time, a short pause between them. Stay well within the monthly classification cap (default 20,000), and tell the user how many classifications the batch will use.
- **Verify:** re-scan the affected pages; the expected topics are present.

### `create_affinity` / `update_affinity`
- **Optional first step:** get AI suggestions with `POST /v2/ai/supertopic/suggest?limit=20&config=<layer id>` (needs a create-scope token). Use each suggestion's `similar_to` to avoid overlapping an existing Affinity.
- **Create:** `POST /api/content/affinity`:
```json
{"label":"Mortgages","description":"Home buying and remortgaging interest","config_id":"<layer id>","topics":[{"label":"Mortgages","value":1},{"label":"Mortgage","value":1},{"label":"Remortgage","value":1}],"draft":true}
```
- **Create as a draft first** (`"draft": true`). Show the draft. Publish only on a separate confirmation, with `PUT /api/content/affinity/:id` and `"draft": false`. Publishing allowlists the topics and starts background re-evaluation.
- **Update:** read the current Affinity, change only the topics or weights, then `PUT`. Name the downstream audiences whose sizes will move.
- **Verify:** after a few days, size `FILTER lytics_rollup.\`<Label>\` >= 0.5 FROM user`, and check `/api/content/rollup/<Label>/urls` returns pages.

### `retire_affinity`
- **High risk.** Confirm no audience or flow references `lytics_rollup.<Label>`. If one does, the plan must update it first.
- `DELETE /api/content/affinity/:id`, after saving the snapshot.

### `create_audience` / `update_audience`
- **Hand off to `audience-builder skill`** with the plan's FilterQL, name and description. It handles validation, sizing and its own confirmation gate.
- Re-confirm the engagement-guard field exists (`schema-discovery skill`) before handing off.

### `activate`
Hand off to `integration-advisor skill` / `integration-setup skill` for exports, or `campaign-flow-builder skill` for journeys (it has an `affinity` routing step).

### `customer_site_spec` (no API)
Produce a short spec for the customer's web team:
- **Markup.** Which templates or pages get which `<meta name="lytics:topics" content="...">` values (comma-separated, matching canonical topic labels exactly).
- **Alternative.** If they'd rather use an existing CMS field or meta tag, note that `content_customprops` can read it; that's a Lytics-side change.
- **Rollout check.** How to confirm the tags are live (view source), and that pages will pick them up on their next classification.

### `support_request` (no API)
Draft the request for the customer's Lytics team, covering:
- `supported_languages` (non-English content)
- `enrich_content_sources`
- the monthly classification cap
- anything else marked staff-only in `api-notes.md`

Each request includes the account ID, the exact setting and value, and the evidence for it.

### `verify`
- After the re-scoring window (plan default: 14 days), run `assess` again with the same scope and diff it against the original evidence file.
- Report each target metric as before, after, and target.
- Mark the verify action `done`, and list follow-up actions for anything that didn't move.

## Report back
After a run, summarize in plain language:
- what changed
- what's waiting on time or on other people
- how to undo each change
- when to re-assess

Link the before and after snapshots and the updated plan.
