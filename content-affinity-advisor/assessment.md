# Assessment: auditing a content context layer

Read-only. Produces a scorecard (markdown) and an evidence file (JSON). Every finding must cite the data behind it: counts, example URLs, example topics. Never report a problem you didn't measure.

Use `topic-curation-principles.md` for the judgement calls, and `api-notes.md` for exact endpoints and fallbacks.

## A. Inventory: what exists

Collect each of these, and record any 403/404 in a `gaps` list.

| What | Call | Notes |
|---|---|---|
| Context layers | `GET /v2/content/contextlayer`, fallback `GET /api/content/config` | One `AffinityConfig` per layer. `label: default` is the standard topic layer. Record `rhs_table`, `rhs_feature_ids`, `lhs_output_id`, `lhs_affinity_id`, `num_topics`, `blacklisted_topics`, `whitelisted_topics`, `explicit_affinities`, `inferred_affinities`, `use_activity_counts`, `decay_affinities`. |
| Affinities | `GET /api/content/affinity` | `label`, `config_id`, `topics` (label and weight), `method`, `draft`, `doc_count`, `created`, `updated`. |
| Topic list | `GET /api/content/topic?config=<id>` | Needs content-doc read scope. If you get 403, rebuild it from the content scan (step B). |
| Taxonomy / clusters | `GET /api/content/taxonomy`, `GET /api/content/topic/cluster` | Optional. Shows how the platform relates topics. |
| Custom topic rules | `GET /v2/content/customtopic` | Rule-based topics (FilterQL or URL pattern). |
| Account content settings | `GET /api/account/setting` | Filter to the keys in `api-notes.md`: blocklist/allowlist, domain/path filters, max topics, sources, languages. |
| Content collections | `GET /api/segment?table=content` | Note which collections are default (`all_documents`, `recently_classified_documents`, ...) and which are customer-built. |
| Profile score fields | `GET /api/schema/user` | Confirm `lytics_content`, `lytics_content_inferred`, `lytics_rollup`, and the field each custom layer writes. |
| Downstream use | `GET /api/segment?table=user` | Find segments whose FilterQL references `lytics_content`, `lytics_content_inferred`, `lytics_rollup`, or a custom layer's output field. Also `GET /v2/flow/ui` for `affinity` steps. |
| Opportunity report | `GET /v2/content/opportunity` | Topics with high audience interest but thin content. |

## B. Content: what the classifier saw

1. Find the `all_documents` collection ID from the content segment list.
2. Scan every page:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${ALL_DOCS_ID}/scan?table=content&limit=200&start=${NEXT}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Page with `_next` until it's empty.

Useful fields on each document:
- `url`, `hashedurl`, `path`, `sitename`
- `httpstatus` and `httpstatuses`
- `language`, `wordct`
- `enriched`, `fetched`, `created`
- `global` (topic → relevance), `rollup` (Affinity → relevance)
- `google_categories`, `meta`, `description`, `aspects`, `stream`

Measure the following, per context layer:

| Check | How | Why it matters |
|---|---|---|
| **Volume** | Total docs. Docs with a URL. Docs per host. | Baseline. |
| **Source hygiene** | Hosts that look like staging/dev/preprod/admin/agency (`dev.`, `staging`, `preprod`, `uat`, `test`, `admin.`, agency domains). Docs with `httpstatus` 404/410/5xx. Docs with no URL. URLs differing only by query string. | Junk pages add junk topics to real people. |
| **Classification coverage** | Docs with ≥1 topic of relevance > 0. Docs where every topic is 0. Docs with no `enriched` date. | Unclassified pages contribute nothing to scores. |
| **Freshness** | Histogram of `enriched` by month. Docs classified in the last 7 and 30 days. | Batches with gaps mean new content is invisible. |
| **Language** | Distribution of `language`, compared to the `supported_languages` setting. | Only English is processed by default. |
| **Topic size** | Distinct topics across all docs. Compare to `num_topics` / `content_max_topics` (default 500). | Above ~500, scores dilute. |
| **Long tail** | Share of topics on exactly one doc. Share on fewer than 3. | Single-doc topics are noise. |
| **Head concentration** | Share of docs carrying each of the top 10 topics. | A topic on most pages describes the site, not the interest. |
| **Brand and generic** | Topics matching the brand, company, site or country names, or the generic list in `topic-curation-principles.md`. | These say nothing about interest. |
| **Duplicates** | Normalize: case, punctuation, trailing `s`/`es`, `Inc`/`Inc.`, `&`/`and`. Group near-matches (edit distance ≤ 2 on labels ≥ 6 characters). | Splits one interest across several scores. |
| **Template artifacts** | Topics far more common on one URL path pattern than anywhere else, plus odd labels ("Capital Repayment Repayment", "Way"). | Boilerplate on templated pages gets classified as content. |

## C. Classification quality: does each page's topic list fit the page?

The numbers in step B can't catch a classifier that is confidently wrong. Judge it directly:

1. Take a stratified sample (default 30, set with `--sample`). Draw it across URL path sections and hosts, weighted toward sections with many docs.
2. For each sampled doc, look at `url`, `path`, `description`/`meta`, and its top topics by relevance.
3. If the description is thin, the page can be re-classified for comparison with `GET /api/content/doc/classify?url=<url>` (preview only, nothing is saved). Use this sparingly, because it calls the classifier.
4. Rate each page on two things:
   - **Fit**: `good`, `partial` or `wrong`.
   - **Problem type**: `generic`, `brand`, `off-topic`, `too-narrow`, `template-noise` or `missing-core-topic`.
5. Record what the page's topics *should* be. These feed the custom-topic rules in `advise`.

Report the fit rate per path section. One bad section (such as product detail templates) is a different fix from a site-wide problem.

## D. Profiles: is the signal usable for audiences?

Use ad-hoc sizing (`POST /api/segment/size`, body is raw FilterQL, nothing saved). For example:

```
FILTER EXISTS lytics_content FROM user
FILTER EXISTS lytics_rollup FROM user
FILTER lytics_content.`<topic>` >= 0.5 FROM user          -- top 20 topics by doc count
FILTER lytics_rollup.`<affinity label>` >= 0.5 FROM user  -- each Affinity
```

| Check | Signal |
|---|---|
| **Coverage** | Profiles with any topic score, out of total profiles. Low coverage usually means few identified page views, or a layer that isn't writing scores. |
| **Over-generalized** | A topic held at ≥ 0.5 by a very large share of scored profiles (rule of thumb: > 40%). It doesn't separate people. |
| **Over-specific** | Many topics held at ≥ 0.5 by fewer than ~0.1% of scored profiles. Too thin to activate. |
| **Affinity spread** | Affinity sizes should differ meaningfully. Near-identical sizes suggest overlapping topic sets. |
| **Affinity overlap** | Overlap of member topics between every pair of Affinities. Above 0.3 is worth flagging. |
| **Existing audiences** | For each segment that uses topic or Affinity scores: its threshold, whether it has an engagement guard, and its current size. |

Field-level distributions (`/api/segment/{id}/fieldinfo`) give the best view of the top topics across an audience, if the token allows it. Some view tokens get 403, so treat it as optional.

Remember how scores are built (see `api-notes.md`):
- They're normalized to the person's own top topic.
- The default Affinity score averages only the member topics the person has.

So a high threshold on its own does **not** mean high engagement. Flag every topic audience that has no recency or volume guard.

## E. Scorecard

Rate each area **Healthy / Needs work / Critical**, with one line of evidence each:

1. Source hygiene
2. Classification coverage and freshness
3. Language coverage
4. Taxonomy size and long tail
5. Brand / generic / duplicate noise
6. Classification fit (from the sample)
7. Profile signal (coverage, over-generalized, over-specific)
8. Affinity design (if any exist)
9. Downstream use (audiences and flows relying on these scores)

End with:
- **Top 5 problems**, ranked by impact on audiences.
- **Gaps**: what couldn't be measured, and why.

Write the scorecard in plain language. The audience is a marketer as much as an engineer.

## Evidence file
Save the raw numbers the scorecard cites as JSON, so `advise` and a re-run can diff against them. Include:
- per-topic doc counts
- duplicate groups
- the junk host list
- sample ratings
- size probes
- the inventory

A re-assessment after `execute` should produce the same structure, so the before and after can be compared.
