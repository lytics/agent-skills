# Discover

Use to find the schema fields that match a natural-language description ("country", "purchase history", "email engagement"), with types and sample values. Read-only.

Inputs: the concepts to find, and the table (default `user`).

## Endpoints

```bash
curl -sS -w '\n%{http_code}\n' "${LYTICS_API_URL:-https://api.lytics.io}/v2/schema/${TABLE:-user}/fieldnames" \
  -H "Authorization: ${LYTICS_API_TOKEN}"
```

| Call | Returns |
|---|---|
| `GET /v2/schema/{table}/fieldnames` | Just field names: quick inventory |
| `GET /v2/schema/{table}/field` | All fields with types, descriptions, merge operations |
| `GET /api/schema/{table}/fieldinfo` | Field info including value distributions and sample data |
| `GET /api/schema/{table}/fieldsuggest/{field}?q={query}` | Suggested values for one field; `q` is **required** and is a case-insensitive substring match against values |
| `GET /v2/schema/{table}/idconfig` | Identity configuration |
| `GET /v2/stream/names` | Available streams |

`fieldinfo` and `fieldsuggest` are `/api` endpoints: read their errors from `.message`, not `.errors` (`references/api.md`). URL-encode `q`: `curl -G --data-urlencode "q=${QUERY}" ...`.

## Steps

1. **Inventory**: fetch `fieldnames`.
2. **Score candidates** for each concept:
   1. Name match (highest priority): exact or substring match on the field name.
   2. Type compatibility: the type supports the intended operation (`references/field-types.md`).
   3. Description match: the field's `shortdesc` / `longdesc`.
3. **Confirm with values**: for the top 2-3 candidates per concept, call `fieldsuggest` to check the field holds the expected kind of data and that sample values match what the user described (e.g. "US" in a country field).
4. **Return a mapping**: concept -> field name, type, confidence, sample values, plus any ambiguities that need the user's choice.

## Name heuristics

| User says | Try |
|---|---|
| country | `country`, `geo_country`, `country_code` |
| email | `email`, `_e` |
| purchased / bought | `products_purchased`, `purchase_categories`, `orders` |
| visited / browsed | `urls_visited`, `pages_viewed`, `visit_count` |
| signed up / registered | `created`, `signup_date`, `joined` |
| clicked | `click_count`, `clicks` |
| score | `scores.*`, `engagement_score` |

## When it doesn't resolve

- No field matches a concept: say so plainly and suggest rephrasing or browsing the field list.
- Several equally strong candidates: present them and let the user choose.
- Table doesn't exist: report it and suggest `user`.
