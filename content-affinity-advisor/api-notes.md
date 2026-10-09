# API notes: content, topics, Affinities

Verified against the `lio` source (develop, October 2026). The public docs at docs.lytics.com lag the code in several places; those are called out below. Base URL is `${LYTICS_API_URL:-https://api.lytics.io}`. Auth is per `../references/auth.md`.

## Terms
| UI / docs name | API object | Where it lives |
|---|---|---|
| Context Layer (formerly Interest Engine) | `AffinityConfig` | `/api/content/config`, `/v2/content/contextlayer` |
| Topic | label in a document's `global` map; in the user's `lytics_content` map | content table / user table |
| Affinity (formerly Topic Rollup; "supertopic") | `Affinity` | `/api/content/affinity` |
| Content Collection | segment with `table: content` | `/api/segment?table=content`, `/v2/segment` |
| Custom topic rule | `FilterBasedCustomTopics` | `/v2/content/customtopic` |

## Profile fields (default layer)
| Field | Meaning |
|---|---|
| `lytics_content` | topic → score (0–1) |
| `lytics_content_inferred` | scores for related topics the person never viewed directly |
| `lytics_content_precise` | direct-only scores (written when explicit affinities are on) |
| `lytics_rollup` | Affinity label → score (0–1) |
| `hashedurls` | the URLs the scores are built from (up to 200 on web) |

A custom context layer writes to its own `lhs_output_id` / `lhs_affinity_id` fields. Read them from the layer's config.

FilterQL (map key; backticks when the label has spaces):
```
FILTER lytics_content.Mortgages >= 0.5 FROM user
FILTER lytics_rollup.`Credit Cards` >= 0.7 FROM user
FILTER EXISTS lytics_content FROM user
```

## How scores are computed
Source: `content/topics/models/evaluators.go`, `sysdata/models/content_topics.go`.
- Each visited URL adds 1 to each of its topics, regardless of the page's relevance values. Visit counts are ignored unless the layer sets `use_activity_counts`.
- Related topics are added from the topic graph (unless `explicit_affinities`).
- Scores are divided by the person's own top score, jittered slightly, then passed through a boost curve: 0.25 → ~0.5, 0.5 → ~0.84, 0.9 → ~0.95. **A person's top topic is always about 1.0, even after one page view.**
- Only the top 50 per person are kept.
- **No decay:** `decay_affinities` is stored but not used.
- **Affinity score:** by default, a weighted average of the person's scores over the Affinity's member topics *that the person has*. One strong member topic is enough for a high Affinity score.
- Scores recalculate when the profile updates (new activity), not on a global schedule.

## Endpoints

R = read, W = write. "Scope" is the permission the route checks. A minted view token may not include content-doc or account scopes; HSBC view tokens got 403 on several of these.

### Inventory and reads
| Method | Path | R/W | Scope | Notes |
|---|---|---|---|---|
| GET | `/api/content/config[/:id]` | R | content-doc read | Context layers. The most reliable way to read a layer. |
| GET | `/v2/content/contextlayer[/:id]` | R | account read | Same data. Some view tokens get 403; fall back to `/api/content/config`. |
| GET | `/api/content/affinity[/:id]` | R | content-doc read | Affinities. **Not in the public API reference.** `/api/content/topicrollup` (documented) no longer exists. |
| GET | `/api/content/topic` (`?config=`) | R | data read | Topic list (top 500). Cached ~24h. Returned 403 to some view tokens that could still scan content; cause not confirmed. Fallback: rebuild from the content scan. |
| GET | `/api/content/topic/:topicId`, `/:topicId/urls` | R | | One topic's summary / pages |
| GET | `/api/content/topic/cluster[/:topicId]` | R | | Topic clusters (POST variant is also read-only) |
| GET | `/api/content/taxonomy`, `/graph`, `/neighborhood` | R | data read | Topic relationships |
| GET | `/api/content/rollup/:label/urls` | R | data read | Pages tagged with an Affinity |
| GET | `/api/content/doc?urls=` | R | data read | Document detail |
| GET | `/api/content/doc/classify?url=` | R | data read | Preview classification (nothing saved; calls the classifier) |
| GET | `/v2/content/customtopic[/:id]` | R | account read | Custom topic rules |
| GET | `/v2/content/opportunity` | R | account read | High-interest / low-content topics |
| GET | `/api/account/setting[/:setting]` | R | | Account settings (see keys below) |
| GET | `/api/segment?table=content` | R | | Content collections |
| GET | `/api/segment/:id/scan?table=content&limit=200&start=` | R | data read | **Full document dump.** Works with data-read tokens even when the topic endpoints 403. |
| POST | `/api/segment/size` (body: raw FilterQL, `text/plain`) | R | | Ad-hoc audience size, nothing saved |

### Writes (all go through the confirmation gate)
| Method | Path | Scope | Effect |
|---|---|---|---|
| POST | `/api/content/affinity` (`?embed=true` optional) | content-doc create | Create an Affinity. Body: `{"label","description","config_id","topics":[{"label","value"}],"method","draft"}`. A weight of 0 or missing becomes 1.0. If `draft` is false it **publishes**: adds its topics to the topic allowlist, then starts re-evaluation and topic-matrix jobs. |
| PUT | `/api/content/affinity/:id` | content-doc update | Update. Setting `draft` from true to false publishes. |
| DELETE | `/api/content/affinity/:id` | content-doc delete | Delete. Check downstream audiences first. |
| POST | `/v2/ai/supertopic/suggest` (`?limit=1-50`, default 8; `?config=`) | **content-doc create** | AI-suggested Affinities: `name`, `members`, `reason`, and `similar_to` (overlap with existing Affinities). It saves nothing, but it needs a create-scope token and makes an LLM call. |
| PUT | `/api/content/config/:id` | content-doc update | Update a layer: `blacklisted_topics`, `whitelisted_topics`, `num_topics`, evaluation flags |
| POST/DEL | `/v2/content/contextlayer[/:id]` | account read (sic) | Create or delete a layer. Custom layers are an advanced change; involve the customer's Lytics team. |
| POST | `/v2/content/customtopic` | account read (sic) | Create a rule. Body: `{"type":"filterql"\|"url","filter_ql":"<FilterQL or URL pattern>","collection_id":"<optional content segment id>","config_id":"<optional>","topics":[{"label":"Mortgages","value":1.0}]}`. **Set `value` explicitly (e.g. 1.0).** The value becomes the topic's relevance on the page, and 0 means the topic counts for nothing. For `type: url`, a topic label of `*` uses the last wildcard segment of the URL as the topic. |
| DELETE | `/v2/content/customtopic/:id` | account read | Delete a rule. There is no PUT; to change a rule, delete it and recreate it. |
| POST | `/api/content/doc/:docField/:docId/topic/:topicLabel?relevance=` | data read (sic) | Set one topic on one page. `docField` is `hashedurl` or `url`. Relevance defaults to 1.0. |
| DELETE | `/api/content/doc/:docField/:docId/topic/:topicLabel` | data read | Remove one topic from one page (fields can't be deleted, so this zeroes it). |
| POST | `/api/content/doc/classify?url=` | data read | Classify a URL and save it to the content table. Use this to re-classify specific pages after rule changes. |
| POST/PUT | `/api/account/setting/:setting` (body: the JSON value) | | Change an account setting. Only settings marked public and assignable can be changed; others return 403 "not editable". |

"(sic)" means the route checks a weaker scope than its effect suggests. Gate these writes exactly like the others.

## Account setting keys (the ones the code actually reads)
The code registers newer "allowlist/blocklist" names, but the getters still read the older keys. **Write the older keys.** The newer ones are private and not assignable.

| Setting | Key to use | Editable via API |
|---|---|---|
| Topic blocklist | `topic_blacklist` | yes |
| Topic allowlist | `topic_whitelist` | yes |
| Domain allowlist / blocklist | `content_whitelist_domains` / `content_blacklist_domains` | yes |
| Path allowlist / blocklist | `content_whitelist_paths` / `content_blacklist_paths` | yes |
| Blocked pages | `content_blocked_pages` | check `/api/account/setting` |
| Allowed URL query params | `content_allowed_params` | check |
| Max topics in matrix | `content_max_topics` (default 500) | check |
| Custom meta-tag topics | `content_customprops` | check |
| Meta-tag delimiter | `content_custom_delimiter` (default `,`) | check |
| Supported languages | `supported_languages` | **no (staff only)**. If empty, only English is processed. |
| Enrichment sources | `enrich_content_sources` | staff. Setting it explicitly silently drops `google_category` and `llm`. |
| Content enrichment on/off | `enrich_content` | staff |
| Monthly classification cap | `enrich_content_maxurls` (default 20,000) | staff |

Each context layer also has its own `blacklisted_topics` / `whitelisted_topics` on the config. Read both the account setting and the layer config before proposing changes, and change whichever one the customer already uses.

## Timing
- **Topic summaries** are cached ~24h.
- **New pages** are classified in runs (~120 URLs per run, capped monthly).
- **Custom topic rules** apply when a page is classified. Pages already in the content table don't pick them up until they're re-classified (`POST /api/content/doc/classify?url=`).
- **Affinity publish** starts background jobs. Profile scores update as people return, and the docs say up to two weeks for inactive users.
- **Block/allow changes** affect the topic matrix on its next rebuild, and profiles on their next update.

## Not verified (test on a sandbox before relying on it)
- Whether `type: url` custom topic rules pass create-time validation. The create handler runs FilterQL validation on `filter_ql` whatever the type.
- Whether Affinity publish backfills `lytics_rollup` for existing profiles immediately, or only on their next update.
- The real context-layer count limit: the docs say 10, the code falls back to 5, and the setting's default is 2.
- Filtering recommendations by Affinity (`rollups`) is marked TODO in the recommend handler. Use topics or collections instead.
