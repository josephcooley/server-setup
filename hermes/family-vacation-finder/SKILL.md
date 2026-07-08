---
name: family-vacation-finder
description: "Use when searching for family-friendly short-term rental properties (Airbnb, VRBO, etc.) for family trips. Handles guest counting, bedroom calculation, hot-tub preference, and produces a curated comparison table. Triggers on: 'find a rental', 'vacation home', 'family trip', 'Airbnb search', 'VRBO search', 'short-term rental', 'beach house', 'cabin rental'."
version: 1.0.0
author: Joseph Cooley
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [travel, vacation, airbnb, vrbo, family, rental, booking, short-term-rental]
    related_skills: [web-scraping-monitoring, plan]
---

# Family Vacation Home Finder

Search short-term rental platforms for family-friendly properties. Dynamically calculates bedroom needs, prioritizes hot tubs, and delivers a curated comparison table.

## What This Does

- Searches Airbnb, VRBO, and similar platforms for vacation rentals
- Enforces a **minimum of 2 bedrooms** for the immediate family (Joseph, Whitney, Holdyn, Bryce)
- **Asks about additional guests** before searching, then adjusts bedroom count accordingly
- Prioritizes properties with hot tubs/jacuzzis but doesn't exclude otherwise perfect matches
- Returns a curated markdown table of 5–10 top properties with links, pricing, bedroom count, and hot tub status

## Tool Availability & Execution Strategy

This skill requires web access to search rental platforms. There are two execution paths:

### Path A: `web_search` Available (Preferred)
If the `web` toolset is loaded (e.g., CLI mode with web tools enabled), use `web_search` with `site:airbnb.com` and `site:vrbo.com` queries. This is the most reliable method.

### Path B: Script-Based Search (Fallback)
If `web_search` is **not available** (common in WebUI sandbox sessions), use the `scripts/rental_search.py` script that curls search result pages directly. This is fragile (platforms may block scraping) but works as a fallback.

**Always check for `web_search` availability first.** If present, use Path A. If missing, fall back to Path B and inform the user that results may be limited due to scraping constraints.

> **Why this matters:** The `web_search` tool is part of the `web` toolset which is not enabled by default in all Hermes sessions. The campground-finder skill avoids this by using a direct API script — rental platforms don't have public APIs, so we rely on search engine results or direct scraping.

## Input Variables

Collect these from the user (ask for any that are missing):

| Variable | Required | Description |
|----------|----------|-------------|
| **Location** | ✅ Yes | City, region, or landmark (e.g. "Cannon Beach, OR", "Lake Tahoe") |
| **Check-in Date** | ✅ Yes | Arrival date (YYYY-MM-DD or natural language) |
| **Check-out Date** | ✅ Yes | Departure date |
| **Additional Guests** | ✅ Yes | Asked explicitly — see Conversation Flow below |
| **Bedrooms** | Auto | Calculated: 2 base + additional based on guest count |
| **Budget Range** | Optional | Max nightly or total budget |
| **Must-haves** | Optional | Pet-friendly, pool, waterfront, etc. |

## Bedroom Calculation Rules

```
Base bedrooms: 2 (Joseph + Whitney in one, Holdyn + Bryce in one)

Additional guests → extra bedrooms:
  1–2 extra guests  → +1 bedroom (total 3)
  3–4 extra guests  → +2 bedrooms (total 4)
  5+ extra guests   → +3 bedrooms (total 5)

Round up: If guests don't evenly split, round up to ensure everyone has a bed.
```

**Never go below 2 bedrooms regardless of guest count.** The base family unit always needs 2.

## Conversation Flow

### Step 1: Collect Core Inputs

Ask for location and dates if not provided in the initial prompt. Be conversational:

> "Where are you looking to go, and what dates are you targeting?"

### Step 2: Ask About Additional Guests (REQUIRED — Never Skip)

Before any search, **always** ask:

> "Are there any additional family members or guests coming with you on this trip?"

This is non-negotiable. The bedroom count depends on it. If the user says the search is just for the core family, note that and proceed with 2 bedrooms.

### Step 3: Calculate Bedrooms

Apply the bedroom calculation rules above. State the result explicitly:

> "Got it — I'll search for properties with **3 bedrooms** (2 for your family + 1 for Grandma and Grandpa)."

### Step 4: Execute Search

**Check tool availability first:**

```
- If `web_search` tool exists → use Path A (preferred, more reliable)
- If `web_search` does NOT exist → use Path B (script fallback)
```

#### Path A: `web_search` Queries

Use `web_search` to search across platforms. Construct queries like:

```
site:airbnb.com [location] [check-in] [check-out] [X] bedrooms hot tub
site:vrbo.com [location] [check-in] [check-out] [X] bedrooms hot tub
[location] vacation rental [X] bedroom hot tub family friendly
```

Run **2–3 parallel searches** to cover multiple platforms. If the user specified a budget, include it in the query.

### Path B: Script-Based Search (Fallback)

If `web_search` is **not available** (common in WebUI sandbox sessions), use the `scripts/rental_search.py` script that curls search result pages directly. This is fragile (platforms may block scraping) but works as a fallback.

> **Need to enable `web_search` permanently?** See `references/toolset-availability.md` in this skill, or load the `hermes-agent` skill and read `references/web-search-setup.md` for the full ddgs-based setup guide.

```bash
python3 ~/.hermes/skills/family-vacation-finder/scripts/rental_search.py \
  --location "Bend, OR" \
  --checkin 2026-07-03 --checkout 2026-07-06 \
  --bedrooms 2 --hot-tub
```

The script curls search result pages and extracts property data. **Note:** Platforms actively block scraping — if results are incomplete, inform the user and suggest enabling the `web` toolset for future searches.

### Step 5: Curate Results

Filter and rank results by:

1. **Bedroom count** — Must meet or exceed calculated minimum
2. **Hot tub** — Prioritize properties that have one (rank higher in table)
3. **Family-friendly signals** — "Family friendly", "children", "crib", "high chair", "playground", "game room"
4. **Rating** — Prefer 4.5+ star properties
5. **Value** — Best price per bedroom ratio within budget

Select **5–10 top properties** for the final table.

### Step 6: Present Results

Output the comparison table (see Output Format below), then add a brief summary highlighting:
- Best overall pick (best value + hot tub)
- Best budget option
- Best luxury option (if applicable)

## Output Format

Always output a markdown table. This is the user's preferred format.

```
| # | Property | Bedrooms | Sleeps | Total Price | Hot Tub | Platform |
|---|----------|----------|--------|-------------|---------|----------|
| 1 | [Beach House Name](https://airbnb.com/rooms/...) | 3 | 8 | $1,250 (5 nights) | ✅ Yes | Airbnb |
| 2 | [Cabin Retreat](https://vrbo.com/...) | 4 | 10 | $980 (5 nights) | ❌ No | VRBO |
...
```

### Column Definitions

- **#**: Rank (1 = best overall pick)
- **Property**: Markdown link — the property name IS the link. No separate link column.
- **Bedrooms**: Number of bedrooms (must be ≥ calculated minimum)
- **Sleeps**: Max guest capacity
- **Total Price**: Total stay price with night count in parentheses. If only nightly is available, show nightly × nights.
- **Hot Tub**: ✅ Yes / ❌ No
- **Platform**: Airbnb / VRBO / Other

### Sort Order

1. Hot tub properties first (ranked by value within that group)
2. Non-hot-tub properties second (ranked by value)
3. Within each group, sort by best value (lowest price per bedroom)

### Summary Section (After Table)

Add 2–4 bullet points after the table:

- 🏆 **Best Overall**: [Name] — why (hot tub + value + rating)
- 💰 **Best Budget**: [Name] — lowest total price that meets criteria
- ⭐ **Highest Rated**: [Name] — if different from above
- ⚠️ **Note**: Any caveats (e.g., "Hot tub not confirmed — verify with host")

## Platform-Specific Search Tips

### Airbnb
- Search URL pattern: `https://www.airbnb.com/s/[location]/homes?checkin=[date]&checkout=[date]&adults=[N]&min_bedrooms=[N]`
- Use `web_search` with `site:airbnb.com` for discovery
- Airbnb search filters: "Amenities" → "Hot tub", "Bedrooms" → set minimum

### VRBO
- Search URL pattern: `https://www.vrbo.com/search?adults=[N]&bedrooms=[N]&location=[location]&startDate=[date]&endDate=[date]`
- Use `web_search` with `site:vrbo.com` for discovery
- VRBO filter: "Hot tub" under Amenities

### Other Platforms
- Booking.com: Good for international destinations
- Vacasa: Managed vacation rentals, reliable quality
- Direct resort sites: Often have hot tub cabins (e.g., national park lodges)

## Common Pitfalls

1. **Forgetting to ask about additional guests.** Always ask before searching. The bedroom count is wrong without this.
2. **Showing properties below 2 bedrooms.** Never drop below the base of 2, even if the user says "it's just us" — that IS 2 bedrooms.
3. **Making hot tub mandatory.** If a property is perfect except no hot tub, include it but mark ❌. Don't filter it out entirely.
4. **Mixing up nightly and total price.** Always show total price for the full stay. If you only have nightly, multiply and note it.
5. **Dead links.** When constructing search URLs, verify the URL pattern works. If a direct link isn't available, link to the search results page for that location/date/bedroom combo.
6. **Too many results.** Cap at 10 properties. More than that is overwhelming. If there are 50+ matches, be selective — best value, best rated, best location.

## Verification Checklist

- [ ] Asked about additional guests before searching
- [ ] Bedroom count calculated correctly (base 2 + additional)
- [ ] Search covered at least 2 platforms (Airbnb + VRBO minimum)
- [ ] Results filtered to meet minimum bedroom requirement
- [ ] Hot tub properties ranked higher than non-hot-tub
- [ ] Output is a markdown table (not a bulleted list)
- [ ] Property names are markdown links
- [ ] Total price shown (not just nightly rate)
- [ ] 5–10 properties in final table
- [ ] Summary section with best picks included

## Reference Files

- `scripts/rental_search.py` — Fallback script that curls Airbnb/VRBO search pages when `web_search` is unavailable. Uses `urllib` + regex/JSON extraction (same pattern as campground-finder).
- `references/toolset-availability.md` — Documents why `web_search` is missing in WebUI, the campground-finder comparison, and how to enable the `web` toolset permanently.

**User**: "Find me a beach house in Cannon Beach for July 10-15"

**Assistant**: "Got it — Cannon Beach, July 10-15. Before I search: **are there any additional family members or guests coming with you on this trip?**"

**User**: "Yeah, my parents will be joining"

**Assistant**: "Perfect — I'll search for **3 bedrooms** (2 for your family + 1 for your parents), prioritizing properties with hot tubs. Let me check Airbnb and VRBO..."

*[Runs searches, curates results]*

**Assistant**: "Here are the top picks for Cannon Beach, July 10-15 (3+ bedrooms):"

*[Outputs table + summary]*
