# Lytics CDP Agent Skills

Agent skills for interacting with the [Lytics](https://www.lytics.com) Customer Data Platform. Compatible with [skills.sh](https://skills.sh).

## Installation

Install every skill for one agent, non-interactively:

```bash
npx skills add lytics/agent-skills --skill '*' --agent claude-code -y
```

- Repeat `--agent` for more than one agent (`--agent claude-code --agent cursor`); a comma-separated list is rejected. Without `--agent`, the CLI asks which agents to install into, and the "Universal (.agents/skills) -- always included" group it shows is a list of *agents*, not extra skills.
- `--skill` takes skill names (`--skill lytics-audiences --skill lytics-schema`) or `'*'`.
- Plain `npx skills add lytics/agent-skills` walks through both choices interactively.

Each skill is self-contained: the shared files it relies on (auth, confirmation gate, FilterQL grammar, ...) ship inside its own `references/` folder.

### Upgrading from 0.3.x or earlier

0.4.0 merged 24 skills into 10 and renamed them all with a `lytics-` prefix. Installing the new ones does not remove the old ones, and two generations side by side will compete for the same requests, so remove the old names first:

```bash
npx skills remove audience-builder audience-advisor audience-snapshot segment-manager filterql-builder \
  entity-lookup profile-explorer profile-investigator \
  integration-advisor integration-setup connection-manager job-manager \
  schema-discovery schema-manager schema-optimizer data-health-monitor stream-inspector \
  flow-manager campaign-flow-builder export-debugger webhook-template-builder \
  account-sync content-affinity-advisor lytics-agent -y
npx skills add lytics/agent-skills --skill '*' --agent claude-code -y
```

Add `-g` to `remove` if you installed globally.

### Contributing

The top-level [`references/`](references/) folder is the only copy to edit. Skills link these files as `references/<file>.md`. After changing one, or linking a new one from a skill, run `scripts/sync-references.sh` to refresh each skill's copy. CI fails a PR whose copies are out of date.

## Environment Setup

| Variable | Required | Description |
|----------|----------|-------------|
| `LYTICS_API_TOKEN` | Yes | Lytics API token for authentication ([create one](https://docs.lytics.com/docs/access-tokens)) |
| `LYTICS_API_URL` | No | Custom API base URL (defaults to Lytics production API) |

See [`references/auth.md`](references/auth.md) for the full authentication contract, including multi-account, SaaS, and multi-agent deployment contexts.

## Available Skills

Each skill covers one area and has modes; its `SKILL.md` says which file to read for each.

| Skill | Covers | Modes | Replaces (before 0.4.0) |
|-------|--------|-------|-------------------------|
| `lytics-audiences` | Audience segments and FilterQL | build, advise, snapshot, manage | audience-builder, audience-advisor, audience-snapshot, segment-manager, filterql-builder |
| `lytics-profiles` | Individual profiles | lookup, explore, investigate | entity-lookup, profile-explorer, profile-investigator |
| `lytics-integrations` | Providers, auth, connections, jobs | advise, setup, connections, jobs | integration-advisor, integration-setup, connection-manager, job-manager |
| `lytics-schema` | Fields, mappings, identity config, patches | discover, manage, optimize | schema-discovery, schema-manager, schema-optimizer |
| `lytics-data-health` | Is data flowing; streams | health-check, streams | data-health-monitor, stream-inspector |
| `lytics-flows` | Flows / journeys | build, manage | campaign-flow-builder, flow-manager |
| `lytics-export-debugger` | Why one user was or wasn't exported | -- | export-debugger |
| `lytics-webhook-templates` | Webhook templates for custom destinations | -- | webhook-template-builder |
| `lytics-content-affinity` | Topics, Supertopics, content affinity | assess, advise, execute | content-affinity-advisor |
| `lytics-account-sync` | Copy metadata and settings between accounts (sandbox -> prod). Only runs when explicitly asked: it writes to the destination account | sync, compare, resume | account-sync |

There is no router skill any more (`lytics-agent` was removed): agents pick a skill from its description, so each description says when it applies.
