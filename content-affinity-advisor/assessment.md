# Assessment: auditing a content context layer

Read-only, on a view token. Produces a scorecard (markdown) and an evidence file (JSON). Every finding must cite the data behind it: counts, example URLs, example topics. Never report a problem you didn't measure.

Use `topic-curation-principles.md` for the judgement calls. Use `api-notes.md` for exact endpoints, the read-only query recipes, and the fallback for every 403. Use `site-assessment.md` for live-site checks.

**Counting rule:** every count comes from a **GET** call: `GET /api/segment/size?segments=<FilterQL>`, segment `fieldinfo`, or a content `scan`. Nothing is saved, and no PII is read.

## A. Inventory: what exists

Collect each of these. Record any 403/404 in a `gaps` list, use the listed fallback, and keep going.

| What | Call (fallback) | Record |
|---|---|---|
| **Context layers** | `GET /api/content/config` | Per layer: `id`, `label` (case-insensitive; the default layer is tagged `default`), `rhs_table`, `rhs_feature_ids`, `lhs_output_id`, `lhs_affinity_id`, `num_topics`, `explicit_affinities`, `inferred_affinities`, `use_activity_counts`. `blacklisted_topics` and `whitelisted_topics` are left out when empty. |
| **Supertopics** | `GET /api/content/affinity` | `label`, `config_id`, `topics` and weights, `method`, `draft`, `created`, `updated`. |
| **Account content settings** | `GET /api/account/setting` | The keys listed in `api-notes.md`, including the domain **allowlist** `content_whitelist_domains`. If it's set, only those domains are collected, which explains coverage, and junk on allowed domains still gets in. Staff-only keys (`supported_languages`, `enrich_content`) are hidden from view tokens, so list them under "unknown". |
| **Custom topic rules** | `GET /v2/content/customtopic` (usually 403, and has no fallback) | If blocked, record the gap "existing custom topic rules unknown". |
| **Content collections** | `GET /api/segment?table=content` | Default collections (`all_documents`, `recently_classified_documents`, ...) versus customer-built ones. |
| **Profile score fields** | `GET /api/schema/user` | `lytics_content`, `lytics_content_inferred`, `lytics_rollup`, plus any custom layer's output fields. |
| **Downstream use** | `GET /api/segment?table=user`, `GET /v2/flow/ui` | Segments whose FilterQL references a topic or Supertopic field, with each one's threshold and guards. Flows with an `affinity` step. |
| **Topic list** | `GET /api/content/topic` (fallback: `GET /api/segment/<all-users id>/fieldinfo?fields=lytics_content&limit=500`, or ad-hoc `GET /api/segment/fieldinfo?segments=<FilterQL>&fields=lytics_content`, which is verified live) | Profile-side count per topic. Page-side counts come from step B. The ad-hoc form also lets you look at **active profiles only**. |
| **Recency and identifier fields** | `GET /api/schema/user` | Find, don't assume:<br>• **recency:** a timestamp of last activity (common names: `lastvisit_ts`, `last_active_ts`, `_modified`). Confirm it with `GET /api/segment/size?segments=FILTER <field> > "now-90d" FROM user`.<br>• **Check what feeds the recency field.** "Last activity" fields are often also written by sync or import streams (ad-platform syncs, CRM loads), not just site visits. Warning signs: the field exists on nearly every profile, or the 90-day count is far larger than the web-active population. Check which streams map to it (`schema-discovery skill`, or the field's stream mappings), and compare its 90-day count with web-only evidence. For example, `GET /api/segment/fieldinfo?segments=<90-day FilterQL>&fields=_streamnames` shows which streams those profiles came through (`_streamnames`, not `_streams`). A field present on nearly every profile is only a warning sign: if `_streamnames` shows the recent population all arrived through the web stream, the field is fine. If no web-only recency field exists, say so, and label the guard "last seen anywhere", not "visited the site".<br>• **activation identifiers:** email, hashed email, phone, mobile IDs, and ad-platform IDs or their sync timestamps (for example `<platform>_id`, `<platform>_id_ts`).<br>Record what exists. If an ad platform has only a sync timestamp, say reach is approximate. |
| **Opportunity** | `GET /v2/content/opportunity` (fallback: derive in step D) | Topics with high interest but thin content. |

## B. Content: what the classifier saw
Scan the content table:
```
GET {LYTICS_API_URL}/api/segment/{ALL_DOCS_ID}/scan
    ?table=content&limit=100&start={next}
    &fields=url,hashedurl,path,sitename,httpstatus,stream,enriched,language,wordct,global,rollup,description,meta,type
Authorization: {LYTICS_API_TOKEN}
```
Scans return **at most 100 per page.** Page with `_next` until it's empty.

| Check | How | Why it matters |
|---|---|---|
| **Volume** | Total docs. Docs with a URL. Docs per host. | Baseline. |
| **Where the content came from** | Docs per `stream` | If most URLs come from an ad or sync stream instead of web page views, the content table reflects ad landing pages or partner URLs, not the site. |
| **Source hygiene** | Staging/dev/preprod/admin/agency hosts. `httpstatus` 404/410/5xx. Docs with no URL. **Asset URLs** (`.pdf .jpg .png .gif .svg .js .css .json .xml`). **Malformed URLs** (spaces, HTML fragments, typed phrases, a domain nested inside a path). URLs that differ only by query string. | Junk pages add junk topics to real people. |
| **Classification coverage** | Docs with ≥1 topic of relevance > 0. Docs whose topics are **all** relevance 0. Docs never enriched (every `enriched` value is 0 or missing). | Only topics with relevance above 0 reach profiles. A page with all-zero topics gives its visitors **no** interest signal. |
| **Lost core topics** | Pages whose obvious subject (from URL, title or breadcrumb) is present only at relevance 0 | That signal is dropped. These pages need a custom topic rule or meta tags. **Weight it by traffic** (next row). |
| **Traffic-weighted coverage** | For the most-visited pages: how many recent visitors each one has, and whether it carries a usable topic (relevance > 0, not noise). Use whatever visited-URL field the profile has (find it in the schema, e.g. `urls`, with `FILTER AND (urls CONTAINS "<path>", <recency>) FROM user`). Report the share of recent visits that land on a page with a usable topic. | Shows the real cost. A few high-traffic pages with no topic can hide most of the audience. |
| **Noise topics on profiles** | Font names, code words ("JavaScript", "CurrentColor"), UI words ("Link"), checked against profile counts (fieldinfo) | They reach profiles when they have relevance above 0 on some page, however small. Block the ones held by many profiles. Topics that only ever appear at relevance 0 never reach profiles, so don't spend effort blocking them. |
| **Stale status codes** | Re-check the recorded `httpstatus` of the top pages and of any page a plan action depends on, against the live site (`site-assessment.md` sample) | Lytics' recorded status can be out of date: live in Lytics but 404 today, or the reverse. |
| **Freshness** | `enriched` is a **map of source to epoch timestamp**. Take each doc's latest non-zero value, then histogram by month. Count docs classified in the last 7 and 30 days. | Gaps mean new content goes unseen. |
| **Existing custom rules** | Not detectable with a view token. **Don't** read a `custom_topic` entry in `enriched` as evidence: `lio` adds that step to every classification run and stamps it whether or not any rules exist. | Record "existing custom topic rules unknown" as a gap. The plan tells the person creating rules in the UI to check the existing rules first. |
| **Language** | Distribution of `language`, compared with `supported_languages` (if visible). | Only English is processed by default. |
| **Taxonomy size** | Distinct topics with relevance > 0, compared with `num_topics` (default 500). | Above ~500, scores dilute. |
| **Long tail** | Share of topics on exactly one doc, and on fewer than 3. | Single-doc topics are noise. |
| **Head concentration** | Share of docs carrying each of the top 10 topics. | A topic on most pages describes the site, not the person's interest. |
| **Brand and generic topics** | Topics that are brand, company, site or country names, or on the generic list in `topic-curation-principles.md`. | They say nothing about interest. |
| **Duplicates** | Normalize case, punctuation, trailing `s`/`es`, `®`/`™`, `Inc`/`Inc.`, `&`/`and`. Group near-matches (edit distance ≤ 2 on labels of 6+ characters). | Splits one interest across several scores. |
| **Template artifacts** | Topics concentrated on one URL path pattern, and odd labels (doubled words, fragments). | Boilerplate on templated pages gets classified as content. |

## C. Classification quality: does each page's topic list fit the page?
1. **Sample.** If the account has **100 or fewer** classified docs, judge them all. Otherwise take a stratified sample (default 30, up to 50, set by `--sample`) across URL sections and hosts, weighted by section size.
2. **Read.** For each one, look at `url`, `path`, `description`/`meta`, and its top topics by relevance. If `site-assessment.md` ran, also use the live page's title, breadcrumb and category.
3. **Rate it:**
   - **Fit:** `good`, `partial` or `wrong`.
   - **Problem type:** `generic`, `brand`, `off-topic`, `too-narrow`, `template-noise`, `core-topic-at-zero` (the right topic is there, at relevance 0), or `missing-core-topic`.
4. **Record what the topics should be.** These feed custom topic rules in `advise`.
5. **Report the fit rate by section.** One bad section is a different fix from a site-wide problem.

## D. Profiles: is the signal usable for audiences?
Use `GET /api/segment/size?segments=<FilterQL>` for counts, and saved-segment `fieldinfo` for distributions. Start with total scored profiles: `FILTER EXISTS lytics_content FROM user`.

| Check | How | Signal |
|---|---|---|
| **Coverage** | Scored profiles ÷ all profiles; and `FILTER EXISTS lytics_rollup` | Low coverage means few identified page views, or a layer that isn't writing scores. |
| **Over-generalized** | For the top 20 topics by profile count: profiles with score ≥ 0.5 ÷ scored profiles | A topic held by more than ~40% doesn't separate people. |
| **Over-specific** | Count topics held at ≥ 0.5 by fewer than ~0.1% of scored profiles | Too thin to activate. |
| **Noise on profiles** | Profile counts for the noise, generic and brand topics found in step B | Shows how much of the profile signal is junk. |
| **Redirected legacy URLs** | Old URLs on profiles (the visited-URL field) that aren't in the content table, or that redirect on the live site | People who visited old URLs may carry no topics for them. They can be counted, and reached with URL-based audiences. |
| **Stale interest (no decay)** | For the top topics, compare `lytics_content.X >= 0.5` with and without a recency guard (a recent-activity field within 90 days). Find the account's real field with `GET /api/schema/user`; don't assume a name. | Shows how much of each audience is old interest. |
| **Known versus anonymous reach** | For each top topic or Supertopic with a recency guard: how many also have each activation identifier (email, a hashed email, mobile ID, ad IDs, whichever the schema has). Use `EXISTS <field>`. | Tells you which channels can actually reach the audience. Mostly anonymous favours ad platforms and on-site personalization over email. |
| **Supertopic spread and overlap** | Size per Supertopic. Topic-set overlap between each pair. | Near-identical sizes, or overlap above 0.3, means the topic sets overlap too much. |
| **Existing audiences** | For each topic or Supertopic segment: its threshold, whether it has a recency guard, its current size (`GET /api/segment/<id>/size`), and the current profile count of each topic it uses. To see what a guarded version would be, **copy its FilterQL**, add the guard, and size the copy with `GET /api/segment/size?segments=...`. Never edit the live audience. | Flag audiences with no guard, and audiences whose topics have mostly disappeared. The copy-sizing shows the owner the impact of fixing it. |
| **Inferred topics** | Profiles with `lytics_content_inferred`, compared with the layer's `inferred_affinities` flag; plus `fieldinfo` on that field | Check the top inferred topics make sense. In testing, the field was populated on millions of profiles while the config said `inferred_affinities: false`, which is not yet explained. Report what you see; don't assume the flag tells the whole story. |
| **Opportunity (derived)** | Topics with high profile counts but few live (`httpstatus` 200) pages | Content gaps worth telling the customer about. |

Scores are normalized to each person's top topic, and an Supertopic's score averages only the member topics the person has. So **a high threshold alone does not mean high engagement.**

## E. Site (optional)
Run `site-assessment.md` if a site URL is known and fetching it is allowed. Add its findings, including the URL-structure verdict, to the scorecard.

## F. Scorecard
The scorecard is read by people who didn't do the analysis, often marketers. So:
- **Open with "How to read this"** (two or three sentences): what the ratings mean, that each line cites its evidence, and that the plan document says what to do about it.
- **Every area gets a one-sentence italic "What this checks and why it matters" note** before its rating. For example:
  > *Source hygiene: whether the pages Lytics collected are real, live pages on the site. Junk pages add junk interests to real people.*
- Then the rating (**Healthy / Needs work / Critical**) and one or two lines of evidence, in plain words, with numbers.
- Explain any term a marketer wouldn't know the first time it appears (relevance, Supertopic, context layer, recency guard). Keep API field names out of the explanations; put them in the evidence file.

Areas:
1. Source hygiene (including which stream feeds content)
2. Classification coverage and freshness
3. Language coverage
4. Taxonomy size and long tail
5. Brand / generic / noise / duplicate topics, and core topics lost at relevance 0
6. Classification fit (from the sample)
7. Profile signal (coverage, over-generalized, over-specific, stale)
8. Reach (known versus anonymous)
9. Supertopic design (if any)
10. Downstream use (audiences and flows relying on these scores)
11. Site structure and URL-taxonomy verdict (if `site-assessment.md` ran)

End with:
- **Top 5 problems,** ranked by impact on audiences.
- **Gaps:** what couldn't be measured, and why.
- **Open assumptions:** questions you couldn't ask, and the default you used.

Write it in plain language. A marketer should be able to follow it.

**Privacy:** never put a personal name, email or user identity in the scorecard, the evidence file, or any request you send. Refer to people by role.

**Topic labels that are people's names.** The classifier sometimes turns a person's name into a topic (an author, a spokesperson, a reviewer, a member of the public in user-generated content).
- In the scorecard, plan and evidence file, replace such labels with `[person name]`, and count them.
- **Blocking:** recommend blocking them (a person isn't an interest). Put the exact labels **only** in the payload of that block action, in the `.yaml`/`.json`, where they're needed to do the work. Never put them in prose.
- **Raw API responses stay as returned,** in `raw/`. Note in the scorecard that `raw/` can contain such labels, and should be kept local, never shared or committed.

## Evidence file
Save the raw numbers the scorecard cites as JSON, so `advise` and a later re-run can diff against them:
- inventory
- per-topic page counts and profile counts
- duplicate groups
- junk host, asset and malformed URL lists
- stream breakdown
- sample ratings
- size probes, with the exact FilterQL
- site findings
- gaps
- assumptions

A re-assessment after `execute` must produce the same structure.
