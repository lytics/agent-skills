---
name: audience-advisor
description: Strategic audience guidance -- helps users build the right audience for their business goal or improve an existing segment. Use when the user needs help choosing the right audience strategy, wants advice on segment design, or needs to improve an existing segment.
metadata:
  arguments: business goal or existing segment name to improve
---

# Audience Advisor

## Purpose
Coaches users toward building the *right* audience for their business outcome, not just any audience. Uses Lytics analytical APIs -- ML feature importance, content affinities, fieldinfo distributions, segment summaries -- to make evidence-based recommendations. Gracefully degrades when advanced features aren't configured.

Supports two modes:
- **Create from goal**: "Help me build an audience to drive more purchases"
- **Improve existing**: "How can I improve my 'High Value Customers' segment?"

## Environment
Requires authenticated API access. See `../references/auth.md` for credential resolution.

## Flow

### Step 1: Understand the Intent

Determine which mode the user needs:

**Path A -- New audience from a business goal:**
Ask what they're trying to achieve, not what audience they want:
- "Drive more purchases" -> conversion-focused
- "Re-engage lapsed users" -> retention-focused
- "Grow email subscribers" -> acquisition-focused
- "Promote new product line" -> awareness-focused

Classify the goal type -- this determines which fields and strategies to prioritize later.

**Path B -- Improve an existing segment:**
Accept a segment name or ID. Fetch it and its current FilterQL:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```
Find the matching segment, note its current size, and parse its FilterQL to understand existing filters.

Both paths converge at Step 2.

### Step 2: Inventory Existing Segments

Fetch all segments to understand what's already built:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/segment?table=user&sizes=true" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

- Identify segments related to the goal by name, tags, or kind
- Look for "goal" or "conversion" kind segments -- these represent business outcomes and are valuable reference points
- Note total population size for percentage calculations later
- Flag any existing segment that already targets this goal to avoid duplication

### Step 3: Gather Analytical Signals

Try each data source. Skip any that return empty or error -- proceed with whatever is available.

**3a. ML Feature Importance (best signal, may not exist):**

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/ml" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

If models exist, find one whose **target segment** matches the user's desired outcome. Each model predicts user similarity to its target segment:

- List all models and examine their target segment names/descriptions
- Match target segment against the user's stated goal (e.g., goal = "drive purchases" -> look for models targeting a "purchasers" or "converters" segment)
- If a relevant model is found, fetch its summary:
  ```bash
  curl -s "${LYTICS_API_URL:-https://api.lytics.io}/v2/ml/${MODEL_ID}/summary" \
    -H "Authorization: ${LYTICS_API_TOKEN}"
  ```
  The response contains model quality metrics and a `features` array ranking which fields most differentiate the target audience:
  ```json
  {
    "data": {
      "id": "model_id",
      "name": "Model Name",
      "state": "completed",
      "summary": {
        "auc": 0.85,
        "accuracy": 0.82,
        "reach": 0.75,
        "model_health": "good",
        "mse": 0.12,
        "rsq": 0.71
      },
      "features": [
        {
          "kind": "score",
          "type": "numeric",
          "name": "visit_count",
          "importance": 1.79,
          "field_prevalence": {"source": 0.30, "target": 0.99},
          "correlation": 0.23,
          "impact": {"lift": 0.35, "threshold": 2}
        }
      ]
    }
  }
  ```
  **Key feature fields for recommendations:**
  - `name` -- the schema field name to filter on
  - `importance` -- higher = more predictive of target segment membership
  - `field_prevalence.source` vs `.target` -- how common the field is in general population vs target (large gap = strong differentiator)
  - `correlation` -- direction and strength of relationship
  - `impact.lift` -- how much this field increases likelihood of being in the target
  - `impact.threshold` -- suggested cutoff value for filtering

- **If no model's target segment relates to the goal**: skip ML. Tell the user: "No ML model targets this outcome. You could create a lookalike model using your conversion segment as the target to get predictive feature rankings."
- **If multiple models could apply**: prefer the one whose target segment most closely matches the goal.
- **If no models exist at all**: skip silently, proceed to next signal.

**3b. Content Affinities (may not be configured):**

```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/content/affinity" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

If affinities exist and a reference segment is available:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/content/recommend/segment/${SEGMENT_ID}" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

This reveals topic interests that differentiate the audience. If not configured: skip silently.

**3c. Fieldinfo Analysis (always available -- the baseline):**

For a reference segment (goal/conversion segment, or the segment being improved).
**Important**: Use the segment's `id` hash, not the slug name -- slugs return HTTP 500.
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${SEGMENT_ID}/fieldinfo?limit=50" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

For segment summary with aspect overlap:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/${SEGMENT_ID}/summary" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

If no reference segment exists, use schema-level field distributions:
```bash
curl -s "${LYTICS_API_URL:-https://api.lytics.io}/api/schema/user/fieldinfo" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

This always works -- field coverage, value distributions, and cardinality are always available.

### Step 4: Synthesize and Recommend

Present findings organized by signal strength:

**With ML feature importance:**
> "Your ML model targeting 'Purchasers' ranks these as the top predictors:
> 1. `visit_count` -- users with 5+ visits are 3.2x more likely to convert
> 2. `email_engagement` -- engaged email readers convert at 2.8x the baseline
> 3. `products_viewed` -- browsing 3+ product categories indicates high intent
>
> I'd recommend building filters around these fields."

**With content affinities:**
> "Your converters over-index on 'Technology' content (3.2x vs baseline) and 'Product Reviews' (2.5x). Consider using content affinity as a targeting signal."

**With fieldinfo only (always available):**
> "Looking at your 'Recent Purchasers' segment:
> - 78% have visit_count >= 5 (vs 30% of all users)
> - 92% have email populated (good for email campaigns)
> - country: 65% US, 15% CA, 10% UK
>
> Filtering on visit_count >= 5 would capture most converters while excluding low-intent users."

**For improving existing segments:**
> "Your 'High Value' segment currently has 50,000 users (35% of total) -- quite broad for targeted campaigns. Here's what I found:
> - The filter `EXISTS email` matches 92% of all users -- it's not adding much selectivity
> - Only 20% of this segment has `purchase_history` populated -- that field may not be useful here
> - Adding `visit_count >= 5` would narrow to 15,000 (10%) while keeping 78% of your actual converters
>
> Suggested updated FilterQL:
> `FILTER AND (visit_count >= 5, email_engagement > 0.3) FROM user ALIAS high_value_v2`"

### Step 5: Iterate on Sizing

Test filter variations without creating segments. Show the user how each change affects audience size:

```bash
# Get total population size for percentage context
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/size" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d 'FILTER * FROM user'
```

```bash
# Test each filter variation
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/size" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d 'FILTER AND (visit_count >= 5) FROM user'
```

Present as incremental refinement:
```
Starting point: 145,000 total users (100%)

1. visit_count >= 5          -> 43,500 (30%)
2. + email_engagement > 0.3  -> 18,200 (13%)
3. + last_visit > "now-30d"  -> 12,400 (9%)   <-- recommended

This 9% audience captures your highest-intent users with recent activity.
```

Validate each FilterQL before sizing:
```bash
curl -s -X POST "${LYTICS_API_URL:-https://api.lytics.io}/api/segment/validate" \
  -H "Authorization: ${LYTICS_API_TOKEN}" \
  -H "Content-Type: text/plain" \
  -d 'FILTER AND (visit_count >= 5, email_engagement > 0.3, last_visit > "now-30d") FROM user'
```

### Step 6: Confirm and Create

Once the user is satisfied with the proposed audience, hand off to the `audience-builder skill` to create the segment with the full confirmation gate pattern.

For improving existing segments, use `PUT /v2/segment/:id` instead.

### Step 7: Post-Creation Snapshot

After creation, offer to run an `audience-snapshot skill` to show the final audience composition and confirm it looks right.

## Audience Sizing Guidance

| % of Total | Assessment | Best For |
|------------|-----------|----------|
| < 1% | Very narrow -- may limit reach and statistical significance | Hyper-personalized, VIP programs |
| 1-10% | Well-targeted | Conversion campaigns, retargeting |
| 10-30% | Broad targeting | Awareness campaigns, email blasts |
| > 30% | Very broad -- consider if tighter targeting would improve ROI | Broad announcements only |

## Field Selection Guidance by Goal Type

| Goal | Preferred Field Types | Why |
|------|----------------------|-----|
| Conversion/Purchase | Behavioral: visit_count, pages_viewed, cart activity | Actions predict intent better than demographics |
| Re-engagement/Retention | Temporal: last_visit, last_purchase, recency scores | Recency identifies lapsed users |
| Awareness/Reach | Demographic: country, industry, interest categories | Broad attributes reach the right population |
| Email/Channel Growth | Channel: email_opt_in, channel_preferences, engagement scores | Channel-specific signals matter most |

## Refinement Patterns

- **Start broad, narrow incrementally** -- show size impact at each step so the user understands the tradeoff
- **Use AND for narrowing, OR for expanding** -- guide users on composition
- **Check field coverage before recommending** -- a field with 20% coverage limits the audience to at most 20%
- **Prefer INTERSECTS for set fields** (e.g., products_purchased), comparison operators for numeric
- **Use date math for temporal targeting** -- `"now-30d"` for recent, `"now-90d"` for medium-term, `"now-1y"` for long-term

## Error Handling
- **No ML models**: Skip gracefully, rely on fieldinfo analysis. Suggest creating a lookalike model.
- **No affinities**: Skip silently, proceed with fieldinfo.
- **No conversion/goal segments**: Ask the user to describe their ideal customer characteristics manually. Use schema discovery to find matching fields.
- **Empty segment after filtering**: Suggest broadening -- remove the most restrictive filter or adjust thresholds.
- **User unsure about goal**: Offer common goal categories and let them pick.

## Dependencies
- Composes: `audience-builder skill`, `audience-snapshot skill`, `segment-manager skill`, `schema-discovery skill`
- References: `../references/auth.md`, `../references/api-client.md`, `../references/field-types.md`, `../references/filterql-grammar.md`
