# Changelog

All notable changes to this skills repo are documented here.
The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
