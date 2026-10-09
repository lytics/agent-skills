# Site assessment: checking the live website

Optional part of `assess`. Run it when a site URL is known, either from `--site` or from the content table's most common hosts. It answers three questions the Lytics data alone can't:
1. Is Lytics seeing the site's real content, or a skewed slice of it?
2. Does the site already carry a usable taxonomy (URL structure, breadcrumbs, structured data, meta tags)?
3. Which topic strategy fits **this kind** of site?

## Ground rules (every site)
- **Read-only, polite, small.**
  - Fetch `robots.txt` first and honour its `Disallow` rules.
  - Use a generic, honest User-Agent such as `lytics-content-affinity (Lytics site assessment)`. **Never include a person's name, email or account in any header or request.**
  - At most one request every 2 seconds.
  - Hard caps: **50 HTML pages** and **20 sitemap files** per run.
- **Never crawl a whole site.** Sample it. A sitemap tells you the site's size without fetching its pages.
- **Don't get past bot protection.** If you hit a CAPTCHA, a login wall or a block page, stop, record a gap, and continue with Lytics data only. Never try to defeat it.
- **Public pages only.** No logged-in areas, no forms, no search queries that create load.
- If the customer has asked that their site not be fetched, skip this file entirely and say so in the scorecard.

## Step 1: Classify the site type
Decide the type before sampling. It changes what you sample and what you recommend.

| Type | Looks like | Example | Typical scale | Taxonomy usually comes from |
|---|---|---|---|---|
| **Brand / marketing** | Product range pages, how-to and support content, a blog. A few hundred to a few thousand URLs. | a single-brand consumer-product site | under 5k URLs | Hand-built interest areas. URL sections are often too coarse or marketing-driven to use as-is. |
| **Content / product-is-the-site** | The site *is* the product: listings, reviews, articles, user-generated content. Very deep, very regular URL patterns. | a jobs or reviews site, a publisher, a marketplace | 100k to millions | **URL directory structure**, if it's clean and semantic. Often the best and cheapest taxonomy. |
| **Retail / catalogue** | Product detail pages identified by SKUs or IDs, faceted navigation, query-string URLs. | a warehouse or big-box retailer | 10k to millions | **Product category data** (breadcrumbs, structured data, a product feed), not the URL. URLs are often unreliable ("wonky"). |
| **Mixed / regional** | Several of the above across hosts or country paths. | a multinational bank | varies | Assess each host or section separately. |

Signals to decide:
- sitemap size and structure (one sitemap, or an index of many)
- URL shape: readable slugs versus IDs, query strings and hashes
- presence of `Product` versus `Article` structured data
- what the content table's hosts and paths look like

If it's unclear, say which type you assumed and why. That's an **open assumption** to confirm with the customer.

## Step 2: Sitemaps (size and coverage)
1. Find sitemaps in `robots.txt` (`Sitemap:` lines). Otherwise try `/sitemap.xml`.
2. If it's a sitemap index, list the child sitemaps and their names (they often reveal sections: `sitemap-products.xml`, `sitemap-blog.xml`).
   - **Small sites (one sitemap, or an index under ~20 files):** fetch them all, and count URLs per section.
   - **Large sites:** don't fetch every child. Fetch up to 20, spread across the section names, and estimate totals from those. Record that it's an estimate.
3. **Clean the sitemap list first:** de-duplicate it, and note entries that redirect (a `HEAD` or `GET` on a small sample; don't follow every one on large sites). Redirecting entries and their targets should be counted once.
4. **Coverage check:** compare sitemap URLs (normalized: lowercase host, no trailing slash, no query) against content-table URLs.

| Measure | Meaning |
|---|---|
| Sitemap URLs found in the content table | How much of the real site Lytics has seen and classified |
| Content-table URLs **not** in any sitemap | Candidates for junk: old, staging, asset, malformed or third-party URLs |
| Sitemap sections with zero content-table coverage | Content Lytics never saw. Usually because nobody visits it, or because the tag isn't on it. |

## Step 3: Page sampling (what's actually on the page)
Sample up to 50 live pages, spread across sitemap sections and weighted toward sections with the most URLs. Include the homepage, the main category pages, and a few deep pages.

For each page, record only structural and taxonomy signals, never personal data:
- `<title>`, `<h1>`, meta description
- **Existing topic markup:** `<meta name="lytics:topics">`, `<meta name="keywords">`, `article:tag` / `article:section`, and other `og:` or CMS meta tags
- **Breadcrumbs:** visible ones, and JSON-LD `BreadcrumbList`
- **Structured data:** JSON-LD `@type` (`Product`, `Article`, `FAQPage`, ...), plus `category` / `articleSection`
- **Boilerplate share:** a rough estimate of navigation, footer and cookie-banner text against main content. Heavy boilerplate explains junk topics.
- **How the Lytics tag is loaded,** without loading or executing anything:
  - **Direct:** a script loaded from `c.lytics.io`, `cdn.lytics.io` or `api.lytics.io`, or containing `jstag` (`window.jstag`, `jstag.init`). Match those exact strings. **Don't match the bare substring `lytics`**: it also matches "Analytics" and gives false positives.
  - **Through a tag manager:** a Google Tag Manager (`googletagmanager.com/gtm.js`), Tealium (`utag.js`), Adobe Launch or Segment snippet. The Lytics tag then won't appear in the HTML.

  Record "loaded via <tag manager>, presence can't be confirmed from the HTML". Don't claim it's missing. Profile-side evidence (scored profiles arriving through the web stream) is the better proof that the tag works.

Compare each sampled page with its content-table record (if it has one): do Lytics' topics match the page's title, breadcrumb and category? This strengthens the classification-fit check in `assessment.md`.

**Watch for disagreements between structured data and live URLs.** A breadcrumb's `item` URLs may point to a different path than the live page (for example `/better-health/...` versus `/why-brand/better-health/...`, after a site restructure).
- **When building URL rules,** trust the live URLs and the content table, not the breadcrumb links.
- **Flag the mismatch** as a `customer_site_spec` item.
- **If breadcrumbs would feed topics** via meta tags, use their *names*, not their URLs.

## Step 4: Can the URL structure be the taxonomy?
Score the URL structure against these tests:

| Test | Good sign | Bad sign |
|---|---|---|
| **Readable** | Path segments are words (`/water-filters/faucet/`) | IDs, hashes, SKUs (`/p/100512345`, `/a9f3e1/`) |
| **Consistent depth** | The same level means the same thing site-wide (level 1 = category, level 2 = subcategory) | Depth varies at random. Campaign paths mix with content paths. |
| **Manageable breadth** | 5 to 50 distinct first-level sections, each with real volume | Thousands of first-level values, or one giant bucket |
| **Stable** | Paths don't carry dates, sessions or tracking | Query strings or tracking parameters define the page |
| **Semantic** | Sections match real interest areas | Sections are organizational ("/about/", "/corporate/") or campaign-driven |

**Verdict** (record it in the scorecard):
- **Use the URL structure:** most tests pass. Recommend custom topic rules by URL pattern, one per section, with a wildcard (`*`) label where the segment itself is the topic. Typical for content / product-is-the-site.
- **Use the URL structure partly:** some sections are clean. Use URL rules for those, and other sources for the rest.
- **Don't use the URL structure:** most tests fail (typical for retail with IDs). Recommend breadcrumbs or structured data via meta tags / `content_customprops`, or a product-catalogue context layer. The catalogue layer is a `setup_recommendation`; this skill doesn't build it.

## Step 5: Inferred topics
`lytics_content_inferred` holds topics people never viewed directly, inferred from the topic graph.
- **If the topic map is noisy,** inferred topics spread the noise further. Recommend fixing the map before relying on them.
- **If the map is clean and well-connected,** inferred topics add useful reach for sparse profiles (one or two page views).
- **Check it:** compare `fieldinfo` on `lytics_content_inferred` with `lytics_content`. Do the top inferred topics make sense for this site type?

## Output
Add a **Site** section to the scorecard:
- the site type, and the reason
- sitemap size and coverage
- taxonomy sources found (URL / breadcrumbs / structured data / meta)
- the URL-structure verdict
- boilerplate notes
- any blocks hit

Add the raw counts to the evidence file under `site`. `advise` uses the verdict to choose levers.
