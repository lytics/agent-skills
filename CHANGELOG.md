# Changelog

All notable changes to this skills repo are documented here.
The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.2] - 2026-10-09

### Fixed

- **Shared references were never installed** ([#1](https://github.com/lytics/agent-skills/issues/1)).
  `npx skills add` copies only each skill's own folder, so every
  `../references/*.md` link (auth rules, confirmation gate, FilterQL grammar,
  field types) pointed at nothing once installed. Each skill now ships the
  references it uses in its own `references/` folder, generated from the
  top-level `references/` by `scripts/sync-references.sh`; CI fails a PR whose
  copies are stale.
- **README install instructions**: a non-interactive install for one agent,
  how to pick several skills or agents (repeat the flag; comma lists are
  rejected), and what the "always included" agents list means.

## [0.3.1] - 2026-10-09

### Fixed

Instructions that made a write do something other than what the user approved,
each checked against lio `develop` source and exercised against a running lio:

- **Multi-account calls hit the ambient account.** The `references/auth.md`
  env-prefix pattern expanded `${LYTICS_API_URL}` before the prefix applied, so
  `account-sync` could read from or write to the wrong account. Replaced with
  `src` / `dst` helpers and a same-account guard on resolved aids.
- **`account-sync`**: jobs are created with `?run_job=false` (they started
  immediately); `sync settings` no longer copies security/API settings,
  `cull_user_filter`, `workflow_exclude_segments`, `enable_schema_patches` or
  immutable settings; schema-mode probe reads the setting; patches use `tag`.
- **`schema-manager`**: field bodies use the real lowercase keys (the old keys
  reset `is_identifier` / `is_pii` on update); publish shows the whole shared
  draft first; mode probe reads the setting; mapping stream can't change.
- **`job-manager`**: create starts the job; update is a full replace; kill is a
  delete. Real status values in `job-manager`, `data-health-monitor`,
  `export-debugger`; no more "stale `updated` means stuck, bounce it".
- **Flows**: lower condition priority is checked first; A/B edge probability is
  ignored by the API, so A/B splits are no longer offered; flow DELETE removes
  every version permanently.
- **Segments**: a taken slug is silently renamed on create, so results report
  the returned slug/id; updates keep `FROM` / `ALIAS` and check the id.
- **Profiles**: `/api/entity` answers a missing profile with 200 and a
  placeholder, not 404; soft delete cannot be undone; value-only lookup is `_uid`.
- Dead cross-references in `references/`.

## [0.3.0] - 2026-10-09

### Added

- **`content-affinity-advisor` skill** -- assess, advise on, and maintain
  Lytics content affinity: context layers, topics, Supertopics (API:
  `Affinity`) and topic-based micro-audiences. Three modes:
  - `assess`: read-only scorecard and evidence on a view token, using
    GET-only query recipes, with a fallback for every content endpoint
    that returns 403. Optional live-site check (`site-assessment.md`).
  - `advise`: target taxonomy and a grouped, plain-language action plan
    (md, yaml, json). Makes no API writes.
  - `execute`: additive only. Never sends `DELETE`, changes only objects
    it created (ledger), and never shrinks live audiences. Domain and path
    blocks (which delete content records), custom topic rules, page edits
    and re-classification are UI or human-handoff steps.
  `api-notes.md` records where docs.lytics.com differs from `lio`. The
  skill was verified against source and five blind test runs on a live
  account.
- **Router entry** in `lytics-agent/SKILL.md` for content and topic intents.

## [0.2.0] - 2026-05-01

### Added

- **`webhook-template-builder` skill** -- new skill for research-driven authoring
  of Lytics webhook templates (the JS/Jsonnet transforms that reshape profiles
  into the body shape an external webhook destination expects). Headline mode
  is `build`: name a destination (e.g. Qualtrics) or paste a docs URL, and the
  skill fetches the destination's API docs, infers the required payload +
  headers + auth model, drafts a `function template(data)` JS template,
  iterates against `/v2/template/{id}/test` (real profile via `entity-lookup`,
  synthetic fixture via `schema-discovery`, or user-supplied JSON), saves, and
  emits a webhook-job config blueprint for `job-manager skill` to consume.
  Supports both `webhook_triggers` (audience triggers) and
  `webhook_enrichment` (user enrichment) workflows. SKILL.md captures runtime
  drift from public docs that bit during end-to-end verification: `template`
  (not `transformData`) entry-point name, PUT (not POST) for update,
  required `desired_format` query param for `/test` to succeed, and
  `try/catch` guards on `ly_*_config` globals.
- **Account-sync `template` type** -- `account-sync` now copies webhook
  templates between accounts. Natural key is `(name, type)`. Source body is
  whitespace-normalized before diff (trailing whitespace trimmed, line endings
  normalized) so re-runs are idempotent. Webhook-workflow jobs
  (`webhook_triggers`, `webhook_enrichment`) now have `config.template_id`
  automatically remapped via the in-run template map; jobs synced without
  their template halt with a blocker rather than writing a broken reference.
- **Router entry** in `lytics-agent/SKILL.md` for webhook-template intents.

### Changed

- **Auth centralized in `references/auth.md`** -- one contract for CLI, SaaS,
  multi-agent, and multi-account (`~/.lytics/accounts.toml`) credential
  resolution; the per-skill auth blocks now point at it.
- **MIT license** added; README links to the access-token docs.

## [0.1.0] - 2026-04-20

First tagged release. Adds cross-account metadata coordination.

### Added

- **`account-sync` skill** -- new skill for copying segments, schema fields and
  mappings, flows, jobs, connections, and auth providers between two Lytics
  accounts (e.g., sandbox -> prod). Handles dependency traversal, cross-account
  hex-ID remapping in FilterQL `INCLUDE`s, upsert-by-natural-key, schema-patches
  integration, and OAuth auth pauses. Grammar: `sync | compare | resume`. Safety
  layers include `--dry-run`, a confirmation gate, a bulk-operation gate,
  stop-on-first-error, read-after-write verification, and a per-run JSON
  manifest at `~/.lytics/sync/`.
- **Account-settings sync** under the same skill: `sync settings`, `sync setting
  <key>`, `sync idconfig [<table>]`, `sync rank [<table>]`. Covers the 99-key
  `account.setting` block (via `/api/account/setting`), per-table `idconfig`,
  and per-table field rank. `can_be_assigned: false` settings classify as
  `drift-readonly` and are never written. `idconfig` writes require an extra
  retype-to-confirm gate beyond the standard confirmation.
- **Profile config** `~/.lytics/accounts.toml` for managing multiple account
  credentials in parallel. Documented in `README.md`.
- **Router entries** in `lytics-agent/SKILL.md` for cross-account sync / promote
  / copy intents, including account-settings keywords.

### Fixed

- **`schema-manager/SKILL.md`** schema-patch examples: patch creation requires
  `tag` (kebab-case), not `name`; patch field endpoints (add/update field
  within a patch) use lowercase keys (`id`, `type`, `shortdesc`, `mergeop`,
  `is_identifier`, `is_pii`). The capitalized shape shown previously is
  rejected by the patch endpoint with `Attribute 'Field' is required for
  Field`. Verified against api.lytics.io.

## [0.0.1] - 2026-04-02

Initial release. Retroactively tagged; see commit `8b9d0ae`. Restructured
from `drewlanenga/agent-skills` into top-level skill directories compatible
with `npx skills add lytics/agent-skills`.

### Added

- **21 agent skills** grouped by domain:
  - *Audiences & Segments*: `audience-advisor`, `audience-builder`,
    `audience-snapshot`, `segment-manager`, `filterql-builder`.
  - *Profiles & Identity*: `entity-lookup`, `profile-explorer`,
    `profile-investigator`.
  - *Data Integration*: `integration-advisor`, `integration-setup`,
    `connection-manager`, `job-manager`, `export-debugger`.
  - *Schema & Data*: `schema-discovery`, `schema-manager`,
    `schema-optimizer`, `stream-inspector`.
  - *Campaigns & Flows*: `campaign-flow-builder`, `flow-manager`.
  - *Monitoring & General*: `data-health-monitor`, `lytics-agent` (the
    top-level router skill).
- **5 shared references** under `references/`: `api-client.md`,
  `api-response-format.md`, `confirmation-gate.md`, `field-types.md`,
  `filterql-grammar.md`.
- **skills.sh-compatible layout** (top-level skill directories); installable
  via `npx skills add lytics/agent-skills`.
- **Environment setup** documented in `README.md`: `LYTICS_API_TOKEN`
  (required) and `LYTICS_API_URL` (optional, defaults to
  `https://api.lytics.io`).
- Frontmatter on every skill with trigger descriptions and metadata so
  `lytics-agent` can route intents to the right specialized skill.
