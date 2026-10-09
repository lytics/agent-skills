---
name: lytics-content-affinity
description: "Lytics CDP: assess, advise on, and curate content affinity -- context layers, topics, Supertopics, and topic-based micro-audiences. Use when the user wants to audit their Lytics topic map, clean up or enrich topics, design Supertopics, build audiences from content interest, or execute a content/topic curation plan."
license: MIT
---

# Content Affinity Advisor

## Purpose
Help a Lytics customer get a topic map that actually means something, then turn it into Supertopics and audiences they can activate.

Topics are the hardest part of content affinity to get right:
- The topic map Lytics produces is a starting point, not an answer. It depends on how pages were scraped, what the language-processing classifier (Google NLP by default) made of them, and whether the customer controls their own site markup.
- Most customers never built an intentional taxonomy for their website, or for their product catalogue when a custom context layer sits on product data.
- A topic set much larger than ~500 dilutes every score. Profiles whose top topics are too generic ("Home", "Customer") or too specific (one-off topics) are useless for activation.

This skill does three things, each in its own reference file:

| Mode | What it does | Token needed | File |
|---|---|---|---|
| `assess` | Audits one or more existing context layers: content, topics, Supertopics, profile scores, downstream use. Optionally checks the live website. Produces a scorecard with evidence. | Read-only view token | `assessment.md`, `site-assessment.md` |
| `advise` | Turns the assessment into an advisement plan: a target taxonomy, proposed Supertopics, micro-audiences, and an ordered list of actions a person or an agent can carry out. | Read-only view token | `advisement.md` |
| `execute` | Carries out the approved `API` actions: topic and exact-page blocks, Supertopics it creates, and audience handoff. Writes step-by-step instructions for everything done in the UI or by a person (custom topic rules, page topic edits, re-classification, domain and path blocks). | Write token with **only** the scopes each action needs (see `execution.md`) | `execution.md` |

Shared guidance:
- `topic-curation-principles.md`: what a good topic map looks like, and the judgement rules every mode uses.
- `api-notes.md`: verified endpoints, permission scopes, read-only query recipes, setting keys, and where the public docs are wrong.

Load only the files the current mode needs.

## Scope: what this skill does and does not do
**In scope:** assessing, fixing and maintaining an **existing** content setup.
- topics and their quality
- topic block lists and exact-page blocks (add-only); domain and path blocks are human handoffs, because they delete content records
- custom topic rules, page-level topic edits and re-classification (advised and written as UI steps; not automated)
- Supertopics
- topic micro-audience design, handed off for creation
- tuning settings on an existing context layer

**Out of scope, hand off or recommend a separate setup effort:**
- creating a new context layer
- building a custom content stream
- mapping custom schema into the content table
- defining a product-catalogue taxonomy from scratch

`assess` may *recommend* this kind of setup when the evidence calls for it (for example, a retail site whose URLs can't carry a taxonomy). It is written as a `setup_recommendation` action for a person or a dedicated setup skill. `execute` never creates layers, streams or schema.

**Non-destructive, always.** This skill never makes a `DELETE` API call, under any mode, token or instruction. It only adds or creates; it never removes. Anything destructive is written up as a **`human_handoff`** action, with exact steps for a person to carry out themselves. That covers:
- deleting or retiring a Supertopic
- deleting or changing a custom topic rule
- zeroing or removing a topic on a page
- removing entries from a block or allow list
- removing topics from an existing Supertopic
- unpublishing anything
- deleting content records

**Only changes what it created.** The agent may modify only objects it created itself, tracked in a ledger. Existing audiences, Supertopics, rules, collections and layers are read-only to it, even for "additive" changes like adding a recency guard or a topic: those change who is in a live audience, so they're human handoffs. To understand a narrower version of an existing audience, the agent copies its FilterQL into a read-only size check. It never edits the audience.

**No personal details.** Plans, handoffs, scripts and HTTP requests name **roles** (customer Lytics admin, customer web team, Lytics account team), never a person's name or email, even when the agent knows who the user is.

**Never touched, under any mode:** profiles, schema fields and mappings, identity config, streams, jobs, connections or auth, and any account setting outside the content allowlist in `execution.md`. `execute` refuses any request outside the content, topic and Supertopic boundary, even if the token would allow it.

## Environment
Requires authenticated API access. See `references/auth.md` for credential resolution.

- **`assess` and `advise` run on a read-only view token.** Several content endpoints return 403 to granular view tokens. That is expected: `api-notes.md` gives a read-only fallback for each. Record any 403 in the assessment's `gaps` list and continue. Do not stop the run, and do not retry with other auth styles.
- **`execute` needs a write token, and it is additive only** (create, add or publish; never `DELETE`). Before any write, it prints the exact token scopes required for the approved actions, and the risk of each (see `execution.md`). It never asks for or uses a broader token than those actions need.
- **The skill never reads PII.** User-table scans use field-restricted queries, and audience questions are answered with counts and distributions, not profile records.

## Portability: any OS, any tool-calling agent
This skill must work on macOS, Windows and Linux, and in any agent that can call tools. So:

- **Calls are specified, not scripted.** Every API call in these files is a request spec: method, path, query parameters, headers, and an optional JSON body. Make it with whatever HTTP capability the runtime offers, in this order of preference:
  1. a built-in HTTP, fetch or MCP tool
  2. Python 3 (`urllib.request`, standard library only)
  3. PowerShell (`Invoke-RestMethod`)
  4. `curl`

  The `curl` snippets are illustrations only. Never require bash, `jq`, `awk` or `sed`.
- **Auth header:** `Authorization: <token>`, the raw token with no `Bearer`. Read the token and URL from the environment the runtime provides:
  - `LYTICS_API_TOKEN`, `LYTICS_API_URL` (see `references/auth.md`)
  - on Windows PowerShell, these are `$env:LYTICS_API_TOKEN` / `$env:LYTICS_API_URL`

  Never print the token.
- **URL-encode** FilterQL and every other query value, using the HTTP tool's own encoding or `urllib.parse.quote`.
- **Analysis** (counting, normalizing, de-duplicating, sizing tables) is done in the agent's own reasoning, or in Python 3 with the standard library only. No third-party packages.
- **Files:** write outputs to a folder the user chooses (default: `./content-affinity-<account>-<YYYY-MM-DD>/`). Use forward-slash-safe relative paths, and file names with no `:` `*` `?` `"` `<` `>` `|` (Windows-safe). Write text as UTF-8 with `\n` line endings.
- **Website checks** (`site-assessment.md`) use the runtime's web-fetch tool if it has one, otherwise the same HTTP client.
- **Generated scripts** are a single Python 3 standard-library file (see `execution.md`). It runs the same on every OS: `python3 <file>.py` (or `py <file>.py` on Windows).

## Invocation

```
assess [all | <context-layer id>] [--site=<homepage URL>] [--sample=<n pages to judge>]
advise [<assessment file>] [--taxonomy=<file or URL>]
execute <plan file> [<action id> ...] [--dry-run]
```

Natural-language requests route to the right mode:
- "Why are my topics so random?" goes to `assess`.
- "Clean up our topics and set up interest groups" goes to `assess`, then `advise`.
- "Do actions 3 to 7 from the plan" goes to `execute`.

## Flow

### 1. Scope the run
1. **Confirm the account and context layer(s).** Read `GET /api/content/config` (a view token can read it; the v2 context-layer endpoint usually 403s).
2. **Ask about the customer's taxonomy:** do they have one already (sitemap, information architecture, product category tree)?
3. **Ask whether the customer controls their site markup.**
4. **Ask what kind of site it is** (see `site-assessment.md`).

If you can't ask, because you're running as a sub-agent or unattended, do not stall. Record each unanswered question as an **open assumption**, with the default you used, in the assessment and the plan.

### 2. Assess
Follow `assessment.md`. If a site URL is known, also run the site checks in `site-assessment.md`. Save:
- `content-assessment-<account>-<YYYY-MM-DD>.md`, the scorecard
- `content-assessment-<account>-<YYYY-MM-DD>.json`, the evidence

### 3. Advise
Follow `advisement.md`. Produce:
- `content-advisement-plan-<account>-<YYYY-MM-DD>.md`, which **opens with a "Start here" list of the first five actions**
- the matching `.yaml` action list, plus an identical `.json` copy for scripts

### 4. Execute (optional)
Follow `execution.md`.
- Only `approved` actions run. Each one is checked against the scope boundary.
- The skill prints the required token scopes and risks before anything else, then runs every write through `references/confirmation-gate.md`.
- `--dry-run` writes a reviewable script instead of calling the API.

### 5. Hand off
- Audience creation goes to the `lytics-audiences` skill.
- Activation goes to the `lytics-integrations` skill / the `lytics-integrations` skill.
- Journey routing by affinity goes to the `lytics-flows` skill.
- Setup work (new layer, stream, schema mapping) is handed to the person, or to a dedicated setup skill.

## Things to tell the user early
- **Scores are relative.** A topic score is relative to the person's own strongest topic: their top topic is always about 1.0, even after one page view. Any relevance above 0 counts in full (0.05 counts the same as 0.95), and relevance 0 counts for nothing. So a page whose real subject sits at relevance 0 gives its visitors no interest signal.
- **No decay.** Old interests never fade, so topic micro-audiences need an engagement or recency guard as well as a score threshold.
- **Changes take time.** Scores update as profiles get new activity. The docs say up to two weeks for inactive users.
- **Language.** Only English content is classified unless `supported_languages` is set. That setting is staff-only, so changing it is a request to Lytics support.

## Error Handling
- **"Account missing content data"**: content enrichment is off. Stop and report. The assessment can only describe what's missing.
- **403**: token scope. Use the fallback in `api-notes.md`, log it as a gap, and continue.
- **404 on a v2 path**: try the v1 path in `api-notes.md` before concluding the resource is missing.
- **Large accounts:** scans return at most 100 records per page. Above ~50,000 documents, sample by URL section rather than pulling everything, and say so in the scorecard.
- **Shell differences:** don't depend on a particular shell. If you do run a shell, avoid shell-specific traps (for example, a variable named `path` overwrites `PATH` in zsh). Generated scripts are Python, not shell.

## Dependencies
- `references/auth.md`, `references/api.md`, `references/confirmation-gate.md`, `references/filterql-grammar.md`
- the `lytics-audiences` skill, the `lytics-audiences` skill, the `lytics-audiences` skill, the `lytics-profiles` skill, the `lytics-schema` skill, the `lytics-integrations` skill, the `lytics-flows` skill
