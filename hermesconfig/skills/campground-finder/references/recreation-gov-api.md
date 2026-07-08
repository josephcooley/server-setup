# Recreation.gov API — Live-Tested Notes (2026-06-22, updated 2026-06-22)

## Endpoints That Work

### Search
```
GET https://www.recreation.gov/api/search?limit=10&q=Trillium
```
Required headers:
```
accept: application/json
X-Requested-With: XMLHttpRequest
Referer: https://www.recreation.gov/
```
**Critical:** The `X-Requested-With: XMLHttpRequest` header is required. Without it, the API returns the full SPA HTML page instead of JSON.

### Availability (per-campground, per-month)
```
GET https://www.recreation.gov/api/camps/availability/campground/{id}/month
  ?start_date=2026-07-01T00:00:00.000Z
```
Same headers required. Returns `campsites` dict keyed by site ID, each with an `availabilities` map of date → status.

**URL Encoding:** The `start_date` query parameter MUST be URL-encoded (especially the colons in the time portion). Use `urllib.parse.urlencode()` or equivalent. Passing raw `T00:00:00.000Z` in the URL string returns `{"error":"query not encoded"}`.

## Endpoints That Don't Work

| Endpoint | Result |
|----------|--------|
| `/api/campgrounds` | Returns HTML (SPA) |
| `/api/facilities` | Returns HTML (SPA) |
| `/api/camps/campgrounds` | 404 |
| `/api/campgrounds?lat=...&lon=...` | Returns HTML |

## Query Parameter Quirks

| Param | Behavior |
|-------|----------|
| `entity_type=campground` | **Ignored.** Response still contains tours, timed entries, rec areas. Must filter client-side. |
| `state=OR` | **Doesn't filter by abbreviation.** The `state_code` field uses full names (`"Oregon"`). Filter client-side. |
| `radius=50` | **Unreliable.** May be ignored entirely, returning results from anywhere in the US. |
| `latitude/longitude` | Accepted but may not filter results. |
| `q=` | Free-text search. Works but returns mixed entity types. |

## Response Structure (Search)

```json
{
  "query": "Trillium",
  "results": [
    {
      "entity_id": "232831",
      "entity_type": "campground",
      "name": "TRILLIUM",
      "city": "Government Camp",
      "state_code": "Oregon",
      "latitude": "45.2831",
      "longitude": "-121.7412",
      "campsites_count": "50",
      "reservable": true,
      "price_range": {"amount_min": 22, "amount_max": 44, "per_unit": "night"},
      "org_name": "USDA Forest Service",
      "parent_name": "Mt. Hood National Forest"
    }
  ],
  "total": 9,
  "size": 10,
  "start": 0
}
```

## Response Structure (Availability) — Updated 2026-06-22

The availability response now uses `campsite_id` as the key field (not `site`). Each campsite object includes richer data:

```json
{
  "facility_name": "TRILLIUM",
  "campsites": {
    "82215": {
      "campsite_id": "82215",
      "site": "048A",
      "loop": "AREA TRILLIUM",
      "campsite_reserve_type": "Site-Specific",
      "campsite_type": "STANDARD NONELECTRIC",
      "type_of_use": "Overnight",
      "min_num_people": 1,
      "max_num_people": 10,
      "capacity_rating": "Double",
      "availabilities": {
        "2026-06-27T00:00:00Z": "Reserved",
        "2026-06-28T00:00:00Z": "Available"
      },
      "quantities": {
        "2026-06-27T00:00:00Z": 0,
        "2026-06-28T00:00:00Z": 1
      }
    }
  },
  "count": 50
}
```

**Key fields:**
- `site`: Human-readable site number (e.g., "048A", "001")
- `campsite_type`: Type of site (e.g., "STANDARD NONELECTRIC", "TENT ONLY NONELECTRIC", "GROUP PICNIC AREA", "YURT")
- `capacity_rating`: "Single" or "Double"
- `campsite_reserve_type`: "Site-Specific" or other
- `quantities`: Remaining quantity per date (0 = none, 1+ = available)

## Status Values

| Value | Meaning |
|-------|---------|
| `Available` | Open for booking |
| `Reserved` | Already booked (observed 2026) |
| `Not Available` | Already booked (older docs) |
| `Not Reservable` | Cannot be reserved (off-season, closed, etc.) |
| `Not Available Yet` | Booking window hasn't opened yet |
| `Open` | Walk-up / first-come-first-served |

**Note:** The API now uses `"Reserved"` and `"Not Reservable"` in addition to the older `"Not Available"` status. Scripts should treat both `"Reserved"` and `"Not Available"` as unavailable.

## Performance

- Search API: 2-8 seconds per call
- Availability API: 3-8 seconds per call
- Returns 50-150KB JSON for search results
- In constrained environments (containers, proxies), curl may timeout on large responses. Use `--max-time 30`.

## Rate Limiting (updated 2026-06-22)

No official rate limits published. In practice:
- Sequential requests with 0.3s gaps work fine
- Burst of 50+ requests may trigger temporary blocks
- **HTTP 429 ("heavy traffic") is common** even with moderate volumes (~50 requests). The script implements exponential backoff retries (3s, 6s, 9s) with max 3 retries per request.
- A 0.5s delay between requests helps but doesn't prevent all 429s
- If blocked, wait 2-3 minutes and retry
- Some requests may still fail after all retries — this is expected, not a bug

## First-of-Month Requirement (discovered 2026-06-22)

The availability endpoint **requires the 1st of the month** as `start_date`. Passing any other date (e.g., `2026-06-27`) returns:
```json
{"error":"Only the first of the month is allowed for this request"}
```

The response contains availability for the entire month. Always filter client-side for the user's actual date range.

```python
from datetime import datetime
dt = datetime.strptime(user_start_date, '%Y-%m-%d')
month_start = dt.replace(day=1).strftime('%Y-%m-%d')
# Use month_start in the API call
```

## Output Stream Separation (2026-06-22)

When using `--json` output for piping to other tools:
- **stdout**: Clean JSON only
- **stderr**: Progress indicators, error messages, rate limit warnings

Always separate streams: `python3 script.py --json 2>/dev/null | jq ...`

Progress messages were originally written to stdout (broken), fixed to stderr on 2026-06-22.

## Finding Campground IDs

Since the search API is unreliable for discovery, the best approaches are:

1. **Browse recreation.gov** — URL contains the ID: `recreation.gov/camping/campgrounds/{ID}`
2. **Search with short unique terms** — `q=Trillium` works better than `q=Trillium Lake Campground`
3. **Filter client-side** — Always check `entity_type == 'campground'` and `state_code == 'Oregon'`

## Campsite Type Taxonomy & Tent Filtering (updated 2026-06-22)

The `campsite_type` field in availability responses determines what kind of camping a site supports. User preference is **tent-camping only** — RV, equestrian, group, picnic, day-use, and yurt sites are excluded.

### Known campsite_type values

| campsite_type | Include? | Description |
|---|---|---|
| `TENT ONLY NONELECTRIC` | ✅ Yes | Tent-only, no RVs allowed |
| `STANDARD NONELECTRIC` | ✅ Yes | Mixed — tents and small RVs/trailers OK |
| `RV NONELECTRIC` | ❌ No | RV-only sites |
| `EQUESTRIAN NONELECTRIC` | ❌ No | Horse/equestrian sites |
| `GROUP PICNIC AREA` | ❌ No | Day-use group picnic shelter |
| `GROUP STANDARD AREA NONELECTRIC` | ❌ No | Group camping areas |
| `PICNIC` | ❌ No | Day-use picnic tables |
| `YURT` | ❌ No | Yurt structures |

### Filtering implementation

```python
TENT_TYPES = {'TENT ONLY NONELECTRIC', 'STANDARD NONELECTRIC'}

for site_id, site_data in campsites.items():
    campsite_type = site_data.get('campsite_type', '')
    if campsite_type not in TENT_TYPES:
        continue
    # ... process availability
```

### Real-world examples (verified 2026-06-22)

- **Trillium (ID 232831)**: 50 total sites → 47 tent (34 STANDARD + 13 TENT ONLY), 3 filtered (1 YURT + 2 GROUP PICNIC)
- **Clackamas Lake (ID 232870)**: 44 total sites → 35 tent (25 TENT ONLY + 10 STANDARD), 9 filtered (EQUESTRIAN)
- **Lost Lake Resort (ID 251434)**: 87 total sites → 15 tent (15 TENT ONLY), 72 filtered (65 RV + 4 GROUP STANDARD + 2 PICNIC + 1 GROUP PICNIC)

### Output format (user preference, updated 2026-06-22)

User explicitly requested:
- **No site numbers** in output — only total count and available count
- **Markdown table** format: `| Campground | Type | Available |`
  - Campground: markdown link — the name IS the booking link: `[Name](https://www.recreation.gov/camping/campgrounds/{id})`
  - Type: area + distance label (e.g. "Estacada (~75 min)", "Coast (~2.5 hrs)") from `CAMPGROUND_AREAS` dict
  - Available: combined `# available / # total` format (e.g. "30/61")
- **No separate link column** — the campground name is the link
- **No price column** (price data unreliable from API)
- Sort by availability (most available first)
- **Always show the full table** — not just top N. The `--top` flag only controls the initial preview but the table should include all results.

### Price Range Data (2026-06-22)

The search API `price_range` field (`{"amount_min": 22, "amount_max": 44, "per_unit": "night"}`) is **unreliable** — it's frequently missing or inconsistent across campgrounds. Do not depend on it for display. If the user asks for pricing, direct them to the booking link for current rates.

- Tested from Hermes WebUI container (192.168.1.12)
- `execute_code` blocks `urllib` HTTP calls in this environment — use `terminal` with `python3` instead
- `curl` works but may be killed on slow responses — use `--max-time 30`
- The `X-Requested-With` header trick was discovered by accident when comparing browser vs curl behavior
- URL-encoding the `start_date` parameter is required — discovered 2026-06-22 when all requests returned "query not encoded"
