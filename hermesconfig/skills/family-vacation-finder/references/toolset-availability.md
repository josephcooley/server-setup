# Toolset Availability & Search Strategy

## The Problem

The `web_search` tool (part of the `web` toolset) is **not available by default** in Hermes WebUI sessions. This breaks any skill that relies on web search for discovering listings.

**Verified 2026-06-23:** In the WebUI sandbox, the available tools are:
`clarify`, `cronjob`, `delegate_task`, `execute_code`, `ha_*`, `memory`, `patch`, `process`, `read_file`, `search_files`, `session_search`, `skill_manage`, `skill_view`, `skills_list`, `terminal`, `text_to_speech`, `todo`, `vision_analyze`, `write_file`

**Missing:** `web_search`, `browser`, and other tools from the `web` toolset.

## Why Campground Finder Works But Rental Finder Doesn't

| Skill | Search Method | Works in WebUI? |
|-------|--------------|-----------------|
| `campground-finder` | Python script (`urllib`) → Recreation.gov API | ✅ Yes (direct HTTP) |
| `family-vacation-finder` (v1) | `web_search` tool | ❌ No (tool unavailable) |
| `family-vacation-finder` (v2) | Script fallback + `web_search` when available | ✅ Yes (dual path) |

**Key insight:** Recreation.gov has a public JSON API that responds to `urllib` requests with proper headers. Airbnb and VRBO have no public API — they require either:
1. A search engine (`web_search`) to discover listing URLs
2. Direct scraping of their HTML pages (fragile, often blocked)

## Solution Pattern: Dual-Path Execution

The skill now supports both paths:

1. **Path A (`web_search` available):** Use search engine with `site:airbnb.com` / `site:vrbo.com` queries. More reliable, gets fresh results.
2. **Path B (script fallback):** `scripts/rental_search.py` curls search pages directly. Works without `web_search` but may be blocked by bot detection.

## How to Enable `web_search` Permanently

### Step 1: Add `web` to toolsets

In `~/.hermes/config.yaml`:
```yaml
toolsets:
- hermes-cli
- web
```

### Step 2: Install a search provider

**Zero-config option (DuckDuckGo, no API key required):**
```bash
pip3 install ddgs
```

Other options (require API key):
- Brave Search: signup at https://brave.com/search/api/ (2k free/month)
- Tavily: signup at https://app.tavily.com/home
- SearXNG: self-hosted

### Step 3: Set the search backend

In `~/.hermes/config.yaml`:
```yaml
web:
  backend: ''
  search_backend: ddgs    # or 'brave-free', 'tavily', 'searxng'
  extract_backend: ''
```

### Step 4: Restart container + new session

```bash
docker restart hermes-webui
```

**Critical:** You must start a **new** chat session after the config change. Toolsets are session-scoped and do NOT appear in existing sessions.

### Quick Reference: Direct Search URLs (if all else fails)

If neither `web_search` nor the script works, provide these direct links to the user:

Airbnb: `https://www.airbnb.com/s/{location}/homes?checkin={date}&checkout={date}&adults={n}&min_bedrooms={n}`

VRBO: `https://www.vrbo.com/search?adults={n}&bedrooms={n}&location={location}&startDate={date}&endDate={date}`

## Platform Anti-Scraping Notes

- **Airbnb:** Returns 403/redirects to CAPTCHA on non-browser requests. The script uses Chrome User-Agent but this may stop working at any time.
- **VRBO:** Similar bot detection. May return a "verify you are human" page instead of results.
- **Workaround:** If scraping fails, provide the user with direct search URLs they can open manually:

Airbnb: `https://www.airbnb.com/s/{location}/homes?checkin={date}&checkout={date}&adults={n}&min_bedrooms={n}`

VRBO: `https://www.vrbo.com/search?adults={n}&bedrooms={n}&location={location}&startDate={date}&endDate={date}`
