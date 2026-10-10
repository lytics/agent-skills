# Advise

Coach the user toward the *right* audience for a business outcome, or improve an existing segment, using evidence from ML feature importance, content affinities, and fieldinfo. Degrades gracefully when advanced features aren't configured.

Two paths:
- **Create from goal**: "Help me build an audience to drive more purchases"
- **Improve existing**: "How can I improve my 'High Value Customers' segment?"

## Step 1: Understand the intent

**Path A, goal.** Ask what they are trying to achieve, not what audience they want, and classify it (this picks the fields later):
- "Drive more purchases" -> conversion
- "Re-engage lapsed users" -> retention
- "Grow email subscribers" -> acquisition
- "Promote new product line" -> awareness

If the user is unsure, offer these categories and let them pick.

**Path B, existing segment.** Accept a name or id, find it in the list below, note its size, and parse its FilterQL.

## Step 2: Inventory existing segments

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
- Find segments related to the goal by name, tags, or kind.
- `goal` and `conversion` kind segments represent business outcomes and are the best reference points.
- Note the total population for percentages.
- Flag any segment that already targets this goal, to avoid duplication.

## Step 3: Gather signals

Try each source; skip any that is empty or errors and continue with what's available.

### 3a. ML feature importance (best signal, may not exist)

`GET /v2/ml` lists models. Each predicts similarity to its **target segment**: match target segment names/descriptions against the goal (goal "drive purchases" -> a model targeting "purchasers" or "converters"); with several candidates, prefer the closest match. Then `GET /v2/ml/${MODEL_ID}/summary`:
```json
{"data": {"id": "model_id", "name": "Model Name", "state": "completed",
  "summary": {"auc": 0.85, "accuracy": 0.82, "reach": 0.75, "model_health": "good", "mse": 0.12, "rsq": 0.71},
  "features": [{"kind": "score", "type": "numeric", "name": "visit_count", "importance": 1.79,
    "field_prevalence": {"source": 0.30, "target": 0.99}, "correlation": 0.23,
    "impact": {"lift": 0.35, "threshold": 2}}]}}
```
- `name`: the schema field to filter on.
- `importance`: higher = more predictive of target membership.
- `field_prevalence.source` vs `.target`: prevalence in the general population vs the target; a large gap is a strong differentiator.
- `correlation`: direction and strength.
- `impact.lift`: how much the field raises the likelihood of being in the target; `impact.threshold`: suggested cutoff.

No model targets the goal: skip ML and say "No ML model targets this outcome. You could create a lookalike model using your conversion segment as the target to get predictive feature rankings." No models at all: skip silently.

### 3b. Content affinities (may not be configured)

`GET /api/content/affinity`; if affinities exist and there is a reference segment, `GET /api/content/recommend/segment/${SEGMENT_ID}` shows topic interests that differentiate the audience. Not configured: skip silently.

### 3c. Fieldinfo (always available, the baseline)

For the reference segment (a goal/conversion segment, or the one being improved), using the **`id` hash, not the slug** (slugs return 500):
- `GET /api/segment/${SEGMENT_ID}/fieldinfo?limit=50`
- `GET /api/segment/${SEGMENT_ID}/summary` (segment summary with aspect overlap)

No reference segment: `GET /api/schema/user/fieldinfo` for schema-level coverage, value distributions, and cardinality.

No goal/conversion segment and no usable signal: ask the user to describe their ideal customer and map that to fields as in `build.md`.

## Step 4: Recommend

Lead with the strongest signal available. Example shapes:

> **ML**: "Your ML model targeting 'Purchasers' ranks these as the top predictors: 1. `visit_count` -- users with 5+ visits are 3.2x more likely to convert; 2. `email_engagement` ..."

> **Affinities**: "Your converters over-index on 'Technology' content (3.2x vs baseline) and 'Product Reviews' (2.5x)."

> **Fieldinfo only**: "In 'Recent Purchasers', 78% have visit_count >= 5 (vs 30% of all users); 92% have email. Filtering on visit_count >= 5 would capture most converters while excluding low-intent users."

> **Improving a segment**: "'High Value' has 50,000 users (35% of total), broad for targeted campaigns. `EXISTS email` matches 92% of all users, so it adds little selectivity; only 20% have `purchase_history`; adding `visit_count >= 5` narrows to 15,000 (10%) while keeping 78% of converters. Suggested: `FILTER AND (visit_count >= 5, email_engagement > 0.3) FROM user ALIAS high_value_v2`"

Field choice by goal:

| Goal | Preferred fields | Why |
|---|---|---|
| Conversion/Purchase | Behavioral: visit_count, pages_viewed, cart activity | Actions predict intent better than demographics |
| Re-engagement/Retention | Temporal: last_visit, last_purchase, recency scores | Recency identifies lapsed users |
| Awareness/Reach | Demographic: country, industry, interest categories | Broad attributes reach the right population |
| Email/Channel growth | Channel: email_opt_in, channel_preferences, engagement scores | Channel-specific signals matter most |

Refinement patterns:
- Start broad and narrow incrementally, showing the size at each step.
- AND narrows, OR expands.
- Check coverage before recommending: a field with 20% coverage caps the audience at 20%.
- INTERSECTS for set fields (e.g. `products_purchased`), comparison operators for numerics.
- Date math: `"now-30d"` recent, `"now-90d"` medium-term, `"now-1y"` long-term.

## Step 5: Iterate on size

Size variations without creating anything. Validate each first (`POST /api/segment/validate`, raw FilterQL, `text/plain`), then size:
```bash
curl -sS -w '\n%{http_code}\n' -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/size" \
  -H "Authorization: ${LYTICS_API_TOKEN}" -H "Content-Type: text/plain" \
  --data-binary 'FILTER * FROM user'
```
`FILTER * FROM user` gives the total population; then e.g. `FILTER AND (visit_count >= 5) FROM user`. Present it as a funnel:
```
Starting point: 145,000 total users (100%)
1. visit_count >= 5          -> 43,500 (30%)
2. + email_engagement > 0.3  -> 18,200 (13%)
3. + last_visit > "now-30d"  -> 12,400 (9%)   <-- recommended
```
Empty after filtering: drop the most restrictive filter or loosen a threshold.

| % of total | Assessment | Best for |
|---|---|---|
| < 1% | Very narrow; may limit reach and statistical significance | Hyper-personalized, VIP |
| 1-10% | Well-targeted | Conversion, retargeting |
| 10-30% | Broad | Awareness, email blasts |
| > 30% | Very broad; tighter targeting may improve ROI | Broad announcements only |

## Step 6: Create or update

- New audience: continue in `build.md` from the confirmation gate (Step 6).
- Existing segment: `PUT /v2/segment/:id` following the update rules in `manage.md` (keep `FROM` and `ALIAS`; confirm the returned id matches).

Afterwards, offer a snapshot (`snapshot.md`) to confirm the composition looks right.
