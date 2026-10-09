# Advisement: turning the assessment into a plan

Input is the assessment scorecard and evidence (run `assess` first if there isn't one). Optional input is the customer's own taxonomy: a sitemap, information architecture, product category tree, or a list of business interest areas.

The output is a plan that works two ways:
- **For a person:** a readable document they can follow by hand, or take to their team.
- **For an agent:** a structured action list that `execute` can carry out, one approved action at a time.

No API writes happen in this mode.

## Step 1: Agree the target
Before proposing changes, set the destination:
1. **Business interest areas.** What does the customer want to target people by? Use their taxonomy if they gave one. If not, propose 8 to 30 areas drawn from:
   - the site's URL structure (top-level path sections)
   - the strongest clean topics in the assessment
   - `POST /v2/ai/supertopic/suggest`, if the token allows it
   - the opportunity report
2. **The target topic set.** For each interest area, list the canonical topics that belong to it. Then map every existing topic with 3 or more pages to one of:
   - **keep**: it's already canonical.
   - **merge into X**: a duplicate or variant of a canonical topic.
   - **block**: brand, generic, template noise, or off-strategy.
   - **ignore**: long tail; leave it alone and let it fall out.
3. **Customer control.** Use the matrix in `topic-curation-principles.md` to decide which levers this customer can realistically use.

Present the target (interest areas, plus the topic mapping summary) to the user and get agreement before writing actions. It is the part most likely to need the customer's input.

## Step 2: Write actions
Order the actions so that each one makes the next more effective:

1. **Stop the junk coming in.** Domain, path and page exclusions; allowed query params.
2. **Clean the topic set.** Block brand, generic and template topics. Allow the canonical topics that are rare but important.
3. **Fill the gaps.** Custom topic rules for sections the classifier gets wrong or misses. Meta-tag recommendations if the customer controls the site. Page-level edits for a handful of key pages.
4. **Re-classify.** Re-classify affected pages so rule changes take effect. Request language or classification-cap changes from Lytics support if needed.
5. **Build Affinities.** One per interest area, merging duplicate topics. Update or retire existing Affinities that overlap.
6. **Design micro-audiences.** Tiers per Affinity, each with an engagement guard, sized.
7. **Activate.** Hand off to audience creation, exports and flows.
8. **Verify and re-assess.** After the re-scoring window, run `assess` again and compare.

## Action format
Every action carries enough detail that a person can do it in the UI, or an agent can do it through the API.

```yaml
plan:
  account: <aid or name>
  context_layer: <config id>
  created: <YYYY-MM-DD>
  assessment: <path to evidence json>
  target_interest_areas: [Mortgages, Credit Cards, Savings, ...]
actions:
  - id: A01
    phase: stop-junk            # stop-junk | clean | fill | reclassify | affinities | audiences | activate | verify
    type: block_domains         # see execution.md playbooks for the full list
    title: Exclude staging and agency hosts from content collection
    why: 45 pages from admin.example-agency.com and 39 from preprod.example.com are being classified; their topics reach real profiles.
    evidence: assessment.json#source_hygiene.junk_hosts
    lever: lytics_api           # lytics_ui | lytics_api | customer_site | lytics_support
    owner: customer-lytics-admin
    payload:                    # exact values; execution.md shows the call
      setting: content_blacklist_domains
      add: [admin.example-agency.com, preprod.example.com]
    depends_on: []
    risk: low                   # low | medium | high, plus one line on what could break
    risk_note: Only affects collection of new pages; existing pages stay until removed.
    ui_steps: Content > Settings > Domain blocklist > add hosts > Save
    verify: Re-scan in 7 days; no new docs from these hosts.
    expected_effect: Stops new junk topics from these hosts.
    status: proposed            # proposed | approved | done | skipped | failed
```

Rules for actions:
- **One change per action.** Small enough to approve or reject on its own.
- **`why` cites the evidence.** No action without a measured reason.
- **Dependencies are explicit.** For example, block a topic only after any Affinity or audience that uses it has been updated.
- **High-risk actions:** anything that touches an existing live audience, a live Affinity, or a context layer. These say exactly what downstream use is affected, and are never batched with other actions.
- **`lever: customer_site`** actions (meta tags, CMS fields) are written as a short spec for the customer's web team, with example markup and the pages or templates affected.
- **`lever: lytics_support`** actions (languages, enrichment sources, classification cap) are written as a request the customer's Lytics team can act on.

## Micro-audience design
For each Affinity (or high-value single topic), propose tiers:

```yaml
  - id: A40
    phase: audiences
    type: create_audience
    title: Mortgages - high interest, active
    payload:
      name: "Mortgages | High interest | Active 30d"
      filterql: >
        FILTER AND (
          lytics_rollup.Mortgages >= 0.8,
          <engagement guard, e.g. a recent-activity field within 30 days>
        ) FROM user
      estimated_size: <from POST /api/segment/size>
    handoff: audience-builder
```

- **Always include an engagement guard.** Use whichever recency or activity field the account actually has. Confirm it with `schema-discovery skill` rather than assuming a field name.
- **Size every tier.** Drop or merge tiers that are too small for the intended channel.
- **Reuse existing audiences.** If an existing audience already covers a tier, propose updating it rather than creating a near-duplicate.

## Plan document
Write `content-advisement-plan-<account>-<YYYY-MM-DD>.md` with:
1. **Summary:** three to five sentences on what's wrong and what the plan fixes.
2. **Target taxonomy:** interest areas and their canonical topics.
3. **Actions by phase:** a table of id, title, lever, owner, risk, and status.
4. **What the customer's team needs to do** (site and support requests), kept separate so it can be forwarded.
5. **Timeline and verification:** when to re-assess, and what "better" looks like in numbers. Examples: topics in the scored set under 500; single-page topics under 30%; classification fit ≥ 80%; no topic held by more than 40% of scored profiles.

Write the matching `.yaml` action list alongside it. The user marks actions `approved` (or tells the agent which ones) before `execute` runs anything.
