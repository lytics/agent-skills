---
name: content-affinity-advisor
description: Assess, advise on, and curate Lytics content affinity -- context layers, topics, Affinities (supertopics), and topic-based micro-audiences. Use when the user wants to audit their topic map, clean up or enrich topics, design Affinities, build audiences from content interest, or execute a content/topic curation plan.
metadata:
  arguments: mode and target -- assess [context-layer id|all], advise [assessment file], execute <plan file> [action ids], or a natural-language content/topic question
---

# Content Affinity Advisor

## Purpose
Help a Lytics customer get a topic map that actually means something, then turn it into Affinities and audiences they can activate.

Topics are the hardest part of content affinity to get right:
- The topic map Lytics produces is only a starting point. It depends on how pages were scraped, what the language-processing classifier (Google NLP by default) made of them, and whether the customer controls their own site markup.
- Most customers never built an intentional taxonomy for their website, or for their product catalogue when a custom context layer sits on product data.
- A topic set much larger than ~500 dilutes every score. Profiles whose top topics are too generic ("Home", "Customer") or too specific (one-off topics) are useless for activation.

This skill does three things, each in its own reference file:

| Mode | What it does | Writes? | File |
|---|---|---|---|
| `assess` | Audits one or more context layers: content, topics, Affinities, profile scores, downstream use. Produces a scorecard with evidence. | No | `assessment.md` |
| `advise` | Turns the assessment into an advisement plan: a target taxonomy, proposed Affinities, micro-audiences, and an ordered list of actions a person or an agent can carry out. | No (writes a local plan file only) | `advisement.md` |
| `execute` | Carries out actions from an approved plan using the playbooks: block or allow topics, custom topic rules, page-level topic fixes, Affinities, re-evaluation, audience handoff. | Yes, behind the confirmation gate | `execution.md` |

Shared guidance:
- `topic-curation-principles.md`: what a good topic map looks like, and the judgement rules every mode uses.
- `api-notes.md`: verified endpoints, permission scopes, setting keys, and where the public docs are wrong.

Load only the files the current mode needs.

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

Token scope matters here more than for most skills (details in `api-notes.md`):
- A data-read token can scan the content table, read Affinities and content configs, and size audiences.
- Some minted view tokens get 403 on the topic list, taxonomy, context-layer and custom-topic endpoints, even when they can scan content.
- Affinity create/update/delete, AI supertopic suggestions, and account settings need write scopes.

If an endpoint returns 403, record it as a gap in the assessment and continue with the alternatives listed in `api-notes.md`. Do not stop the run, and do not retry with other auth styles.

## Invocation

```
assess [all | <context-layer id>] [--sample=<n pages to judge>]   # read-only audit
advise [<assessment file>] [--taxonomy=<file or URL>]           # build the advisement plan
execute <plan file> [<action id> ...] [--dry-run]               # carry out approved actions
```

Natural-language requests route to the right mode:
- "Why are my topics so random?" goes to `assess`.
- "Clean up our topics and set up interest groups" goes to `assess`, then `advise`.
- "Do actions 3 to 7 from the plan" goes to `execute`.

## Flow

### 1. Scope the run
- Confirm which account, and which context layer(s). List them first:
  - `GET /v2/content/contextlayer`
  - `GET /api/content/config`
- `default` is the standard topic layer. Custom layers can sit on other tables or streams, such as a product catalogue.
- Ask whether the customer has an existing taxonomy, sitemap, information architecture, or product category tree. If they do, it becomes the target in `advise`. If not, the skill proposes one.
- Ask whether the customer controls their site markup (meta tags, CMS fields). This decides which levers are realistic in `advise`. Many customers do not, and the plan must still work without it.

### 2. Assess
Follow `assessment.md`. Save the outputs locally:
- `content-assessment-<account>-<YYYY-MM-DD>.md`, the scorecard
- `content-assessment-<account>-<YYYY-MM-DD>.json`, the evidence

Show the scorecard summary to the user.

### 3. Advise
Follow `advisement.md`. Produce:
- `content-advisement-plan-<account>-<YYYY-MM-DD>.md`, for people
- `content-advisement-plan-<account>-<YYYY-MM-DD>.yaml`, the machine-readable action list

The plan is the contract between a person and an agent. A person can work through it by hand, or hand it to `execute`.

### 4. Execute (optional)
Follow `execution.md`. Rules:
- Only actions in the plan with `status: approved` run.
- Every write goes through `../references/confirmation-gate.md`.
- Every action takes a before snapshot and records a verification step.

If the user's token is read-only, or they prefer it, `--dry-run` generates a reviewable shell script instead of calling the API.

### 5. Hand off
- Audience creation goes to `audience-builder skill`.
- Activation goes to `integration-advisor skill` / `integration-setup skill`.
- Journey routing by affinity goes to `campaign-flow-builder skill` (its `affinity` step).
- Profile checks go to `profile-investigator skill`.

## Things to tell the user early
- **Scores are relative.** A topic score is relative to the person's own strongest topic: their top topic is always about 1.0, even after one page view. It is not a measure of how much they engaged. Topic micro-audiences need an engagement or recency guard as well as a score threshold.
- **No decay.** Old interests count as much as new ones.
- **Changes take time.** Re-scoring after a change is not instant. Profiles update as they get new activity, and the docs say up to two weeks for inactive users. Plan verification windows accordingly.
- **Language.** Only English content is classified unless `supported_languages` is set. That setting is staff-only, so changing it is a request to Lytics support.

## Error Handling
- **"Account missing content data"**: content enrichment (`enrich_content`) is off. Stop and report. The assessment can only describe what's missing.
- **403 on an endpoint**: token scope. Log it in the assessment's "gaps" section, use the fallback in `api-notes.md`, and continue.
- **404 on a v2 path**: try the v1 path listed in `api-notes.md` before concluding the resource is missing.
- **Large accounts**: the content scan pages 200 at a time. Over 50,000 documents, sample by URL path section rather than pulling everything, and say so in the scorecard.

## Dependencies
- `../references/auth.md`, `../references/api-client.md`, `../references/api-response-format.md`, `../references/confirmation-gate.md`, `../references/filterql-grammar.md`
- `segment-manager skill` (sizing, content-table scans), `audience-builder skill`, `audience-snapshot skill`, `profile-investigator skill`, `integration-advisor skill`, `campaign-flow-builder skill`
