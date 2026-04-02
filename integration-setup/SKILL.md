---
name: integration-setup
description: Guided setup for data integrations -- connection, auth, and job creation. Use when the user wants to set up, configure, or connect a new data integration end-to-end.
metadata:
  arguments: description of the desired integration
---

# Integration Setup

## Purpose
Guide users through setting up a complete data integration -- from creating auth credentials to configuring connections and creating jobs. Handles both imports (data flowing into Lytics) and exports (data flowing out to external platforms).

## Environment
- `LYTICS_API_TOKEN` -- API authentication token
- `LYTICS_API_URL` -- Base URL (default: `https://api.lytics.io`)

## Inputs
- Description of the desired integration (platform, direction, data type)
- Optional: credentials, segment to export, schedule preferences

## Setup Flow

### Step 0: Consider Using the Integration Advisor
If the user's request involves choosing a workflow, mapping fields, or setting up a new integration from scratch, suggest starting with the `integration-advisor skill`:
> "For new integrations, I can help you choose the right workflow, map fields, and configure everything optimally. Would you like strategic guidance first?"

If the user has a specific, well-defined setup request (e.g., "create a job with workflow X and auth Y"), proceed directly.

### Step 1: Identify Integration Type
Parse the user's description to determine:
- **Platform**: Facebook, Google, Salesforce, Klaviyo, etc.
- **Direction**: Import (into Lytics) or Export (from Lytics)
- **Data type**: Audiences, events, profiles, conversions

### Step 2: Check Available Providers
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/provider" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Find the matching provider for the target platform.

### Step 3: Check Existing Auth
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/auth" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Check if valid auth already exists for the target platform.

### Step 4: Create Auth (if needed)
Use `connection-manager skill` to create auth credentials. Guide the user on what credentials are needed for their platform.

### Step 5: Create or Select Connection
```bash
# Check existing connections
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/connection" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Use existing connection if available, or create new one.

### Step 6: Configure Job
Use `job-manager skill` to create the job with:
- Workflow matching the integration type
- Config specific to the platform
- Auth IDs linking to the credentials
- Segment ID (for exports)

### Step 7: Confirmation Gate
Present the complete integration setup:
- Auth provider details (type, not credentials)
- Connection configuration
- Job settings (workflow, schedule, segment)
- Raw API payloads for each resource to create

### Step 8: Execute on Approval
Create resources in order:
1. Auth (if new)
2. Connection (if new)
3. Job

Report success with links to each created resource.

## Common Integration Patterns

### Audience Export
1. User selects/creates a segment
2. Configure export job with segment_id
3. Set schedule (continuous, daily, etc.)

### Data Import
1. Configure connection to data source
2. Scan connection to discover available data
3. Create import job with field mappings

### Conversion API (CAPI)
1. Configure auth for the ad platform
2. Create conversion export job
3. Map Lytics events to platform conversion events

## Error Handling
- **Missing credentials**: Guide user on where to find them in the target platform
- **Invalid auth**: Suggest re-creating credentials
- **Workflow not found**: List available workflows for the platform
- **Segment not found**: Help create the segment first using audience-builder

## Dependencies
- Composes: `connection-manager skill`, `job-manager skill`, `../references/confirmation-gate.md`
- Related: `audience-builder skill` (for creating segments to export)
