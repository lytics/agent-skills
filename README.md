# Lytics CDP Agent Skills

Agent skills for interacting with the [Lytics](https://www.lytics.com) Customer Data Platform. Compatible with [skills.sh](https://skills.sh).

## Installation

```bash
npx skills add lytics/agent-skills
```

## Environment Setup

| Variable | Required | Description |
|----------|----------|-------------|
| `LYTICS_API_TOKEN` | Yes | Lytics API token for authentication |
| `LYTICS_API_URL` | No | Custom API base URL (defaults to Lytics production API) |

## Available Skills

### Audiences & Segments

| Skill | Description |
|-------|-------------|
| `audience-advisor` | Strategic audience guidance -- helps choose the right audience for a business goal |
| `audience-builder` | Create or update audience segments from natural language descriptions |
| `audience-snapshot` | Analyze audience composition -- demographics, field values, coverage, distributions |
| `segment-manager` | Segment CRUD, validation, and sizing operations |
| `filterql-builder` | Translate structured conditions into valid FilterQL expressions |

### Profiles & Identity

| Skill | Description |
|-------|-------------|
| `entity-lookup` | Look up user profiles by identity field and value |
| `profile-explorer` | Interactive profile exploration -- lookup, segments, and event history |
| `profile-investigator` | Diagnose segment membership and trace data lineage |

### Data Integration

| Skill | Description |
|-------|-------------|
| `integration-advisor` | Strategic guidance for setting up the right data integration |
| `integration-setup` | Guided end-to-end setup for data integrations |
| `connection-manager` | Browse and manage connections, auth providers, and credentials |
| `job-manager` | Job lifecycle management -- create, pause, resume, bounce, kill |
| `export-debugger` | Trace why a user was or wasn't exported to a platform |

### Schema & Data

| Skill | Description |
|-------|-------------|
| `schema-discovery` | Discover profile schema fields, types, and sample values |
| `schema-manager` | Browse and modify schema fields, mappings, and identity config |
| `schema-optimizer` | Analyze schema usage and suggest improvements |
| `stream-inspector` | Inspect data streams, view stats, and browse recent events |

### Campaigns & Flows

| Skill | Description |
|-------|-------------|
| `campaign-flow-builder` | Guided multi-step campaign/journey creation |
| `flow-manager` | Flow/journey CRUD and step management |

### Monitoring & General

| Skill | Description |
|-------|-------------|
| `data-health-monitor` | Single-command health check across streams, jobs, schema, and quotas |
| `lytics-agent` | Top-level agent that routes requests to the appropriate skill |
