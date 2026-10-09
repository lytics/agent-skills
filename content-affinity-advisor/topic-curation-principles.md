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
  - **Affinities:** 8 to 30 business-meaningful groups of topics (Home Buying, Protection, Performance Footwear). Affinities are what marketers target. Topics are the evidence underneath.
- **Every topic earns its place.** It appears on enough pages to matter (rule of thumb: 3 or more). It means one thing. It maps to at most one or two Affinities.
- **Every Affinity is activatable.** It has a clear business owner or use case, it is sized for at least one channel, and it doesn't heavily overlap another Affinity.

## Remove or demote
- **Brand and company names:** the customer's own brand, sub-brands, and group names. They're on every page.
- **Site furniture:** Home, Page, Information, Customer, Account, Login, Menu, Search, Cookie, Privacy, Terms, Contact, Help, Name, Way, Website, Online.
- **Geography words that aren't an interest:** the country or region the site serves. Keep geography only when it *is* the interest, as in travel destinations.
- **Template artifacts:** topics produced by repeated boilerplate on templated pages. Spot them by heavy concentration on one URL pattern, or by odd labels like doubled words.
- **Single-page topics:** these are noise unless they belong in the target taxonomy.
- **Content from the wrong sources:** staging, dev, preprod, agency and admin hosts; dead pages; careers and legal sections when they aren't a marketing interest.

## Merge
Lytics has no topic rename or merge. Get the same result with these levers:
1. **Group duplicates under one Affinity** (Mortgage, Mortgages, Remortgage → "Mortgages"). This is the cleanest option, and it doesn't touch the documents.
2. **Block the variants and allow the canonical form,** so only one label is scored.
3. **Add the canonical topic** to the affected pages with a custom topic rule.

## Enrich
Add topics when the classifier misses the page's real subject. In order of preference:
1. **Customer-controlled markup.** `<meta name="lytics:topics" content="Mortgages, First-time Buyers">` on page templates, or `keywords`, or a CMS field read through `content_customprops`. This is the best long-term fix, because it survives re-classification. Only recommend it if the customer can change their site.
2. **Rule-based custom topics.** These live inside Lytics (`/v2/content/customtopic`) and apply topics to every page matching a FilterQL condition or URL pattern. They're the main lever when the customer can't touch their site.
3. **Page-level topic edits.** These are for a small number of high-value pages (`/api/content/doc/.../topic/...`). They don't scale, so use them for landing pages and key product pages.
4. **Allowlist.** Forces an important topic into the scored set even when it's rare.

## Judge "too general" and "too specific" on profiles, not just pages
A topic map can look fine at page level and still produce useless profiles:
- **Over-generalized:** most people's top topics are the same few broad ones. Fix it by removing the generic topics, and by giving Affinities a narrower membership.
- **Over-specific:** scores scatter across topics that only a handful of people hold. Fix it by rolling those topics into Affinities and dropping the long tail.

## Micro-audiences from scores
Scores are relative to each person's own strongest interest, and they never decay. So:
- **Pair every score threshold with an engagement guard:** recent activity, page-view count, or a minimum number of relevant pages.
- **Prefer tiers over one cut:** high (≥ 0.8), some (0.5–0.8). Size each tier before proposing it.
- **Prefer Affinity scores (`lytics_rollup`)** over single topics for activation. Use single topics for narrow, high-intent cases.
- **Expect lag.** New or changed Affinities take days to populate, longer for inactive profiles.

## Customer-control matrix
Pick levers based on what the customer can actually do:

| Customer can... | Primary levers |
|---|---|
| Edit site templates / CMS | Meta tags (`lytics:topics`), then Affinities |
| Not edit the site, but has a Lytics admin | Custom topic rules, block/allow lists, domain/path exclusions, Affinities |
| Only use the Lytics UI | Topic blocking in the UI, the Affinity builder, audiences; everything else as requests to their Lytics team |
| Has a product catalogue in Lytics | A custom context layer on the product table, with the category tree as the taxonomy |

## Things to avoid
- Don't block a topic that an existing audience or Affinity uses without flagging that dependency.
- Don't propose hundreds of page-level edits. Use a rule.
- Don't promise immediate results. Every change has a re-scoring lag.
- Don't treat the classifier as ground truth when the page's URL, title and description clearly say otherwise.
