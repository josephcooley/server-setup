---
name: campground-finder
description: Search for available tent-camping sites near Beaverton, Oregon using Recreation.gov. Filters out RV-only, equestrian, group/picnic/day-use, and yurt sites. Output is a markdown table with campground names as direct booking links, area/distance column, and combined available/total counts.
---

# Campground Finder — Beaverton, OR

Search for available tent-camping sites near Beaverton, OR (Portland metro area). Queries Recreation.gov for real-time availability at federal campgrounds (USFS, NPS, BLM).

## What This Does

- Searches for reservable campgrounds within a configurable radius of Beaverton
- Checks site-level availability for a given date range
- Can target specific campground IDs or search broadly
- **Tent-camping only** — filters out RV-only, equestrian, group/picnic/day-use, and yurt sites. Only `TENT ONLY NONELECTRIC` and `STANDARD NONELECTRIC` sites are included in results.

## Output Format (user preference — do not change without asking)

The user explicitly requested this format. Deviating from it triggers corrections.

- **Always output a markdown table** — never a bulleted list
- **Columns**: `| Campground | Type | Available |`
  - Campground: markdown link to booking page — the name IS the link. No separate link column.
  - Type: area + distance label from `CAMPGROUND_AREAS` dict (e.g. "Estacada (~75 min)", "Coast (~2.5 hrs)")
  - Available: combined `# available / # total` format (e.g. "30/61")
- **No site numbers** — only show total site count and available count. The user does not want individual site numbers listed.
- **Sort by distance (closest first)**, then by availability within same distance band
- **Single campground mode** (`--campground-id`): Shows header + count, NOT a table (too small to warrant it)

## Known API Quirks (tested 2026-06-22)

These are critical — the script handles all of them, but any reimplementation must account for each:

1. **URL-encode the `start_date` parameter.** Use `urllib.parse.urlencode()`. Raw `T00:00:00.000Z` in the URL string returns `{"error":"query not encoded"}`.
2. **Availability endpoint requires the 1st of the month.** Pass `start_date=2026-06-01T00:00:00.000Z` even if the user wants June 27–28. The response contains the full month; filter client-side.
3. **Rate limiting is aggressive.** The API returns HTTP 429 ("heavy traffic") even with moderate request volumes. The script implements exponential backoff retries (3s, 6s) and a 0.5s delay between requests. Some requests may still fail after 3 retries — this is expected, not a bug. When many 429s occur, results may be incomplete; re-run after a minute for fuller results.
4. **Progress output goes to stderr; JSON goes to stdout.** The `--json` output is clean JSON on stdout only. Progress indicators and error messages are routed to stderr. Always separate: `python3 script.py --json 2>/dev/null | jq ...`
5. **Status values changed.** The API now uses `"Reserved"` (not `"Not Available"`) and `"Not Reservable"` (off-season/closed). The script only counts `"Available"` as bookable.
6. **Price range data is unreliable.** The search API `price_range` field is frequently missing or inconsistent across campgrounds. Do not depend on it for display. If the user asks for pricing, direct them to the booking link for current rates.

## Quick Start

### Search by Date Range

```bash
python3 ~/.hermes/skills/campground-finder/scripts/campground_finder.py \
  --start 2026-07-15 --end 2026-07-18
```

### Check Specific Campground

```bash
python3 ~/.hermes/skills/campground-finder/scripts/campground_finder.py \
  --campground-id 232831 --start 2026-07-15 --end 2026-07-18
```

### Filter by Name

```bash
python3 ~/.hermes/skills/campground-finder/scripts/campground_finder.py \
  --start 2026-07-15 --end 2026-07-18 --filter "Trillium,Eagle Creek"
```

### JSON Output (for piping to other tools)

```bash
python3 ~/.hermes/skills/campground-finder/scripts/campground_finder.py \
  --start 2026-07-15 --end 2026-07-18 --json 2>/dev/null | jq .
```

## API Reference

### Recreation.gov Search API

```
GET https://www.recreation.gov/api/search?limit=10&q=Trillium
```

Required headers:
```
accept: application/json
X-Requested-With: XMLHttpRequest
Referer: https://www.recreation.gov/
```

**Critical:** The `X-Requested-With: XMLHttpRequest` header is required. Without it, the API returns HTML instead of JSON.

### Availability API

```
GET https://www.recreation.gov/api/camps/availability/campground/{id}/month
  ?start_date=2026-07-01T00:00:00.000Z
```

**URL Encoding:** The `start_date` query parameter MUST be URL-encoded. Use `urllib.parse.urlencode()`. Passing raw `T00:00:00.000Z` returns `{"error":"query not encoded"}`.

**First-of-month required:** The API rejects any `start_date` that isn't the 1st of the month.

Same headers required. Returns `campsites` dict keyed by site ID, each with an `availabilities` map of date → status.

## Campsite Type Taxonomy

The `campsite_type` field determines what kind of camping a site supports. The script filters to **tent-camping types only**:

| campsite_type | Included? | Description |
|---|---|---|
| `TENT ONLY NONELECTRIC` | ✅ Yes | Tent-only, no RVs |
| `STANDARD NONELECTRIC` | ✅ Yes | Mixed use — tents and small RVs/trailers |
| `RV NONELECTRIC` | ❌ No | RV-only sites |
| `EQUESTRIAN NONELECTRIC` | ❌ No | Horse/equestrian sites |
| `GROUP PICNIC AREA` | ❌ No | Day-use group picnic |
| `GROUP STANDARD AREA NONELECTRIC` | ❌ No | Group camping areas |
| `PICNIC` | ❌ No | Day-use picnic |
| `YURT` | ❌ No | Yurt structures |

## Verified Campground IDs

Key campgrounds within ~2 hours of Beaverton (coordinate: 45.4871, -122.8037). Full list of 49 IDs is in the script's `CAMPGROUND_IDS` dict.

### Columbia River Gorge (~30-60 min)
| ID | Campground | Sites |
|----|-----------|-------|
| 122890 | Eagle Creek | 17 |
| 122940 | Wyeth | 16 |

### Mount Hood National Forest (~60-90 min)
| ID | Campground | Sites |
|----|-----------|-------|
| 232831 | Trillium | 50 |
| 232835 | Still Creek | 26 |
| 232837 | Camp Creek | 24 |
| 232836 | Tollgate | 14 |
| 232838 | Lost Creek | 14 |
| 272096 | Nottingham | 21 |
| 251434 | Lost Lake Resort | 87 |

### Timothy Lake / Estacada Area (~60-90 min)
| ID | Campground | Sites |
|----|-----------|-------|
| 232867 | Hoodview | 44 |
| 232866 | Gone Creek | 48 |
| 232868 | Oak Fork | 49 |
| 10208831 | Stone Creek | 43 |
| 232865 | Pine Point | 26 |
| 232870 | Clackamas Lake | 44 |

### Detroit / Santiam (~2 hrs)
| ID | Campground | Sites |
|----|-----------|-------|
| 233301 | Breitenbush | 28 |
| 233693 | Hoover | 35 |
| 233694 | Cove Creek | 61 |
| 233258 | Riverside at Detroit | 37 |
| 255135 | Southshore at Detroit Lake | 28 |
| 251470 | Whispering Falls | 14 |

### Central Oregon / Bend (~2.5-3 hrs)
| ID | Campground | Sites |
|----|-----------|-------|
| 267555 | Elk Lake | 19 |
| 251448 | Lava Lake | 43 |
| 233215 | Little Lava Lake | 16 |

### Oregon Coast (~2-2.5 hrs)
| ID | Campground | Sites |
|----|-----------|-------|
| 233110 | Tahkenitch | 24 |
| 234578 | Lagoon | 37 |
| 233111 | Tyee (Oregon Dunes) | 15 |

### Molalla / French Prairie (~45 min)
| ID | Campground | Sites |
|----|-----------|-------|
| 262754 | Three Bears | 15 |
| 262756 | Cedar Grove | 10 |

## Conversation Flow

When the user asks about camping:

1. **Identify dates** — "When are you looking to camp?" (if not specified). User often phrases as "next weekend", "N weekends from now" — convert to actual dates (today + N*7 days for "N weekends from now").
2. **Run the search** — Use the script with appropriate parameters.
3. **Present results** — Output is a markdown table with linked campground names sorted by distance (closest first). No site numbers. No price column (unreliable API data).
4. **Quick summary** — After the table, offer 2-3 bullet points highlighting best options per distance band (e.g., "Closest with good availability: X", "Best scenery: Y"). Keep it concise.

### Example User Prompts
- "Find campgrounds near Beaverton available July 4th weekend"
- "What's available 3 weekends from now?"
- "Is Trillium open August 15-18?"
- "Check tent sites for next Saturday night"

### If No Availability Found
- Suggest adjusting dates (mid-week is easier)
- Suggest first-come, first-served campgrounds
- Note that some USFS campgrounds don't take reservations
- Check Oregon State Parks at oregonstateparks.org

## Dependencies

- Python 3.7+
- Standard library only (urllib, json, datetime) — no pip install needed

## Reference Files

- `references/recreation-gov-api.md` — Live-tested API response structures, endpoint quirks, campsite type taxonomy, and environment notes
