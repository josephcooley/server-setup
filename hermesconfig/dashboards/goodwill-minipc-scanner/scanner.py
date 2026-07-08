#!/usr/bin/env python3
"""
ShopGoodwill Mini PC Scanner
Scans shopgoodwill.com for mini PCs with 8th gen Intel processors or above.
Uses the internal API at buyerapi.shopgoodwill.com/api/

NOTE: The API rate-limits after a few requests. We keep it to ~3-4 calls per run.
"""

import re
import sys
import json
import time
import logging
import html as html_mod
from datetime import datetime
from pathlib import Path

import requests

# ── Configuration ──────────────────────────────────────────────────────────────

API_BASE = "https://buyerapi.shopgoodwill.com/api/"
COMPUTERS_CAT_ID = 30

GEN_FROM_MODEL = re.compile(r'i[3579]-(\d)\d{3,4}', re.IGNORECASE)
GEN_FROM_TEXT = re.compile(
    r'(?:8th|9th|10th|11th|12th|13th|14th|15th)\s*(?:gen|generation)', re.IGNORECASE,
)
CORE_ULTRA = re.compile(r'core\s+ultra|ultra\s+(?:5|7|9)', re.IGNORECASE)
AMD_GEN = re.compile(r'ryzen\s+(?:3|5|7|9)\s*[3-9]\d{3}', re.IGNORECASE)
MIN_INTEL_GEN = 8

MINIPC_PATTERNS = [
    re.compile(r'mini\s*pc', re.IGNORECASE),
    re.compile(r'mini\s*desktop', re.IGNORECASE),
    re.compile(r'minipc', re.IGNORECASE),
    re.compile(r'small\s*form\s*factor', re.IGNORECASE),
    re.compile(r'\bsff\b', re.IGNORECASE),
    re.compile(r'tiny\s*desktop', re.IGNORECASE),
    re.compile(r'micro\s*desktop', re.IGNORECASE),
    re.compile(r'\bnuc\b', re.IGNORECASE),
    re.compile(r'thinkcentre\s*tiny', re.IGNORECASE),
    re.compile(r'optiplex\s*micro', re.IGNORECASE),
    re.compile(r'elitedesk\s*mini', re.IGNORECASE),
    re.compile(r'prodesk\s*mini', re.IGNORECASE),
    re.compile(r'ideacentre\s*mini', re.IGNORECASE),
    re.compile(r'gm\d', re.IGNORECASE),
    re.compile(r'beelink', re.IGNORECASE),
    re.compile(r'minisforum', re.IGNORECASE),
    re.compile(r'geekom', re.IGNORECASE),
]

SCRIPT_DIR = Path(__file__).parent
STATE_FILE = SCRIPT_DIR / "seen_listings.json"
OUTPUT_FILE = SCRIPT_DIR / "results.json"

# HTML output directory on the workspace
HTML_DIR = Path("/workspace/dashboards/minipc-search")
HTML_FILE = HTML_DIR / "index.html"
HISTORY_FILE = HTML_DIR / "history.json"

# ── Logging ────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(SCRIPT_DIR / "scanner.log"),
    ],
)
log = logging.getLogger("shopgoodwill-scanner")


# ── API ────────────────────────────────────────────────────────────────────────

def make_session() -> requests.Session:
    s = requests.Session()
    s.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-US,en;q=0.5",
        "Accept-Encoding": "gzip, deflate, br",
        "Origin": "https://shopgoodwill.com",
        "Referer": "https://shopgoodwill.com/",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-site",
    })
    try:
        s.get("https://shopgoodwill.com/", timeout=20)
    except requests.RequestException:
        pass
    return s


def build_body(query: str, page: int = 1) -> dict:
    now = datetime.now()
    return {
        "searchText": query,
        "selectedGroup": "",
        "selectedCategoryIds": str(COMPUTERS_CAT_ID),
        "selectedSellerIds": "",
        "lowPrice": 0,
        "highPrice": 999999,
        "searchBuyNowOnly": "",
        "searchPickupOnly": False,
        "searchNoPickupOnly": False,
        "searchOneCentShippingOnly": False,
        "searchDescriptions": True,
        "searchClosedAuctions": False,
        "closedAuctionEndingDate": now.strftime("%m/%d/%Y"),
        "closedAuctionDaysBack": 7,
        "searchCanadaShipping": False,
        "searchInternationalShippingOnly": False,
        "sortColumn": 1,
        "page": page,
        "pageSize": 40,
        "sortDescending": False,
        "savedSearchId": 0,
        "useBuyerPrefs": True,
        "searchUSOnlyShipping": False,
        "categoryLevelNo": 1,
        "catIds": str(COMPUTERS_CAT_ID),
        "partNumber": "",
        "isWeddingCatagory": False,
        "isMultipleCategoryIds": False,
        "isFromHeaderMenuTab": True,
        "layout": "grid",
        "isFromHomePage": "",
    }


def do_search(session: requests.Session, query: str, page: int = 1) -> list[dict]:
    body = build_body(query, page)
    try:
        resp = session.post(f"{API_BASE}Search/ItemListing", json=body, timeout=30)
        if resp.status_code == 200:
            return resp.json().get("searchResults", {}).get("items", [])
        log.warning(f"  Search returned {resp.status_code}: {resp.text[:100]}")
    except requests.RequestException as e:
        log.error(f"  Search error: {e}")
    return []


def get_description(session: requests.Session, item_id: int) -> str:
    try:
        resp = session.get(
            f"{API_BASE}ItemDetail/GetItemDetailModelByItemId/{item_id}", timeout=15
        )
        if resp.status_code == 200:
            html_text = resp.json().get("description", "") or ""
            text = re.sub(r'<[^>]+>', ' ', html_text)
            text = html_mod.unescape(text)
            return re.sub(r'\s+', ' ', text).strip()
    except requests.RequestException:
        pass
    return ""


# ── Matching ───────────────────────────────────────────────────────────────────

def is_minipc(title: str, description: str = "") -> bool:
    combined = f"{title} {description}"
    return any(p.search(combined) for p in MINIPC_PATTERNS)


def has_modern_cpu(text: str) -> bool:
    if GEN_FROM_TEXT.search(text):
        return True
    if CORE_ULTRA.search(text):
        return True
    if AMD_GEN.search(text):
        return True
    for m in GEN_FROM_MODEL.finditer(text):
        if int(m.group(1)) >= MIN_INTEL_GEN:
            return True
    return False


# ── State ──────────────────────────────────────────────────────────────────────

def load_seen() -> set:
    if STATE_FILE.exists():
        try:
            return set(json.loads(STATE_FILE.read_text()))
        except Exception:
            return set()
    return set()


def save_seen(seen: set):
    STATE_FILE.write_text(json.dumps(list(seen)))


# ── HTML generation ────────────────────────────────────────────────────────────

def build_html(matches: list[dict], scan_time: str, query: str) -> str:
    """Build a clean, dark-themed HTML page with all matched listings."""
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M")

    cards = ""
    for m in matches:
        price = f"${m['price']:.2f}"
        if m.get("buyNowPrice", 0) > 0:
            price += f' <span class="buynow">Buy Now: ${m["buyNowPrice"]:.2f}</span>'

        end_time = m.get("endTime", "")
        if end_time:
            try:
                dt = datetime.fromisoformat(end_time.replace("Z", "+00:00"))
                end_time = dt.strftime("%b %d, %Y %I:%M %p")
            except Exception:
                pass

        image = m.get("imageURL", "")
        image_html = (
            f'<img src="{image}" alt="{html_mod.escape(m["title"])}" loading="lazy">'
            if image
            else '<div class="no-image">No Image</div>'
        )

        desc = html_mod.escape(m.get("description", "")[:200])
        category = html_mod.escape(m.get("category", ""))
        url = m.get("url", "#")

        cards += f"""
        <div class="card">
            <div class="image-wrap">
                {image_html}
            </div>
            <div class="info">
                <h3><a href="{url}" target="_blank" rel="noopener">{html_mod.escape(m["title"])}</a></h3>
                <div class="meta">
                    <span class="price">{price}</span>
                    <span class="end-time">⏰ {end_time}</span>
                </div>
                <p class="desc">{desc}</p>
                <p class="category">📁 {category}</p>
                <a class="btn" href="{url}" target="_blank" rel="noopener">View Listing →</a>
            </div>
        </div>"""

    empty_msg = ""
    if not matches:
        empty_msg = '<div class="empty">No new 8th gen+ mini PCs found this run. Check back later!</div>'

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ShopGoodwill Mini PC Scanner</title>
<style>
*, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}

body {{
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #0d1117;
    color: #c9d1d9;
    line-height: 1.6;
}}

header {{
    background: linear-gradient(135deg, #161b22 0%, #1a2332 100%);
    border-bottom: 1px solid #30363d;
    padding: 24px 32px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    gap: 12px;
}}

header h1 {{
    font-size: 1.4rem;
    color: #58a6ff;
}}

header h1 span {{
    color: #8b949e;
    font-weight: 400;
    font-size: 0.85rem;
    display: block;
    margin-top: 2px;
}}

.stats {{
    display: flex;
    gap: 20px;
    font-size: 0.85rem;
    color: #8b949e;
}}

.stats strong {{
    color: #c9d1d9;
}}

.container {{
    max-width: 1200px;
    margin: 0 auto;
    padding: 24px 32px;
}}

.empty {{
    text-align: center;
    padding: 80px 20px;
    color: #8b949e;
    font-size: 1.1rem;
}}

.grid {{
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
    gap: 20px;
}}

.card {{
    background: #161b22;
    border: 1px solid #30363d;
    border-radius: 12px;
    overflow: hidden;
    transition: border-color 0.2s, transform 0.2s;
}}

.card:hover {{
    border-color: #58a6ff;
    transform: translateY(-2px);
}}

.image-wrap {{
    height: 200px;
    background: #0d1117;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
}}

.image-wrap img {{
    width: 100%;
    height: 100%;
    object-fit: contain;
    padding: 12px;
}}

.no-image {{
    color: #30363d;
    font-size: 0.9rem;
}}

.info {{
    padding: 16px;
}}

.info h3 {{
    font-size: 0.95rem;
    margin-bottom: 8px;
    line-height: 1.4;
}}

.info h3 a {{
    color: #58a6ff;
    text-decoration: none;
}}

.info h3 a:hover {{
    text-decoration: underline;
}}

.meta {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 10px;
    flex-wrap: wrap;
    gap: 8px;
}}

.price {{
    font-size: 1.15rem;
    font-weight: 700;
    color: #3fb950;
}}

.buynow {{
    font-size: 0.8rem;
    color: #d29922;
    font-weight: 400;
}}

.end-time {{
    font-size: 0.8rem;
    color: #8b949e;
}}

.desc {{
    font-size: 0.82rem;
    color: #8b949e;
    margin-bottom: 8px;
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
}}

.category {{
    font-size: 0.75rem;
    color: #6e7681;
    margin-bottom: 12px;
}}

.btn {{
    display: inline-block;
    padding: 8px 16px;
    background: #238636;
    color: #fff;
    text-decoration: none;
    border-radius: 6px;
    font-size: 0.85rem;
    font-weight: 500;
    transition: background 0.2s;
}}

.btn:hover {{
    background: #2ea043;
}}

footer {{
    text-align: center;
    padding: 24px;
    color: #30363d;
    font-size: 0.75rem;
    border-top: 1px solid #21262d;
    margin-top: 40px;
}}
</style>
</head>
<body>

<header>
    <h1>🔍 ShopGoodwill Mini PC Scanner<br><span>8th gen Intel / Ryzen 3000+ mini PCs</span></h1>
    <div class="stats">
        <div>Matches: <strong>{len(matches)}</strong></div>
        <div>Query: <strong>{html_mod.escape(query)}</strong></div>
        <div>Updated: <strong>{now_str}</strong></div>
    </div>
</header>

<div class="container">
    {empty_msg}
    <div class="grid">
        {cards}
    </div>
</div>

<footer>
    ShopGoodwill Mini PC Scanner — Auto-updated every 4 hours via Hermes Agent
</footer>

</body>
</html>"""


def generate_html(matches: list[dict], scan_time: str, query: str):
    """Write the HTML page and update history."""
    HTML_DIR.mkdir(parents=True, exist_ok=True)

    html = build_html(matches, scan_time, query)
    HTML_FILE.write_text(html, encoding="utf-8")
    log.info(f"HTML page written to {HTML_FILE}")

    # Update history
    history = []
    if HISTORY_FILE.exists():
        try:
            history = json.loads(HISTORY_FILE.read_text())
        except Exception:
            history = []

    history.append({
        "scan_time": scan_time,
        "query": query,
        "match_count": len(matches),
        "item_ids": [m["itemId"] for m in matches],
    })
    # Keep last 50 runs
    history = history[-50:]
    HISTORY_FILE.write_text(json.dumps(history, indent=2))


# ── Main ───────────────────────────────────────────────────────────────────────

def run_scan():
    log.info("=" * 60)
    log.info(f"ShopGoodwill Mini PC scan — {datetime.now().isoformat()}")
    log.info("=" * 60)

    session = make_session()
    seen = load_seen()
    matches = []
    new_seen = set()

    hour = datetime.now().hour
    query_index = (hour // 4) % 4
    queries = ["mini pc", "NUC", "GEEKOM", "Beelink"]
    query = queries[query_index]

    log.info(f"Using query: '{query}' (rotation {query_index + 1}/4)")

    items = do_search(session, query, page=1)
    if not items:
        log.info("No results or API error.")
        scan_time = datetime.now().isoformat()
        generate_html([], scan_time, query)
        save_seen(seen)
        return []

    log.info(f"Got {len(items)} items")

    for item in items:
        item_id = str(item["itemId"])
        if item_id in seen or item_id in new_seen:
            continue
        new_seen.add(item_id)

        title = item.get("title", "")
        description = (item.get("description") or "") or ""

        if not is_minipc(title, description):
            continue

        combined = f"{title} {description}"
        if not has_modern_cpu(combined):
            full_desc = get_description(session, item["itemId"])
            combined = f"{title} {full_desc}"
            if not has_modern_cpu(combined):
                continue
            description = full_desc[:300]

        match = {
            "itemId": item["itemId"],
            "title": title,
            "description": description or "(see listing)",
            "price": item.get("currentPrice", 0),
            "buyNowPrice": item.get("buyNowPrice", 0),
            "endTime": item.get("endTime", ""),
            "imageURL": item.get("imageURL", ""),
            "category": item.get("catFullName", ""),
            "url": f"https://shopgoodwill.com/item/{item['itemId']}",
        }

        log.info(f"  ✓ {title[:80]}")
        log.info(f"    ${match['price']} (BN: ${match.get('buyNowPrice', 0)})  {match['url']}")
        matches.append(match)

    seen.update(new_seen)
    save_seen(seen)

    scan_time = datetime.now().isoformat()
    results = {
        "scan_time": scan_time,
        "query": query,
        "total_matches": len(matches),
        "matches": matches,
    }
    OUTPUT_FILE.write_text(json.dumps(results, indent=2))

    # Generate HTML page
    generate_html(matches, scan_time, query)

    log.info(f"Done. {len(matches)} new matches.")
    return matches


def format_report(matches: list[dict]) -> str:
    if not matches:
        return "🔍 ShopGoodwill Mini PC Scan: No new 8th gen+ mini PCs found.\n\nView results: /workspace/dashboards/minipc-search/index.html"

    lines = [
        f"🔍 ShopGoodwill Mini PC Scan — {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"Found {len(matches)} new mini PC(s):\n",
    ]
    for i, m in enumerate(matches, 1):
        lines.append(f"  {i}. {m['title']}")
        price = f"${m['price']}"
        if m.get("buyNowPrice", 0) > 0:
            price += f" (Buy Now: ${m['buyNowPrice']})"
        lines.append(f"     💰 {price}")
        if m.get("endTime"):
            lines.append(f"     ⏰ Ends: {m['endTime']}")
        lines.append(f"     🔗 {m['url']}")
        lines.append("")
    lines.append("📄 Full results: /workspace/dashboards/minipc-search/index.html")
    return "\n".join(lines)


if __name__ == "__main__":
    matches = run_scan()
    print("\n" + format_report(matches))
