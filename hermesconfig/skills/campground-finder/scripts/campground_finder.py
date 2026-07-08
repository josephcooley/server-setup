#!/usr/bin/env python3
"""
Campground availability checker for Recreation.gov
Searches for available campgrounds near Beaverton, OR and checks site-level availability.

Usage:
    python3 campground_finder.py --start 2026-07-15 --end 2026-07-18
    python3 campground_finder.py --campground-id 232831 --start 2026-07-15 --end 2026-07-18
    python3 campground_finder.py --start 2026-07-15 --end 2026-07-18 --json
    python3 campground_finder.py --start 2026-07-15 --end 2026-07-18 --filter "Trillium,Eagle Creek"
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
from datetime import datetime

# Beaverton, OR coordinates (default)
BEAVERTON_LAT = 45.4871
BEAVERTON_LON = -122.8037

# Real campground IDs near Beaverton, OR (verified via Recreation.gov API)
# Organized by region, roughly sorted by distance from Beaverton
CAMPGROUND_IDS = {
    # === COLUMBIA RIVER GORGE (~30-60 min from Beaverton) ===
    122890: "Eagle Creek Campground",          # Cascade Locks (17 sites)
    122940: "Wyeth Campground",                # Cascade Locks (16 sites)
    234306: "Eagle Creek Overlook Group Site",  # Cascade Locks (1 site)

    # === MT HOOD NATIONAL FOREST (~60-90 min) ===
    232831: "Trillium",                        # Government Camp (50 sites)
    232835: "Still Creek",                     # Government Camp (26 sites)
    232837: "Camp Creek",                      # Government Camp (24 sites)
    232836: "Tollgate",                        # Rhododendron (14 sites)
    232838: "Lost Creek",                      # Rhododendron (14 sites)
    232834: "Riley Horse Campground",          # Rhododendron (13 sites)
    272096: "Nottingham Campground",           # Mount Hood Parkdale (21 sites)
    234075: "Wildwood Recreation Site",        # Welches (7 sites)
    251434: "Lost Lake Resort and Campground", # Hood River (87 sites)

    # === TIMOTHY LAKE / ESTACADA AREA (~60-90 min) ===
    232867: "Hoodview Campground (Timothy Lake)",    # Estacada (44 sites)
    232866: "Gone Creek Campground (Timothy Lake)",   # Estacada (48 sites)
    232868: "Oak Fork Campground (Timothy Lake)",     # Estacada (49 sites)
    10208831: "Stone Creek Campground (Timothy Lake)", # Estacada (43 sites)
    232865: "Pine Point Campground (Timothy Lake)",   # Estacada (26 sites)
    251452: "North Arm Campground (Timothy Lake)",    # Estacada (19 sites)
    232870: "Clackamas Lake",                        # Estacada (44 sites)
    232844: "Ripplebrook",                           # Estacada (13 sites)
    232854: "Kingfisher",                            # Estacada (23 sites)
    232856: "Lake Harriet Campground",               # Estacada (8 sites)
    232863: "Joe Graham Horse Campground",           # Estacada (13 sites)
    232872: "Little Crater Lake",                    # Estacada (15 sites)

    # === MAUPIN / WHITE RIVER AREA (~90 min) ===
    232848: "Frog Lake",                      # Maupin (30 sites)
    232849: "Clear Lake (OR)",                # Maupin (27 sites)
    234720: "Bear Springs Campground",        # Maupin (5 sites)

    # === DETROIT / SANTIAM PASS (~2 hrs) ===
    233301: "Breitenbush Campground",         # Detroit (28 sites)
    251713: "Humbug Campground",              # Detroit (21 sites)
    251616: "Santiam Flats Campground",       # Detroit (29 sites)
    233693: "Hoover Campground",              # Gates (35 sites)
    233694: "Cove Creek (OR)",                # Gates (61 sites)
    233258: "Riverside at Detroit",           # Idanha (37 sites)
    255135: "Southshore at Detroit Lake",     # Gates (28 sites)
    251470: "Whispering Falls Campground",    # Idanha (14 sites)

    # === CENTRAL OREGON / BEND AREA (~2.5-3 hrs) ===
    267555: "Elk Lake Campground",            # Bend (19 sites)
    251448: "Lava Lake Campground",           # Bend (43 sites)
    233215: "Little Lava Lake",               # Bend (16 sites)
    266142: "Jack Creek Campground",          # Camp Sherman (19 sites)
    267081: "Lower Canyon Creek Campground",  # Camp Sherman (5 sites)
    251566: "Pioneer Ford Campground",        # Camp Sherman (19 sites)

    # === OREGON COAST (~2-2.5 hrs) ===
    233110: "Tahkenitch Campground",          # Gardiner (24 sites)
    234578: "Lagoon Campground",              # Florence (37 sites)
    233111: "Tyee Campground - Oregon Dunes", # Westlake (15 sites)

    # === MOLALLA / FRENCH PRAIRIE (~45 min south) ===
    262754: "Three Bears Campground",         # Molalla (15 sites)
    262756: "Cedar Grove Campground",         # Molalla (10 sites)

    # === WILLAMETTE NF (Sweet Home area, ~90 min) ===
    274721: "Yellowbottom Recreation Site",   # Sweet Home (21 sites)
    273354: "Elkhorn Valley Recreation Site", # Lyons (23 sites)

    # === SOUTHERN CASCADES ===
    233186: "Hart-Tish Park at Applegate Lake", # Jacksonville (16 sites)
}

# Area/distance labels for display in the Type column
CAMPGROUND_AREAS = {
    122890: "Gorge (~45 min)",
    122940: "Gorge (~45 min)",
    234306: "Gorge (~45 min)",
    232831: "Mt Hood (~90 min)",
    232835: "Mt Hood (~90 min)",
    232837: "Mt Hood (~90 min)",
    232836: "Mt Hood (~90 min)",
    232838: "Mt Hood (~90 min)",
    232834: "Mt Hood (~90 min)",
    272096: "Mt Hood (~90 min)",
    234075: "Mt Hood (~75 min)",
    251434: "Mt Hood (~90 min)",
    232867: "Estacada (~75 min)",
    232866: "Estacada (~75 min)",
    232868: "Estacada (~75 min)",
    10208831: "Estacada (~75 min)",
    232865: "Estacada (~75 min)",
    251452: "Estacada (~75 min)",
    232870: "Estacada (~75 min)",
    232844: "Estacada (~75 min)",
    232854: "Estacada (~75 min)",
    232856: "Estacada (~75 min)",
    232863: "Estacada (~75 min)",
    232872: "Estacada (~75 min)",
    232848: "Maupin (~90 min)",
    232849: "Maupin (~90 min)",
    234720: "Maupin (~90 min)",
    233301: "Detroit (~2 hrs)",
    251713: "Detroit (~2 hrs)",
    251616: "Detroit (~2 hrs)",
    233693: "Detroit (~2 hrs)",
    233694: "Detroit (~2 hrs)",
    233258: "Detroit (~2 hrs)",
    255135: "Detroit (~2 hrs)",
    251470: "Detroit (~2 hrs)",
    267555: "Bend (~2.5 hrs)",
    251448: "Bend (~2.5 hrs)",
    233215: "Bend (~2.5 hrs)",
    266142: "Bend (~2.5 hrs)",
    267081: "Bend (~2.5 hrs)",
    251566: "Bend (~2.5 hrs)",
    233110: "Coast (~2.5 hrs)",
    234578: "Coast (~2.5 hrs)",
    233111: "Coast (~2.5 hrs)",
    262754: "Molalla (~45 min)",
    262756: "Molalla (~45 min)",
    274721: "Sweet Home (~90 min)",
    273354: "Sweet Home (~90 min)",
    233186: "Southern Cascades (~2 hrs)",
}


def api_get(url, timeout=30, max_retries=3):
    """Make a GET request with proper headers for Recreation.gov API.
    Retries on 429 (rate limit) with exponential backoff."""
    import time
    req = urllib.request.Request(url, headers={
        'accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': 'https://www.recreation.gov/',
        'User-Agent': 'Mozilla/5.0 (Hermes Campground Finder)'
    })
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < max_retries - 1:
                wait = (attempt + 1) * 3
                print(f"  Rate limited, retrying in {wait}s...", file=sys.stderr)
                time.sleep(wait)
                continue
            body = e.read().decode() if e.fp else ''
            print(f"HTTP Error {e.code}: {body[:200]}", file=sys.stderr)
            return {}
        except urllib.error.URLError as e:
            print(f"URL Error: {e.reason}", file=sys.stderr)
            return {}
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            return {}
    return {}


def get_campground_availability(campground_id, start_date, end_date):
    """Get site-level availability for a specific campground and date range."""
    import urllib.parse
    # API requires the first of the month; we filter client-side
    from datetime import datetime
    dt = datetime.strptime(start_date, '%Y-%m-%d')
    month_start = dt.replace(day=1).strftime('%Y-%m-%d')
    params = urllib.parse.urlencode({'start_date': f'{month_start}T00:00:00.000Z'})
    url = (f"https://www.recreation.gov/api/camps/availability/campground"
           f"/{campground_id}/month?{params}")

    data = api_get(url)
    if not data:
        return {'id': campground_id, 'error': 'API request failed', 'num_available': 0}

    campsites = data.get('campsites', {})
    available_sites = []

    # Only include tent-camping sites: exclude RV-only, equestrian, group/picnic/day-use
    TENT_TYPES = {'TENT ONLY NONELECTRIC', 'STANDARD NONELECTRIC'}

    for site_id, site_data in campsites.items():
        # Skip non-tent site types (RV, equestrian, group, picnic, day use)
        campsite_type = site_data.get('campsite_type', '')
        if campsite_type not in TENT_TYPES:
            continue

        site_num = site_data.get('site', '')
        avail = site_data.get('availabilities', {})

        available_nights = 0
        total_nights = 0

        for date_str, status in avail.items():
            date_only = date_str[:10]
            if start_date <= date_only <= end_date:
                total_nights += 1
                if status == 'Available':
                    available_nights += 1

        if available_nights > 0:
            available_sites.append({
                'site_id': site_id,
                'site_num': site_num,
                'campsite_type': campsite_type,
                'available_nights': available_nights,
                'total_nights_checked': total_nights,
            })

    return {
        'id': campground_id,
        'name': data.get('facility_name', ''),
        'available_sites': available_sites,
        'total_sites': len(campsites),
        'num_available': len(available_sites),
    }


def main():
    parser = argparse.ArgumentParser(description='Find available campgrounds near Beaverton, OR')
    parser.add_argument('--lat', type=float, default=BEAVERTON_LAT)
    parser.add_argument('--lon', type=float, default=BEAVERTON_LON)
    parser.add_argument('--radius', type=int, default=75, help='Search radius in miles (for search mode)')
    parser.add_argument('--start', required=True, help='Start date (YYYY-MM-DD)')
    parser.add_argument('--end', required=True, help='End date (YYYY-MM-DD)')
    parser.add_argument('--campground-id', type=int, help='Check specific campground ID')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--filter', type=str, help='Comma-separated list of campground names to filter')
    parser.add_argument('--top', type=int, default=10, help='Show top N results (default: 10)')
    args = parser.parse_args()

    # Validate dates
    try:
        start = datetime.strptime(args.start, '%Y-%m-%d')
        end = datetime.strptime(args.end, '%Y-%m-%d')
    except ValueError:
        print("Error: Dates must be in YYYY-MM-DD format", file=sys.stderr)
        sys.exit(1)

    if end <= start:
        print("Error: End date must be after start date", file=sys.stderr)
        sys.exit(1)

    if args.campground_id:
        # Check specific campground
        result = get_campground_availability(args.campground_id, args.start, args.end)
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            name = result.get('name', CAMPGROUND_IDS.get(args.campground_id, 'Unknown'))
            link = f"https://www.recreation.gov/camping/campgrounds/{args.campground_id}"
            print(f"\n{'='*60}")
            print(f"🏕️  [{name}]({link}) (ID: {args.campground_id})")
            print(f"   {args.start} to {args.end}")
            print(f"{'='*60}")
            if result.get('error'):
                print(f"  ❌ {result['error']}")
            elif result['num_available'] == 0:
                print(f"  ❌ No available sites out of {result['total_sites']} total")
            else:
                print(f"  ✅ {result['num_available']} site(s) available!\n")
                for site in result['available_sites'][:10]:
                    print(f"  Site {site['site_num']}: {site['available_nights']} nights available")
                if result['num_available'] > 10:
                    print(f"  ... and {result['num_available'] - 10} more")
            print()
    else:
        # Check all known campgrounds
        campgrounds = CAMPGROUND_IDS.copy()

        # Apply name filter if provided
        if args.filter:
            filter_terms = [f.strip().lower() for f in args.filter.split(',')]
            campgrounds = {
                cid: name for cid, name in campgrounds.items()
                if any(term in name.lower() for term in filter_terms)
            }
            print(f"Filtered to {len(campgrounds)} campgrounds matching: {args.filter}")

        print(f"Checking {len(campgrounds)} campgrounds for {args.start} to {args.end}...\n", file=sys.stderr)

        results = []
        for i, (cid, name) in enumerate(campgrounds.items()):
            avail = get_campground_availability(cid, args.start, args.end)
            avail['name'] = name
            results.append(avail)
            # Progress indicator
            if (i + 1) % 10 == 0:
                print(f"  ... checked {i+1}/{len(campgrounds)}", file=sys.stderr)
            # Rate limit: pause briefly between requests to avoid 429s
            import time
            time.sleep(0.5)

        # Sort by distance (closest first), then by availability within same area
        def sort_key(x):
            cid = x['id']
            area = CAMPGROUND_AREAS.get(cid, '')
            # Extract minutes from area label
            import re
            minutes = 9999
            m = re.search(r'(\d+) min', area)
            if m:
                minutes = int(m.group(1))
            elif 'hr' in area:
                m2 = re.search(r'(\d+)', area)
                if m2:
                    minutes = int(m2.group(1)) * 60
            # Primary: distance, Secondary: availability (descending)
            return (minutes, -x.get('num_available', 0))

        results.sort(key=sort_key)

        if args.json:
            print(json.dumps(results, indent=2))
        else:
            print(f"\n{'='*70}")
            print(f"🏕️  CAMPGROUND AVAILABILITY NEAR BEAVERTON, OR")
            print(f"    Dates: {args.start} to {args.end}")
            print(f"    Checked: {len(results)} campgrounds")
            print(f"{'='*70}\n")

            available = [r for r in results if r.get('num_available', 0) > 0]

            if not available:
                print("  No availability found.")
                print("  Tips:")
                print("  - Try different dates (mid-week is easier)")
                print("  - Some campgrounds are first-come, first-served (not on Recreation.gov)")
                print("  - Check Oregon state parks separately at oregonstateparks.org")
            else:
                print(f"  ✅ Found availability at {len(available)} campground(s):\n")

            # Output results as a markdown table
            print(f"{'='*70}")
            print(f"| Campground | Type | Available |")
            print(f"|---|---|---|")
            for r in available:
                name = r.get('name', 'Unknown')
                num = r.get('num_available', 0)
                total = r.get('total_sites', '?')
                link = f"https://www.recreation.gov/camping/campgrounds/{r['id']}"
                area = CAMPGROUND_AREAS.get(r['id'], '')
                print(f"| [{name}]({link}) | {area} | {num}/{total} |")
            print()


if __name__ == '__main__':
    main()
