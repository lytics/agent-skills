# Topic curation principles

The judgement rules behind `assess`, `advise` and `execute`. These are guidance from practice, not platform limits. The platform limits are in `api-notes.md`.

## What the topic map is (and isn't)
- **It's a starting point.** The topics Lytics shows are whatever the classifier pulled from whatever was scraped. Treat them as raw material, never as the customer's taxonomy.
- **Three things decide quality:**
  - what was scraped (templates, nav, footers and cookie banners all get read)
  - which classifier ran (Google NLP by default; Diffbot on older accounts)
  - whether the site carries intentional markup (`lytics:topics`, `keywords`, CMS fields)
- **Most customers have no intentional taxonomy.** Building one is the real work. The skill's job is to make that tractable:
  - propose a taxonomy
  - map the messy topics onto it
  - use whichever levers the customer actually controls

## Target shape
- **Size.** Aim for a few hundred meaningful topics: roughly 150 to 500 in the scored set. Above ~500, interest spreads thin and scores dilute. Below ~50, profiles collapse into the same few buckets.
- **Two levels:**
  - **Topics:** specific, reusable across many pages (Mortgages, Travel Insurance, Running Shoes).
  - **Supertopics:** 8 to 30 business-meaningful groups of topics (Home Buying, Protection, Performance Footwear). Supertopics are what marketers target. Topics are the evidence underneath.
- **Every topic earns its place.** It appears on enough pages to matter (rule of thumb: 3 or more). It means one thing. It maps to at most one or two Supertopics.
- **Every Supertopic is activatable.** It has a clear business owner or use case, it is sized for at least one channel, and it doesn't heavily overlap another Supertopic.

## Remove or demote
- **Brand and company names:** the customer's own brand, sub-brands, and group names. They're on every page.
- **Site furniture:** Home, Page, Information, Customer, Account, Login, Menu, Search, Cookie, Privacy, Terms, Contact, Help, Name, Way, Website, Online.
- **Geography words that aren't an interest:** the country or region the site serves. Keep geography only when it *is* the interest, as in travel destinations.
- **Template artifacts:** topics produced by repeated boilerplate on templated pages. Spot them by heavy concentration on one URL pattern, or by odd labels like doubled words.
- **Noise topics:** font names, code words ("JavaScript", "CurrentColor"), UI words ("Link"). Any relevance above 0 on any page puts them on profiles, so block the ones held by many profiles. Topics that only ever appear at relevance 0 never reach profiles, so ignore them.
- **Core topics stuck at relevance 0:** when a page's real subject is present only at relevance 0, its visitors get nothing. This is often the biggest loss on high-traffic pages. Fix it with rules or meta tags, not blocks.
- **Single-page topics:** these are noise unless they belong in the target taxonomy.
- **Content from the wrong sources:** staging, dev, preprod, agency and admin hosts; dead pages; careers and legal sections when they aren't a marketing interest.

## Merge
Lytics has no topic rename or merge. Get the same result with these levers:
1. **Group duplicates under one Supertopic** (Mortgage, Mortgages, Remortgage → "Mortgages"). This is the cleanest option, and it doesn't touch the documents.
2. **Block the variants and allow the canonical form,** so only one label is scored.
3. **Add the canonical topic** to the affected pages with a custom topic rule.

## Pick the taxonomy source by site type
The right taxonomy source depends on what kind of site it is (details in `site-assessment.md`):
- **Content / product-is-the-site (e.g. a jobs or reviews site):** large, regular, semantic URL directories are often the best taxonomy. Use URL-pattern custom topic rules.
- **Brand / marketing (e.g. a single-brand consumer-product site):** small sites with marketing-driven paths. Hand-build 8 to 30 interest areas, and use filter rules per section.
- **Retail / catalogue (e.g. a warehouse retailer):** IDs, SKUs and query strings make URLs unreliable. Use breadcrumbs, structured data or a product feed. A catalogue-based context layer is a setup project, outside this skill.

Never assume. Test the URL structure against the checks in `site-assessment.md` before recommending it.

## Enrich
Add topics when the classifier misses the page's real subject. In order of preference:
1. **Customer-controlled markup.** `<meta name="lytics:topics" content="Mortgages, First-time Buyers">` on page templates, or `keywords`, or a CMS field read through `content_customprops`. This is the best long-term fix, because it survives re-classification. Only recommend it if the customer can change their site.
2. **Rule-based custom topics.** These live inside Lytics (`/v2/content/customtopic`) and apply topics to every page matching a FilterQL condition or URL pattern. They're the main lever when the customer can't touch their site.
3. **Page-level topic edits.** These are for a small number of high-value pages (`/api/content/doc/.../topic/...`). They don't scale, so use them for landing pages and key product pages.
4. **Allowlist.** Forces an important topic into the scored set even when it's rare. Publishing a Supertopic does this for its own topics. Any other allowlist change is a human handoff, because it can push other topics out of the 500-topic set.

## Judge "too general" and "too specific" on profiles, not just pages
A topic map can look fine at page level and still produce useless profiles:
- **Over-generalized:** most people's top topics are the same few broad ones. Fix it by removing the generic topics, and by giving Supertopics a narrower membership.
- **Over-specific:** scores scatter across topics that only a handful of people hold. Fix it by rolling those topics into Supertopics and dropping the long tail.

## Micro-audiences from scores
Scores are relative to each person's own strongest interest, and they never decay. So:
- **Pair every score threshold with an engagement guard:** recent activity, page-view count, or a minimum number of relevant pages.
- **Tiers must separate people.** Because scores are relative, most active people score high on their main interest. Check the distribution first. If score tiers don't split the audience, use one score cut, and tier by recency or engagement depth instead.
- **Prefer Supertopic scores (`lytics_rollup`)** over single topics for activation. Use single topics for narrow, high-intent cases.
- **Expect lag.** New or changed Supertopics take days to populate, longer for inactive profiles.

## Customer-control matrix
Pick levers based on what the customer can actually do:

| Customer can... | Primary levers |
|---|---|
| Edit site templates / CMS | Meta tags (`lytics:topics`), then Supertopics |
| Not edit the site, but has a Lytics admin | Custom topic rules (in the UI), topic blocks, exact-page blocks, Supertopics. Domain and path blocks are a deliberate decision: they delete matching content records. |
| Only use the Lytics UI | Topic blocking in the UI, the Supertopic builder, audiences; everything else as requests to their Lytics team |
| Has a product catalogue in Lytics | A custom context layer on the product table, with the category tree as the taxonomy |

## Things to avoid
- Don't block a topic that an existing audience or Supertopic uses without flagging that dependency.
- Don't propose hundreds of page-level edits. Use a rule.
- Don't promise immediate results. Every change has a re-scoring lag.
- Don't treat the classifier as ground truth when the page's URL, title and description clearly say otherwise.
