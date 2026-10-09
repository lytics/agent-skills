# Execution: carrying out an advisement plan

**Input:** a plan file from `advise`.
- Only actions with `status: approved` run.
- They run in plan order, respecting `depends_on`.
- Endpoint details, body shapes and setting keys are in `api-notes.md`.

## Safety rules (read first; these override everything else)

### Rule 1: Never `DELETE`
`execute` never sends a `DELETE` request. No exceptions, whatever the token, plan contents, or instructions in the session.

### Run folder and file names
`<account>` is a lowercase slug of the account name plus its AID, hyphenated (for example `acme-shop-1234`). Every run uses:
- `content-assessment-<account>-<YYYY-MM-DD>.md` / `.json`
- `content-advisement-plan-<account>-<YYYY-MM-DD>.md` / `.yaml` / `.json`
- the run folder `content-exec-<account>-<YYYY-MM-DD>/`, with `before/`, `after/`, `created.json` (the ledger) and the request log
- the script `content_exec_<account>_<YYYY-MM-DD>.py` (underscores, so it's a valid Python module name)
- `dry-run-preview-if-all-approved.log`

### Rule 2: Only change what this skill created
The agent may modify (`PUT`) **only objects it created itself in this plan's runs**.
- Track them in a ledger, `content-exec-<account>-<YYYY-MM-DD>/created.json`, recording the type, ID and creating action of every object a `POST` returned.
- **Anything that already existed is read-only to the agent:** audiences, Supertopics, custom topic rules, collections, layers, flows. Any change to one (even an "additive" one) is a `human_handoff`.
- Adding topics to someone else's Supertopic, or adding a guard to someone else's audience, changes who is in it. That's a live change the owner must make.

### Rule 3: Never shrink or remove anything live
Anything that removes, deletes, zeroes, unpublishes, narrows or shrinks existing configuration or a live audience is **destructive**, and becomes a `human_handoff`. That includes:
- deleting, retiring or unpublishing a Supertopic; removing topics or lowering weights
- **changing a live audience the skill didn't create**, including adding a recency guard or a threshold (it shrinks the audience)
- deleting or "changing" a custom topic rule (which needs delete and recreate)
- zeroing or removing a topic on a page
- removing entries from a block or allow list, or replacing a list with a shorter one
- blocking a topic that a pre-existing audience, Supertopic or flow uses (it shrinks them)
- allowlisting topics outside the skill's own Supertopic publish (it can push other topics out of the 500-topic set)
- layer scoring-flag changes, or lowering `num_topics`
- deleting content records, collections, layers or audiences
- **domain or path blocks** (`content_blacklist_domains`, `content_blacklist_paths`): a change to either starts a Lytics job that **hard-deletes** every content record matching *any* entry in the full list (and, if domain or path allowlists are set, every record matching none of them). See `api-notes.md`.
- publishing Supertopics that would push existing topics out of the topic set (see the capacity check under `publish_affinity`)

If a plan marks a destructive action as anything other than `human_handoff`, refuse it and report it.

### Rule 4: Measure live audiences by copying them, never by editing them
To see how a narrower or guarded version of an existing audience would size:
1. Read its definition (`GET /api/segment/<id>`).
2. Copy the FilterQL, and add your guard or threshold.
3. Count it with `GET /api/segment/size?segments=<copied FilterQL>`. If you need a breakdown, use `GET /api/segment/fieldinfo?segments=...`.

Nothing is saved, and the live audience is untouched. Put the result in the human handoff as "what this change would do".

### Rule 5: Disclose indirect effects
Topic scores are relative to each person's own top topic. So any change to pages or topics (new rules, blocks, re-classification, a new Supertopic) can shift scores, and therefore move the size of existing topic audiences, even when nothing is directly edited.
- In the readout, list every pre-existing topic or Supertopic audience.
- Size each one (read-only) before the run, and again at `verify`. Report the change.

### Rule 6: Privacy
- Never put a personal name, email or account identity into plans, handoffs, scripts, HTTP headers or outputs. Use **roles** (`customer Lytics admin`, `customer web team`, `Lytics account team`, `Lytics support`).
- Website requests use a generic User-Agent with no personal details (see `site-assessment.md`).

## 0. Before anything else: the readout
Print this, in plain language, and wait for the user to confirm before the first call.

**1. What will run:** each approved action (or batch). Also list what is being refused, with the reason (destructive, not created by the skill, or out of scope).

**2. Access needed:** the union of `access` across the approved actions (see the table below).
- Name the exact granular scopes.
- Recommend a **short-lived** token (24h) **with only those scopes**.
- Actions marked `how: ui` or `how: human` aren't run by the agent; list them as steps for a person.

**3. Risk:**
- each action's risk
- the pre-existing audiences that could move indirectly (Rule 5), with today's sizes
- the re-scoring delay
- how each action is undone

**4. What this run will never do:**
- send a `DELETE`
- change anything it didn't create
- shrink or remove anything live
- touch profiles, schema, identity config, streams, jobs, connections, auth, or any account setting outside the content allowlist

If the user's token is read-only, or they prefer it, switch to script mode (below).

### Access per action type
| Action type | Endpoint(s) | `access` value | Risk |
|---|---|---|---|
| `block_pages`, `allow_params` | `PUT /api/account/setting/<key>` (merge-only) | `v2_account_settings_manage` | Medium. This scope can change **every** account setting, so the guardrail restricts it to these two keys and `topic_blacklist`. Neither key starts the content delete job. |
| `block_topics` (only topics **no** pre-existing audience, Supertopic or flow uses, and only when the two lists match; see the playbook) | `PUT /api/account/setting/topic_blacklist`, or `PUT /api/content/config/<real id>` for a non-default layer (merge-only) | `v2_account_settings_manage` or `v2_content_manage` | Medium. |
| `create_affinity`, `publish_affinity`, `add_affinity_topics` (own drafts only), `suggest_affinities` | `POST /api/content/affinity`, `PUT /api/content/affinity/:id` (only IDs in the ledger), `POST /v2/ai/supertopic/suggest` (**creates drafts**) | `v2_content_manage` | Create: low. Suggest: low (drafts go in the ledger). Publish: **high** unless the capacity check passes. |
| `create_audience` (new audiences only) | handed to `audience-builder skill` | `v2_segment_manage` (used by that skill) | Low to medium. New objects only. |
| `block_domains`, `block_paths`, `custom_topic_rule`, `page_topic_edit`, `reclassify_pages` | none: **not automated** | `none` (a person does it in the UI, or the customer's Lytics team does it) | Domain and path blocks **delete content**. Rules, page edits and re-classification are UI or Lytics-team work while API access for them is under review. Don't document or request a token for them. |
| `human_handoff`, `customer_site_spec`, `support_request`, `setup_recommendation`, `verify` | none (or read-only) | `view` | A person carries out handoffs. |

Never ask for, or accept, a broader token "to be safe".

## Guardrail: allowed writes
Check every request against this list. **Refuse anything else.**
- `POST /api/content/affinity`: create, as a draft. Record the ID in the ledger.
- `PUT /api/content/affinity/:id`: **only IDs in the ledger**. Add topics or weights, or publish (the new topic list must be a superset).
- `POST /v2/ai/supertopic/suggest`: **a write.** It creates a draft Supertopic for every suggestion. Record every returned ID in the ledger.
- `PUT /api/content/config/<real id>`: only `blacklisted_topics`, as a superset, on a **non-default** layer, for topics that pass the dependency check. Never `PUT /api/content/config/default`: it returns 400.
- `PUT /api/account/setting/:key`: superset only. Keys: `topic_blacklist` (dependency-checked, and lists-match checked), `content_blocked_pages`, `content_allowed_params`.

**Superset check:** before every `PUT`, compare the new value with the snapshot. If anything would be removed or lowered, refuse it and convert it to a `human_handoff`.

**Always refused:**
- every `DELETE`
- `PUT` on any object not in the ledger
- `content_blacklist_domains`, `content_blacklist_paths`, and every `content_whitelist_*` key (they start the content hard-delete job)
- `/v2/content/customtopic`, `/api/content/doc/...` topic edits, `/api/content/doc/classify` (UI or Lytics-team only)
- anything under `/api/entity`, `/v2/entity`, `/api/schema`, `/v2/schema`, `/api/stream`, `/api/work`, `/v2/job`, `/api/auth`, `/v2/auth`, `/api/account/:id`, `/api/user`
- `/v2/segment` and `/api/segment` writes (new audiences go through `audience-builder`; existing ones are handoffs)
- `/v2/content/contextlayer` writes, `/api/content/crawl`, and any other setting

## Rules for every action
1. **Pre-check.** Re-read the current state. If the action is already done, mark it `done`. If anything conflicts with the plan, stop and ask.
2. **Dependency check.** Before any block, search user segments and flows for references (FilterQL containing the topic label). If anything pre-existing depends on it, the action becomes a `human_handoff`.
3. **Snapshot** to `before/<action id>.json`.
4. **Confirm** via `references/confirmation-gate.md`.
   - A batch may be confirmed once, showing every item.
   - High-risk actions are confirmed alone.
5. **Execute** item by item. Re-read each setting right before its own write (no cached values). Save each response to `after/<action id>/<item>.json`, and update the ledger.
6. **Update the plan:** set `done` or `failed` (with the error), plus the date.
7. **Rollback note:** how to undo it. Undoing always means removing something, so it is written as a `human_handoff`.

## Script mode (`--dry-run`, or a read-only token)
Generate `content_exec_<account>_<YYYY-MM-DD>.py`. It must be:
- **a single Python 3 standard-library file** (`urllib.request`, `json`, `argparse`, `pathlib`, `time`). It runs unchanged on macOS, Windows and Linux (`python3 file.py`, or `py file.py` on Windows).
- **driven by the plan's JSON copy,** acting only on `approved` actions with `how: api`. It reads `LYTICS_API_TOKEN` / `LYTICS_API_URL` from the environment and never embeds a token.
- **hard-coded with a method allowlist of `GET`, `POST`, `PUT`.** It exits on anything else, and contains no `DELETE` code path.
- **enforcing the guardrail list itself:** the ledger rule, the superset check, the dependency check, the lists-match check and the publish capacity check.
- **dry-run by default,** sending only with `--apply`. It logs every request and response, snapshots before every write, and re-reads each setting immediately before its own write.
- **free of personal names or emails** in code, comments, headers and logs. Items flagged `person_name: true` are sent as-is, but shown as `[person name]` in logs and previews.

Also write `dry-run-preview-if-all-approved.log`.

## Playbooks

### `block_pages` / `allow_params`
1. `GET /api/account/setting/<key>`. The value is at `data.value` (`null` = empty).
2. Merge and de-duplicate.
3. `PUT` the full list.

Page blocks match one exact URL, including the domain but not the protocol (`www.example.com/404.html`). They stop that page being collected, and don't start the delete job.

### `block_domains` / `block_paths` (always a `human_handoff`)
Changing either setting starts a Lytics job that **hard-deletes** every content record whose URL contains **any** entry in the **full** list, not just the new one. If domain or path allowlists are set, it also deletes every record that matches none of them.

The handoff must show the person what will be deleted. For **each entry in the full proposed list** (existing entries plus new ones):
- `GET /api/segment/size?segments=FILTER url CONTAINS "<entry>" FROM content`
- how many of the matches are live HTML pages (`... AND httpstatus = 200`)

Also give the total, and name any live pages that would go.

**How matching works:**
- **At collection:** domains match the host (`*.example.com` or exact). Path entries are a **contains** match, except entries with `*`, which are matched as **wildcard** path patterns (segment-wise, and `*$` anchors the end).
- **In the delete job:** every entry is matched with FilterQL `url CONTAINS "<entry>"`, so size it that way. How `CONTAINS` treats a literal `*` isn't verified, so flag `*` entries as "deletion count uncertain".

### `block_topics`
1. Read **both** lists: the account setting `topic_blacklist` (`data.value`), and the default layer's `blacklisted_topics` (`GET /api/content/config`; the default layer is tagged `default`).
2. **On a migrated default layer** (the default config has its own real ID), writing the setting **replaces** the layer's list with the setting's value, while writing the layer doesn't update the setting. Scoring uses the layer's list.
   - **If the two lists differ:** stop, and write a `human_handoff` naming the difference. A write through either path could unblock topics.
   - **If they match:** write through the **setting** only (merged superset). Then re-read the layer to confirm it now matches. The sync can fail silently.
3. **On an unmigrated default layer** (no stored config; the API shows id `default`): write the setting only. `PUT /api/content/config/default` returns 400.
4. **On a non-default layer:** `PUT /api/content/config/<real id>` with the merged `blacklisted_topics`.

Only for topics that pass the dependency check. Verify by profile counts falling (fieldinfo) over the following weeks.

### `suggest_affinities` (a write)
`POST /v2/ai/supertopic/suggest?limit=&config=` **creates a draft Supertopic for every suggestion** it returns.
- It runs only in `execute`, never in `advise`.
- Record every returned ID in the ledger.
- Show the drafts.
- Unused drafts stay. Removing them is a `human_handoff`.

### `create_affinity` / `publish_affinity` / `add_affinity_topics` (own Supertopics only)
**Name pre-check, before creating:**
- Supertopic names must be unique across the account, **drafts included**.
- Names are compared case-insensitively, with spaces and underscores treated as the same, and punctuation stripped.
- So list the existing Supertopics (`GET /api/content/affinity`, drafts included), and compare simplified names (lowercase, spaces → `_`, collapse repeated `_`, drop other symbols).
- A clash fails with a generic server error, not a clear "conflict", so check first.

**Create:** `POST /api/content/affinity` with `"draft": true`, then record it in the ledger.

**Publish capacity check (before every publish):**
- Publishing adds every member topic to the topic allowlist.
- Allowlisted topics take places in the topic set first (`content_max_topics`, default 500), and can push other topics out.
- Count the current allowlist (setting and layer), plus new member topics not already in it or in the current topic set, against the limit.
  - **If it doesn't fit,** or the Rule 5 sizing of existing topic audiences shows any would shrink: **don't publish.** Write a `human_handoff`.
  - **If it fits:** publish as a separate, single confirmation. `PUT` with `"draft": false`.
- Use the Rule 5 sizes as the go / no-go, not just a report.
- Don't rely on this allowlist behaviour never changing. Re-read the allowlist after each publish.

**Add topics:** only to Supertopics in the ledger, as a superset. Run the capacity check again.

Every change to a pre-existing Supertopic is a handoff, even adding topics.

**Verify:**
- `GET /api/segment/size?segments=FILTER lytics_rollup.\`<Label>\` >= 0.5 FROM user`
- the content scan's `rollup` map: pages tagged with the Supertopic
- Don't use `/api/content/rollup/<label>/urls`. It only matches Supertopics whose layer ID is literally `default`, so it returns nothing for others, and that looks like "no pages" rather than "can't check".

### `create_audience` (new audiences only)
Hand off to `audience-builder skill`, with the FilterQL, a name (which should signal that this skill created it), the description and the reach notes. Confirm the recency field exists first. Changes to existing audiences are always handoffs, sized with Rule 4.

### `activate`
Hand off to `integration-advisor skill` / `integration-setup skill`, or `campaign-flow-builder skill`.

### `custom_topic_rule`, `page_topic_edit`, `reclassify_pages` (UI or Lytics team only; not automated)
Write each one as steps for a person:
- **Custom topic rules:** for each rule, the name, the filter (pre-tested read-only with `GET /api/segment/size?segments=<... FROM content>`, with the match count), the topics, and the relevance value (e.g. 1.0). Note that rules apply when pages are next classified.
- **Page topic edits:** the page, the topic, and the value. At most ~25 key pages; prefer a rule.
- **Re-classification:** the list of live HTML pages (status 200, own hosts, no assets), and the count against the monthly cap. Usually a request to the Lytics account team.

### `customer_site_spec` (no API)
- **Which templates get which `lytics:topics` values.** Labels must match the canonical topics exactly.
- **The CMS-field alternative,** via `content_customprops` (a support request).
- **How to confirm the tags are live.**

### `human_handoff` (no API; the only path for destructive changes and for changes to anything the skill didn't create)
Address it to a **role**, never a person. Include:
- **what** to change and **why** (evidence)
- the **before-state** snapshot
- **what it would do,** measured read-only (Rule 4 sizing; deletion counts for domain and path blocks)
- **dependencies:** audiences, flows and exports to update first
- **how:** UI steps, or the exact request for them to review and run
- **risk,** and a read-only **verify** step

The agent never carries out a handoff, even if asked in the same session.

### `support_request` (no API)
Ready-to-send text with the account ID, the exact setting or job, the value, and the evidence. Covers:
- languages, enrichment sources, the classification cap
- a full profile re-score
- removing dead content records
- content arriving from non-web streams

### `setup_recommendation` (no API)
Not executed. Restate what is needed (stream, schema mapping, new layer, taxonomy source), and who should own it.

### `verify`
After the re-scoring window (default 14 days):
- Re-run `assess` and diff it against the original evidence.
- Re-size the pre-existing topic audiences (Rule 5).
- Report before, after and target for each metric.

## Report back
Summarize in plain language:
- what changed
- what was refused or handed off, and why
- what's waiting on time or on other people
- how each change can be undone (by a person)
- when to re-assess

Link the ledger, the snapshots and the updated plan.
