# API notes: content, topics, Supertopics

Verified against the `lio` source (develop, October 2026) and five blind read-only test runs on a live account. The public docs at docs.lytics.com lag the code in several places; those are called out below. Base URL is `${LYTICS_API_URL:-https://api.lytics.io}`. Auth is per `../references/auth.md`. URL-encode FilterQL in query strings, with the HTTP tool's encoding or Python's `urllib.parse.quote(ql, safe="")`. Requests are written as `METHOD /path?query`; any HTTP client works (see "Portability" in `SKILL.md`).

## Terms
| UI / docs name | API object | Where it lives |
|---|---|---|
| Context Layer (formerly Interest Engine) | `AffinityConfig` | `/api/content/config` (readable with a view token), `/v2/content/contextlayer` |
| Topic | label in a document's `global` map; in the user's `lytics_content` map | content / user tables |
| **Supertopic** (UI name; formerly Topic Rollup). Use "Supertopic" in anything customer-facing. | `Affinity` (API name) | `/api/content/affinity` |
| Content Collection | segment with `table: content` | `/api/segment?table=content` |
| Custom topic rule | `FilterBasedCustomTopics` | `/v2/content/customtopic` |

## Data shapes worth knowing

### Content document
These are the fields that matter, as returned by a content scan:

| Field | What it is |
|---|---|
| `url`, `hashedurl`, `path`, `sitename` | Page identity |
| `httpstatus`, `httpstatuses` | Fetch status (current, and history) |
| `stream` | The stream the URL arrived from. It can be an ad or sync stream rather than web page views. |
| `language`, `wordct` | Detected language and word count |
| `enriched` | A **map of enrichment source → epoch timestamp**, not a single date. `0` means that source never ran. Use the latest non-zero value as the page's classification date. |
| `fetched`, `created`, `updated` | Lifecycle timestamps |
| `global` | Topic → relevance |
| `rollup` | Supertopic → relevance |
| `google_categories`, `meta`, `description`, `long_description`, `aspects`, `type` | Other classifier output and page metadata |

`global` often contains topics with relevance **0**. Those never reach profiles (next section).

### Context layer config (`/api/content/config`)
- `label` is case-insensitive (`default` or `Default`). The default layer also carries `tags: ["default"]`.
- `blacklisted_topics` / `whitelisted_topics` are **omitted when empty**. A missing field means an empty list.
- Topic block and allow lists can also live in account settings (see below). Read both.

### Profile fields (default layer)
| Field | Meaning |
|---|---|
| `lytics_content` | topic → score (0–1) |
| `lytics_content_inferred` | scores for related topics the person never viewed directly (from the topic graph) |
| `lytics_content_precise` | direct-only scores (when explicit affinities are on) |
| `lytics_rollup` | Supertopic label → score (0–1) |
| `hashedurls` | URLs the scores are built from (up to 200 on web). `FILTER EXISTS hashedurls` sized to 0 in testing even when scores existed, so don't use it as a coverage signal. |

A custom context layer writes to its own `lhs_output_id` / `lhs_affinity_id` fields. Read them from its config.

FilterQL (map key; backticks when the label has spaces):
```
FILTER lytics_content.Mortgages >= 0.5 FROM user
FILTER lytics_rollup.`Credit Cards` >= 0.7 FROM user
FILTER EXISTS lytics_content FROM user
FILTER AND (url CONTAINS "/filters/", httpstatus = 200) FROM content
```

## How scores are computed
Source: `content/topics/models/evaluators.go`, `sysdata/models/content_topics.go`.
- **Raw counts.** Each visited URL adds 1 to each of its topics **with relevance above 0**. How high the relevance is doesn't matter (0.05 counts the same as 0.95), but **relevance 0 is dropped**: those topics never reach profiles (`content/content.go`, `EntToDtmRow`, which deletes topics whose relevance equals 0 before scoring; confirmed live). Visit counts are ignored unless the layer sets `use_activity_counts`.
  - **Noise on profiles** (font names, code words) comes from pages where those labels had relevance above 0, even a tiny one.
  - **A page's real subject at relevance 0** (for example "Trail Running Shoes" on the trail-running category page) is **lost signal.** Visitors get nothing for it. Fix it with a custom topic rule (`value: 1.0`) or meta tags.
- **Related topics** are added from the topic graph, unless `explicit_affinities` is set.
- **Normalization.** Scores are divided by the person's own top score, jittered slightly, then boosted (0.25 → ~0.5, 0.5 → ~0.84, 0.9 → ~0.95). **A person's top topic is always about 1.0, even after one page view.**
- **Top 50 only.** Only the top 50 scores per person are kept.
- **No decay.** `decay_affinities` is stored but not used. Interests on inactive profiles never fade.
- **Supertopic score.** By default this is a weighted average over the Supertopic's member topics *that the person has*.
- **When scores change.** They recalculate when the profile updates, not on a global schedule.

## Read-only query recipes (use these first)
All of these are **GET**, read-only, and save nothing. Prefer them over POST equivalents.

| Need | Call | Notes |
|---|---|---|
| Size any ad-hoc audience | `GET /api/segment/size?segments=<FilterQL>` | Works for `FROM user` and `FROM content`. Use it for all assessment counts. |
| Size a saved audience | `GET /api/segment/<id>/size` | Add `?table=content` for content collections, or you'll get a 404. |
| **Size response shape** | | It varies by route and method: `GET` returns `data` as a **list** (`[n]`); the `POST` ad-hoc form has returned an object (`data.size`). Parse defensively: if `data` is a list, take its first element; if that, or `data`, is an object, read `size`. |
| Topic counts across profiles | `GET /api/segment/<all-users segment id>/fieldinfo?fields=lytics_content&limit=500` | **The main fallback for the topic list.** It returns how many profiles hold each topic. Use `fields=lytics_rollup` for Supertopics. Find the "all users" segment ID in `GET /api/segment?table=user` (slug usually `all`). |
| Topic counts within any ad-hoc audience | `GET /api/segment/fieldinfo?segments=<FilterQL>&fields=lytics_content&limit=500` | **Verified live.** Accepts ad-hoc FilterQL, so it can break down "active in 90 days" profiles, or a **copy** of an existing audience's definition. |
| What-if on an existing audience | Read `GET /api/segment/<id>`, copy its FilterQL, add a guard, then `GET /api/segment/size?segments=<copy>` | The only way the skill evaluates changes to audiences it didn't create. Nothing is saved. |
| Read content documents | `GET /api/segment/<all_documents id>/scan?table=content&limit=100&start=<next>` | **At most 100 per page,** even if you ask for more. Page with `_next`. The cursor value can look the same from page to page. Stop when `_next` is empty **or** a page returns no records you haven't already seen. Add `fields=url,global,httpstatus,stream,enriched,language` to keep pages small. |
| Read documents matching a filter | `GET /api/segment/scan?segments=<FilterQL ... FROM content>&table=content&limit=100&fields=...` | Ad-hoc content scan. Use it to look up specific URLs or test a custom-rule filter. |
| User-table records | Avoid. | Answer audience questions with size and fieldinfo. If a scan is unavoidable, use `GET /api/segment/scan?segments=...&fields=lytics_content,lytics_rollup&limit=10` and **never request or record PII fields**. |

Granular view tokens can read the content table through these segment routes even when the dedicated content endpoints return 403.

## Endpoints and the permission each needs

Permission comes from the route's check in `lio`. Granular roles come from `sysdata/models/role_v2.go` and predefined roles from `role.go`. The default granular **view** token includes `v2_content_view` (content-doc read) and `v2_account_settings_view`. It does **not** include data read or account read, which no granular *view* role grants without exposing personal data (PII).

### Reads
| Method | Path | Permission | View token? | Fallback if 403 |
|---|---|---|---|---|
| GET | `/api/content/config[/:id]` | content-doc read | yes | — |
| GET | `/api/content/affinity[/:id]` | content-doc read | yes | — |
| GET | `/api/account/setting[/:setting]` | account-settings read | yes (staff-only keys such as `supported_languages` and `enrich_content` are hidden) | Ask the customer's Lytics team for the hidden values. |
| GET | `/api/segment?table=user\|content`, size, fieldinfo, scan | segment / table read | yes | — |
| GET | `/api/schema/user` | schema read | yes | — |
| GET | `/v2/flow/ui` | flow read | yes | — |
| GET | `/api/content/topic` (`?config=`) | data read | **no (403)** | Profile-side counts from fieldinfo, plus page-side counts from the content scan's `global`. |
| GET | `/api/content/topic/:id`, `/:id/urls` | data read | no | Count pages per topic from the full content scan's `global` maps. |
| GET | `/api/content/taxonomy`, `/graph`, `/neighborhood`, `/topic/cluster` | data read | no | Build co-occurrence from the content scan (topics appearing on the same pages). |
| GET | `/api/content/doc?urls=` | data read | no | Ad-hoc content scan: `FILTER url = "<url>" FROM content`. |
| GET | `/api/content/doc/classify?url=` | data read | no | None. Judge fit from the scanned doc's `description`/`meta` instead. |
| GET | `/api/schema/user/fieldinfo` | | no (403 in testing) | Segment fieldinfo, above. |
| GET | `/v2/content/contextlayer[/:id]` | account read | no | `/api/content/config`. |
| GET | `/v2/content/customtopic[/:id]` | account read | no | **None.** Record "existing custom topic rules unknown" as a gap. `execute` must list the rules with its own token before creating any. |
| GET | `/v2/content/opportunity` | account read | no | Derive it: topics held by many profiles (fieldinfo) but present on few live pages (scan). |

### Writes (`execute` only, all behind the confirmation gate)
**This skill never calls `DELETE`.** `DELETE` routes are only named so a *person* carrying out a `human_handoff` knows what they're running.

**Automated by `execute`:**

| Action | Method / path | Narrowest token |
|---|---|---|
| Create, update or publish a Supertopic the skill created | `POST` / `PUT /api/content/affinity[/:id]` | `v2_content_manage` |
| AI Supertopic suggestions | `POST /v2/ai/supertopic/suggest?limit=&config=`. **This saves:** it creates a draft Supertopic for every suggestion and returns their IDs. It is a write, so it's never used in `assess` or `advise`. | `v2_content_manage` |
| Topic blocklist on a **non-default** layer | `PUT /api/content/config/<real id>` | `v2_content_manage` |
| Topic blocklist (default layer), blocked pages, allowed params (merge-only) | `PUT /api/account/setting/:key` (body: the JSON value) | `v2_account_settings_manage` **(can change every account setting; `execute` restricts it to these keys)** |

**Not automated; UI, Lytics team or `human_handoff` only:**
- custom topic rules (`/v2/content/customtopic`)
- page-level topic edits (`/api/content/doc/.../topic/...`)
- re-classifying a page (`POST /api/content/doc/classify`)
- domain and path blocks (they delete content; see below)

How API access is enforced on the first three is under review. So this skill documents no permission or token for them, and builds no automated writes on them.

`/v2/content/contextlayer` create, update and delete are **setup, not maintenance**, and out of scope for `execute`.

**Default layer IDs:**
- **Unmigrated account:** the default layer has no stored config. It's built from account settings and shows `id: "default"`. `PUT /api/content/config/default` returns **400** ("Cannot edit default config"), so use the account settings.
- **Migrated account:** the default layer is a stored config tagged `default`, with its own real ID. On these accounts, writing `topic_blacklist` **replaces** the layer's `blacklisted_topics` with the setting's value. Writing the layer doesn't update the setting, and scoring uses the layer's list. If the two lists differ, a write through either path can unblock topics (see `execution.md`, `block_topics`).

**Supertopic names** are unique across the account, **drafts included**. They're compared after simplifying: lowercase, spaces → `_`, repeated `_` collapsed, other symbols dropped. So "Foo Bar", "foo_bar" and "FooBar!" clash. A clash fails with a generic server error ("already exists, possibly as a draft"), so check names before creating.

**`GET /api/content/rollup/:label/urls`** only returns pages for published Supertopics whose layer ID is literally `default`, matched on the exact label. For anything else it returns nothing. Use the content scan's `rollup` map instead.

Body shapes:
- **Supertopic (`Affinity`):** `{"label","description","config_id","topics":[{"label":"X","value":1}],"method","draft":true}`.
  - A weight of 0 or missing becomes 1.0.
  - Publishing (`draft:false`) adds every member topic to the topic allowlist (the account setting for the default layer, otherwise the layer's list), and starts re-evaluation jobs.
  - Allowlisted topics take places in the topic set first, up to `content_max_topics` (default 500), and can push other topics out. Treat this as current behaviour, not a guarantee.
- **Custom topic rule:** `{"type":"filterql"|"url","filter_ql":"<FilterQL or URL pattern>","collection_id":"","config_id":"","topics":[{"label":"X","value":1.0}]}`.
  - **`value` is the relevance it writes onto the page. Set it (e.g. 1.0).**
  - For `type:url`, a label of `*` uses the last wildcard URL segment as the topic.
  - There is no update: changing a rule means delete and recreate, so it is a `human_handoff`.

## Account setting keys
The code registers newer "allowlist/blocklist" names, but the getters still read the **older keys**. Write the older keys.

**What `execute` may change (add-only, superset check):**

| Purpose | Key |
|---|---|
| Topic blocklist (default layer; see the migrated-layer note above) | `topic_blacklist` |
| Blocked pages (**exact** URL, with the domain, without the protocol: `www.example.com/404.html`) | `content_blocked_pages` |
| Allowed URL query params | `content_allowed_params` |

**Content-deleting settings (human handoff only):**

| Purpose | Key | Matching |
|---|---|---|
| Domain blocklist | `content_blacklist_domains` | Host match: `*.example.com` or exact |
| Path blocklist | `content_blacklist_paths` | **Contains** match (`faq` matches any URL containing "faq"). Entries with `*` are **wildcard** path patterns instead (segment-wise; `*$` anchors the end). |
| Domain / path allowlists | `content_whitelist_domains`, `content_whitelist_paths` | Only listed domains or paths are collected |

**Any change to these four keys starts a Lytics job that hard-deletes content records.** It deletes every record whose URL contains **any** entry in the **full** blocklists. When allowlists are set, it also deletes every record that matches **none** of the allowlist entries. The job matches with FilterQL `url CONTAINS "<entry>"` (how a literal `*` behaves there isn't verified).

So before anyone changes one, size the deletion: `GET /api/segment/size?segments=FILTER url CONTAINS "<entry>" FROM content` for each entry in the full proposed list. `content_blocked_pages` and `topic_blacklist` don't start this job.

**Response shape:** `GET /api/account/setting/<key>` returns an object with the value at **`data.value`**, which is `null` when unset. It is not the bare list. Treat `null` as an empty list in the superset check. The `PUT` body is the bare JSON value (the full list).

**Read-only for this skill. Recommend changes as support requests:**

| Setting | Key | Default / note |
|---|---|---|
| Max topics in matrix | `content_max_topics` | default 500 |
| Custom meta-tag topic sources | `content_customprops` | |
| Meta-tag delimiter | `content_custom_delimiter` | default `,` |
| Supported languages | `supported_languages` | Empty means English only |
| Enrichment sources | `enrich_content_sources` | Setting it explicitly silently drops `google_category` and `llm` |
| Content enrichment on/off | `enrich_content` | |
| Monthly classification cap | `enrich_content_maxurls` | default 20,000 |

A setting can only be changed through the API when it's both public and assignable. The `editable` flag in the settings list did not match this in testing, so trust a test write's response over the flag.

## Timing
- **Topic summaries** are cached about 24 hours.
- **New pages** are classified in runs of about 120 URLs, up to the monthly cap.
- **Custom topic rules** apply when a page is classified. Existing pages need re-classifying.
- **Block and allow changes** take effect on the next topic-matrix rebuild, and on profiles as they update.
- **Supertopic publish** starts background jobs. Profiles update as people return; the docs say up to two weeks for inactive users.
- **Inactive profiles** keep their old topic scores indefinitely (no decay). Clearing them needs a full re-score by Lytics staff, so it's a support request.

## Not verified (test before relying on it)
- Whether `type: url` custom topic rules pass create-time validation. The handler runs FilterQL validation on `filter_ql` whatever the type.
- Whether Supertopic publish backfills `lytics_rollup` for existing profiles immediately.
- The real context-layer limit: the docs say 10, the code falls back to 5, and the setting default is 2.
- Recommendation filtering by Supertopic (`rollups`) is marked TODO in the code.
