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
- **Anything that already existed is read-only to the agent:** audiences, Affinities, custom topic rules, collections, layers, flows. Any change to one (even an "additive" one) is a `human_handoff`.
- Adding topics to someone else's Affinity, or adding a guard to someone else's audience, changes who is in it. That's a live change the owner must make.

### Rule 3: Never shrink or remove anything live
Anything that removes, deletes, zeroes, unpublishes, narrows or shrinks existing configuration or a live audience is **destructive**, and becomes a `human_handoff`. That includes:
- deleting, retiring or unpublishing an Affinity; removing topics or lowering weights
- **changing a live audience the skill didn't create**, including adding a recency guard or a threshold (it shrinks the audience)
- deleting or "changing" a custom topic rule (which needs delete and recreate)
- zeroing or removing a topic on a page
- removing entries from a block or allow list, or replacing a list with a shorter one
- blocking a topic that a pre-existing audience, Affinity or flow uses (it shrinks them)
- allowlisting topics outside the skill's own Affinity publish (it can push other topics out of the 500-topic set)
- layer scoring-flag changes, or lowering `num_topics`
- deleting content records, collections, layers or audiences

If a plan marks a destructive action as anything other than `human_handoff`, refuse it and report it.

### Rule 4: Measure live audiences by copying them, never by editing them
To see how a narrower or guarded version of an existing audience would size:
1. Read its definition (`GET /api/segment/<id>`).
2. Copy the FilterQL, and add your guard or threshold.
3. Count it with `GET /api/segment/size?segments=<copied FilterQL>`. If you need a breakdown, use `GET /api/segment/fieldinfo?segments=...`.

Nothing is saved, and the live audience is untouched. Put the result in the human handoff as "what this change would do".

### Rule 5: Disclose indirect effects
Topic scores are relative to each person's own top topic. So any change to pages or topics (new rules, blocks, re-classification, a new Affinity) can shift scores, and therefore move the size of existing topic audiences, even when nothing is directly edited.
- In the readout, list every pre-existing topic or Affinity audience.
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
- Name the actions that can't use a narrow token (`access: ui_admin` or `admin`), and the recommended path for each: the Lytics UI, the customer's Lytics team, or skipping it.

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
| Action type | Endpoint(s) | `access` value (narrowest token) | Risk |
|---|---|---|---|
| `block_domains`, `block_paths`, `block_pages`, `allow_params` | `PUT /api/account/setting/<allowlisted key>` (merge-only) | `v2_account_settings_manage` | Medium. This scope can change **every** account setting, so the guardrail restricts it to the content allowlist. |
| `block_topics` (only topics **no** pre-existing audience, Affinity or flow uses) | `PUT /api/account/setting/topic_blacklist`, or `PUT /api/content/config/:id` `blacklisted_topics` (merge-only) | `v2_account_settings_manage` or `v2_content_manage` | Medium. |
| `create_affinity`, `publish_affinity`, `add_affinity_topics` (own drafts only), AI suggestions | `POST /api/content/affinity`, `PUT /api/content/affinity/:id` (only IDs in the ledger), `POST /v2/ai/supertopic/suggest` | `v2_content_manage` | Publishing is **medium**. Publishing allowlists the Affinity's topics, which is expected. |
| `custom_topic_rule` (create only) | `POST /v2/content/customtopic` | `ui_admin` (no granular scope; prefer the Lytics UI) or `admin` | **High (privilege).** |
| `page_topic_edit` (set only), `reclassify_pages` | `POST /api/content/doc/...`, `POST /api/content/doc/classify` | `admin` (no narrow scope; broad data role) | **High (privilege).** Prefer rules plus natural re-classification, or the customer's Lytics team. |
| `create_audience` (new audiences only) | handed to `audience-builder skill` | `v2_segment_manage` (used by that skill) | Low to medium. New objects only. |
| `human_handoff`, `customer_site_spec`, `support_request`, `setup_recommendation`, `verify` | none (or read-only) | `view` | A person carries out handoffs. |

Never ask for, or accept, a broader token "to be safe". If an admin token is supplied, use it only for the actions that need it, and say so.

## Guardrail: allowed writes
Check every request against this list. **Refuse anything else.**
- `POST /api/content/affinity`: create, as a draft. Record the ID in the ledger.
- `PUT /api/content/affinity/:id`: **only IDs in the ledger**. Add topics or weights, or publish (the new topic list must be a superset).
- `POST /v2/ai/supertopic/suggest` (saves nothing)
- `PUT /api/content/config/:id`: only `blacklisted_topics`, as a superset, for topics that pass the dependency check
- `POST /v2/content/customtopic`: create only. Record the ID in the ledger.
- `POST /api/content/doc/:docField/:docId/topic/:label`: only to set a topic with relevance > 0 on a page that has no value for that topic yet
- `POST /api/content/doc/classify?url=`
- `PUT /api/account/setting/:key`: superset only. Keys: `topic_blacklist` (dependency-checked), `content_blacklist_domains`, `content_blacklist_paths`, `content_blocked_pages`, `content_allowed_params`.

**Superset check:** before every `PUT`, compare the new value with the snapshot. If anything would be removed or lowered, refuse it and convert it to a `human_handoff`.

**Always refused:**
- every `DELETE`
- `PUT` on any object not in the ledger
- anything under `/api/entity`, `/v2/entity`, `/api/schema`, `/v2/schema`, `/api/stream`, `/api/work`, `/v2/job`, `/api/auth`, `/v2/auth`, `/api/account/:id`, `/api/user`
- `/v2/segment` and `/api/segment` writes (new audiences go through `audience-builder`; existing ones are handoffs)
- `/v2/content/contextlayer` writes
- `/api/content/crawl`
- allowlist settings (`topic_whitelist`, `content_whitelist_*`), and any other setting

## Rules for every action
1. **Pre-check.** Re-read the current state. If the action is already done, mark it `done`. If anything conflicts with the plan, stop and ask.
   - For custom topic rules, list the existing rules first, now readable with the admin token.
2. **Dependency check.** Before any block, search user segments and flows for references (FilterQL containing the topic label or path).
   - If anything pre-existing depends on it, the action becomes a `human_handoff`.
3. **Pattern check (path and page blocks).** Path blocks match any URL that **contains** the value. Before blocking:
   - count the live HTML pages (`httpstatus` 200, in the sitemap) that the value would also match (`GET /api/segment/size?segments=FILTER url CONTAINS "<value>" FROM content`)
   - if it would catch pages the plan doesn't intend to block, refuse it, and narrow the pattern in a handoff
4. **Snapshot** to `before/<action id>.json`.
5. **Confirm** via `../references/confirmation-gate.md`.
   - A batch may be confirmed once, showing every item.
   - High-risk actions are confirmed alone.
6. **Execute** item by item. Save each response to `after/<action id>/<item>.json`, and update the ledger.
7. **Update the plan:** set `done` or `failed` (with the error), plus the date.
8. **Rollback note:** how to undo it. Undoing always means removing something, so it is written as a `human_handoff`.

## Script mode (`--dry-run`, or a read-only token)
Generate `content_exec_<account>_<YYYY-MM-DD>.py`. It must be:
- **a single Python 3 standard-library file** (`urllib.request`, `json`, `argparse`, `pathlib`, `time`). It runs unchanged on macOS, Windows and Linux (`python3 file.py`, or `py file.py` on Windows).
- **driven by the plan's JSON copy,** acting only on `approved` actions. It reads `LYTICS_API_TOKEN` / `LYTICS_API_URL` from the environment and never embeds a token.
- **hard-coded with a method allowlist of `GET`, `POST`, `PUT`.** It exits on anything else, and contains no `DELETE` code path.
- **enforcing the guardrail list, the ledger rule, the superset check, the dependency check and the pattern check itself.**
- **dry-run by default,** sending only with `--apply`. It logs every request and response, snapshots before every write, and is idempotent.
- **for `reclassify_pages`,** limited to live HTML URLs on the site's own hosts. It throttles, and prints the classification count.
- **free of personal names or emails,** in code, comments, headers and logs. Items flagged `person_name: true` are sent as-is in the request body, but shown as `[person name]` in every log line and printed preview.
- **free of stale reads:** re-read each setting immediately before its own merge and `PUT`. Never reuse a value cached earlier in the run, or a later block-list update could overwrite an earlier one.

Also write `dry-run-preview-if-all-approved.log`.

## Playbooks

### Collection filters: `block_domains` / `block_paths` / `block_pages` / `allow_params`
1. `GET /api/account/setting/<key>`. The current list is at `data.value` (`null` means empty).
2. Run the pattern check.
3. Merge and de-duplicate.
4. `PUT` the full list.

How each one matches:
- **Domain** blocks support `*.example.com` and exact domains.
- **Path** blocks match any URL that **contains** the value, so `faq` also blocks `/faqs-about-filters/`.
- **Page** blocks match one exact URL, including the domain but not the protocol (`www.example.com/404.html`).

These stop **new** collection only. Pages already collected stay. Removing any entry is a handoff.

### `block_topics`
Only for topics that pass the dependency check. Use whichever list the account already uses (account setting `topic_blacklist`, or the layer's `blacklisted_topics`), merge-only.

Verify by watching profile counts fall (fieldinfo) over the following weeks.

### `custom_topic_rule` (can be a batch)
1. List the existing rules.
2. Pre-test each filter on the content table (`GET /api/segment/size?segments=<... FROM content>`), and report the match counts.
3. `POST /v2/content/customtopic`, with an explicit `value` (e.g. 1.0) on every topic.
4. Test one URL-pattern rule before the rest.
5. Record the IDs in the ledger.

**If the access is `ui_admin`,** write the UI steps instead: rule name, filter, topics, and value.

Rules apply when pages are next classified. Changing or removing a rule is a handoff.

### `page_topic_edit`
`POST /api/content/doc/hashedurl/<hashedurl>/topic/<Label>?relevance=1.0`
- Only on pages that don't already carry that topic.
- At most ~25 key pages.
- Removing or zeroing a topic is a handoff.

### `reclassify_pages`
`POST /api/content/doc/classify?url=<url>`, one at a time, throttled. State the count against the monthly cap first. Verify by re-scanning the pages.

### `create_affinity` / `publish_affinity` / `add_affinity_topics` (own Affinities only)
- **Create:** `POST /api/content/affinity` with `"draft": true`, then record it in the ledger.
- **Publish:** a separate confirmation. `PUT` with `"draft": false`.
- **Add topics:** only to Affinities in the ledger, as a superset.

Every change to a pre-existing Affinity is a handoff, even adding topics.

**Verify:**
- `GET /api/segment/size?segments=FILTER lytics_rollup.\`<Label>\` >= 0.5 FROM user`
- `GET /api/content/rollup/<Label>/urls` (if readable)

### `create_audience` (new audiences only)
Hand off to `audience-builder skill`, with the FilterQL, a name (which should signal that this skill created it), the description and the reach notes. Confirm the recency field exists first.

Changes to existing audiences are always handoffs, sized with Rule 4.

### `activate`
Hand off to `integration-advisor skill` / `integration-setup skill`, or `campaign-flow-builder skill`.

### `customer_site_spec` (no API)
- **Which templates get which `lytics:topics` values.** Labels must match the canonical topics exactly.
- **The CMS-field alternative,** via `content_customprops` (a support request).
- **How to confirm the tags are live.**

### `human_handoff` (no API; the only path for destructive changes and for changes to anything the skill didn't create)
Address it to a **role**, never a person. Include:
- **what** to change and **why** (evidence)
- the **before-state** snapshot
- **what it would do,** sized with Rule 4 (for example, "audience goes from 211,400 to 18,900")
- **dependencies:** audiences, flows and exports to update first
- **how:** UI steps, or the exact request for them to review and run
- **risk,** and a read-only **verify** step

The agent never carries out a handoff, even if asked in the same session.

### `support_request` (no API)
Ready-to-send text with the account ID, the exact setting or job, the value, and the evidence. Covers:
- languages, enrichment sources, the classification cap
- a full profile re-score
- removing dead content records

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
