# Advisement: turning the assessment into a plan

**Inputs:**
- the assessment scorecard and evidence (run `assess` first if there isn't one)
- optionally, the customer's own taxonomy: a sitemap, information architecture, product category tree, or a list of business interest areas

**Output:** a plan that works for two readers:
- **A person** (a marketer, the customer's Lytics admin, or a Lytics account team member) who reads it, decides what to approve, and does some steps by hand.
- **An agent** that carries out the approved steps through `execute`.

No API writes happen in this mode.

## Step 1: Agree the target
1. **Business interest areas:** what the customer wants to target people by.
   - Use their taxonomy if they gave one.
   - If not, propose 8 to 30 areas from:
     - the site-assessment verdict and sitemap sections
     - the strongest clean topics
     - the opportunity findings
     - **Not** `POST /v2/ai/supertopic/suggest`: it creates draft Supertopics, so it's a write. If AI suggestions are wanted, add a `suggest_affinities` action to the plan for `execute`.
2. **Taxonomy source, by site type** (see `site-assessment.md`):

   | Site / verdict | Primary taxonomy source |
   |---|---|
   | Clean, semantic URLs (content / product-is-the-site) | URL-pattern custom topic rules, one per section |
   | Brand / marketing site | Hand-built interest areas, with filter rules per section |
   | Retail / catalogue, unreliable URLs | Breadcrumbs or structured data via meta tags / `content_customprops`, or a product-catalogue layer (`setup_recommendation`) |
   | Mixed | Per host or section |

3. **Target topic set.** Map each meaningful existing topic to one of:
   - **keep:** already canonical
   - **merge into X:** a duplicate or variant
   - **block:** noise or off-strategy
   - **ignore:** long tail
4. **Customer control.** Use the matrix in `topic-curation-principles.md`.

Get the user's agreement on the target before writing actions. If you can't ask, write the plan anyway, and list the target as an **open assumption** to confirm before approving anything.

## Step 2: Write actions

### Order
1. Stop the junk coming in.
2. Clean the topic set.
3. Fill the gaps (rules, meta-tag spec, a few page edits).
4. Re-classify.
5. Build Supertopics.
6. Design new micro-audiences.
7. Activate.
8. Verify.
9. Setup recommendations (if any).

### Keep it short: group actions into batches
One reviewable decision per action, not one API call per action. Group items that share the same type, risk and owner into a single action with an `items` list. For example:
- "Create 11 section topic rules" is one action with 11 items.
- "Create 11 Supertopics as drafts" is one action.
- "Publish the 11 Supertopics" is one action.

Split a batch only when its items differ in risk or owner. **Target: about 15 to 25 actions for a small or medium site.** If you're over 30, group harder.

### What the agent may and may not propose for itself
Read the safety rules in `execution.md`. In short:
- **The agent may propose:**
  - creating new things: rules, Supertopics as drafts, new audiences
  - merge-only blocks of junk sources
  - blocks of topics that nothing pre-existing depends on
- **These are always `human_handoff`:**
  - **any change to something the skill didn't create**, including existing audiences, Supertopics and rules (even adding a guard or topics)
  - any removal, shrink, unpublish or delete
  - blocking a topic that something pre-existing uses
- **Existing audiences** that need a fix (no recency guard, dead topics) get a `human_handoff`. It shows the proposed new FilterQL and its size, measured by **copying** the audience's FilterQL into a read-only size check (`GET /api/segment/size?segments=...`). The live audience is never edited. Optionally, also propose a **new** guarded audience as an additive alternative the owner can switch to.

### When topic scores aren't usable yet
If the assessment shows topic scores can't support audiences today (most traffic lands on pages with no usable topic), you may propose **interim** new audiences built from the visited-URL field instead (e.g. `FILTER AND (urls CONTAINS "/faucet", <recency>) FROM user`), one per interest area. Confirm the field's name in the schema. Label them "interim, URL-based", and pair each with the Supertopic audience that will replace it once re-scoring completes.

### Content arriving from non-web streams
If a large share of content records came from a sync or ad stream (not the web tag), write a `support_request` asking the Lytics account team to confirm the source and stop that stream feeding the content table. The agent can't change stream routing.

### Things that can't be fixed directly
Say so plainly:
- **Dead pages already collected:** block their paths so they aren't re-collected. Removal is a request to the customer's Lytics team.
- **Stale topics on inactive profiles:** scores never decay. Use recency guards in **new** audiences. A full re-score is a support request.

## Action format
```yaml
plan:
  account: <aid or name>
  context_layer: <config id>
  created: <YYYY-MM-DD>
  assessment: <path to evidence json>
  site_type: brand | content | retail | mixed
  url_taxonomy_verdict: use | partial | dont_use | not_assessed
  target_interest_areas: [ ... ]
  open_assumptions: [ ... ]
actions:
  - id: A05
    phase: fill                 # stop-junk | clean | fill | reclassify | affinities | audiences | activate | verify | setup
    type: custom_topic_rule     # must match a playbook in execution.md
    title: Add section topic rules for the 11 interest areas
    why: Product pages carry spec words ("Capacity", "99%") instead of product types; 43% of judged pages were wrong.
    evidence: assessment.json#classification_fit
    how: ui                     # ui | api | customer_site | lytics_support | human
    owner: customer Lytics admin    # a ROLE, never a person's name
    access: none                # view | v2_account_settings_manage | v2_content_manage | v2_segment_manage | none (for ui / human / support rows)
    risk: high                  # low | medium | high
    risk_note: Done by hand in the Lytics UI; adds topics to ~84 pages, which shifts scores for anyone who visited them.
    items:
      - { name: Faucet, filter: 'FILTER url CONTAINS "/faucet" FROM content', topics: [{label: Faucet Filters, value: 1.0}], pages_matched_today: 9 }
      # ...
    depends_on: [A02]
    ui_steps: <step-by-step for the UI, when how = ui>
    verify: After re-classification, scan the pages and confirm each carries its section topic.
    expected_effect: Every live product page carries a product-type topic.
    status: proposed            # proposed | approved | done | skipped | failed
```
- **`owner`** is always a role: `customer Lytics admin`, `customer web team`, `customer marketing`, `Lytics account team`, or `Lytics support`. **Never a person's name or email,** even if you know who the user is.
- **`person_name: true`** on an item (for example, one label in a block list) marks it as a person's name. The `.yaml`/`.json` carry the exact label, because the action needs it. Prose, logs and printed output show `[person name]` instead, and generated scripts must honour the flag.
- **`how: human`** is used for every `human_handoff`. **`how: ui`** marks steps done by hand in the Lytics UI. Custom topic rules, page topic edits and re-classification are always `ui` (or `lytics_support`), never `api`.
- **Domain and path blocks are always `type: human_handoff`.** Changing either setting hard-deletes matching content records. The handoff shows the deletion count for every entry in the full list (`execution.md`).

## New micro-audiences
For each Supertopic (or high-value single topic), propose **new** tiers. Never edits to existing audiences.
```yaml
  - id: A14
    phase: audiences
    type: create_audience
    title: New interest audiences, 2 tiers per Supertopic (22 audiences)
    how: api
    owner: customer marketing
    access: v2_segment_manage
    items:
      - name: "Faucet | High interest | Active 90d"
        filterql: 'FILTER AND (lytics_rollup.`Faucet` >= 0.8, <recency field> > "now-90d") FROM user'
        estimated_size_today: <read-only size using the member topics; "estimate before the Supertopic exists">
        reach: { email: <n>, ad_ids: <n>, anonymous_web: <n> }
    handoff: lytics-audiences
```
- **Fit the guard to the channel.** Don't apply one guard everywhere:

  | Channel | Recommended guard |
  |---|---|
  | Ad platforms, on-site personalization | Recent **site activity** (for example 30 or 90 days), on a field that reflects real visits. See `assessment.md` on fields fed by syncs. |
  | Email, SMS | Site visits are often rare for these people. Use the Supertopic plus **channel engagement or consent** (an email field, opt-in, recent opens if they exist). Don't require a site visit. Size it with and without the guard, and show both. |
  | Anything | If the only recency field is also fed by sync streams, say so, and label it "last seen anywhere". |

- **Tiers must actually separate people.** Scores are relative to each person's top interest, so most active people score high on their main Supertopic. Before proposing score tiers, check the distribution: `GET /api/segment/fieldinfo?segments=<active FilterQL>&fields=lytics_rollup`, or size ≥ 0.8 against ≥ 0.5.
  - If **more than ~80%** of the Supertopic's active holders are already ≥ 0.8, don't use score tiers. Use **one** score cut (≥ 0.5), and tier by **engagement** instead: recency window (30 days versus 90 days), or depth (visits, or pages in that section, if a count field exists).
  - State which basis you chose and why, with the numbers.
- **Existing audiences with a different purpose** (for example, email audiences that use a topic as one condition): adding a site-visit guard can wipe them out. Size the copy first. If it collapses, recommend replacing the topic condition with the new Supertopic (as a human handoff), not adding a guard.
- **Record reach per channel.** Drop or merge tiers too small for the intended channel.

## The plan document
Write `content-advisement-plan-<account>-<YYYY-MM-DD>.md`. It's read by people who weren't part of the analysis, so **every section starts with a short italic "What this is / how to use it" note** (one to three sentences) before its content. Write for a marketer as much as an engineer: plain words, no unexplained acronyms, no internal field names in the explanation.

Sections, each with its explainer:

1. **Start here.**
   *What this is:* the five actions to approve first, and why they come first.
   Each one: a sentence on what it does, why, and who does it.

2. **Summary.**
   *What this is:* the problem and the fix in three to five sentences.

3. **Before you approve anything: open assumptions.**
   *What this is:* decisions the analysis had to guess. Confirm them first, because several actions depend on them.

4. **Target taxonomy.**
   *What this is:* the interest areas the plan builds toward, and the topics that roll up into each. This is the "map" every later action serves.
   A table of interest area → canonical topics, plus which taxonomy source was chosen and why.

5. **Actions, phase by phase.**
   *What this is:* every proposed change, in the order to do it. Each row is one decision to approve or reject.
   - Under the explainer, include **a legend for the table**:

     | Column | Meaning |
     |---|---|
     | ID | Reference used everywhere else in the plan |
     | Action | What changes, in plain words |
     | How | `API` (an agent can do it), `UI` (by hand in Lytics), `Web team`, `Support` (Lytics does it), or `Person` (a handoff: destructive or touches existing setup) |
     | Owner | The role that approves or carries it out |
     | Access | The permission an agent needs for `API` rows: `view` (read only) or a named permission. `none` for rows a person does |
     | Risk | Low / Medium / High, with one line on what could go wrong |
     | Status | `proposed` until someone approves it |

   - Then include **"What to do with this table"**:
     1. Read the Start-here five.
     2. Mark the ones you agree with as `approved` in the `.yaml`/`.json` (or tell the agent which IDs).
     3. Do the `UI`, `Web team`, `Support` and `Person` rows yourself, or forward them.
     4. Run `execute` for the `API` rows.
   - Group the table by phase, with a one-line explainer per phase heading ("Stop the junk: these keep bad pages out of Lytics").

6. **Access needed.**
   *What this is:* which permissions an agent needs to do the `API` rows, and which rows need an administrator. Use it to request the right short-lived token, and nothing broader.

7. **Handoffs for a person.**
   *What this is:* changes the agent will not make, because they remove or shrink something, or touch setup the agent didn't create. Each one says what it does, measured read-only (for example, "audience goes from 211,400 to 18,900"), what depends on it, and how to do it.

8. **Requests for the web team and Lytics support.**
   *What this is:* ready-to-forward requests.

9. **Setup recommendations** (if any).
   *What this is:* bigger changes outside this skill, such as a new context layer or a product-data feed, and why they're worth considering.

10. **How we'll know it worked.**
    *What this is:* when to re-check, and the numbers that should move. Show before, target, and how it's measured. Examples:
    - under 500 topics in the scored set
    - single-page topics under 30%
    - classification fit ≥ 80%
    - no topic held by more than 40% of scored profiles
    - no noise topics in the top 50 on profiles

Write the matching `.yaml` alongside it, plus an identical `.json` copy (generated scripts read the JSON, because Python's standard library can't parse YAML). Actions stay `proposed` until a person marks them `approved`.
