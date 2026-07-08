#!/usr/bin/env python3
"""
Short-term rental search fallback for when `web_search` is unavailable.
Curls Airbnb and VRBO search pages and extracts property listings.

WARNING: Platforms actively block scraping. This is a best-effort fallback.
For reliable results, enable the `web` toolset so `web_search` is available.

Usage:
    python3 rental_search.py --location "Bend, OR" --checkin 2026-07-03 --checkout 2026-07-06 --bedrooms 2
    python3 rental_search.py --location "Bend, OR" --checkin 2026-07-03 --checkout 2026-07-06 --bedrooms 2 --hot-tub --json
"""

import argparse
import json
import re
import sys
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime


def curl(url, timeout=15):
    """Make a GET request with browser-like headers to avoid basic bot detection."""
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode('utf-8', errors='replace')
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code} for {url[:80]}...", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  Error fetching {url[:80]}...: {e}", file=sys.stderr)
        return None


def build_airbnb_url(location, checkin, checkout, bedrooms, adults=4):
    """Build an Airbnb search URL with filters applied."""
    params = urllib.parse.urlencode({
        'checkin': checkin,
        'checkout': checkout,
        'adults': adults,
        'min_bedrooms': bedrooms,
        'location': location,
    })
    return f"https://www.airbnb.com/s/{urllib.parse.quote(location)}/homes?{params}"


def build_vrbo_url(location, checkin, checkout, bedrooms, adults=4):
    """Build a VRBO search URL with filters applied."""
    params = urllib.parse.urlencode({
        'adults': adults,
        'bedrooms': bedrooms,
        'location': location,
        'startDate': checkin,
        'endDate': checkout,
    })
    return f"https://www.vrbo.com/search?{params}"


def extract_listings_airbnb(html):
    """Extract property data from Airbnb search results page HTML."""
    if not html:
        return []

    listings = []

    # Try to find JSON data embedded in the page (Airbnb uses Next.js data)
    json_match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html, re.DOTALL)
    if json_match:
        try:
            data = json.loads(json_match.group(1))
            # Navigate the nested structure to find listings
            explore_sections = (
                data.get('props', {})
                .get('pageProps', {})
                .get('exploreData', {})
                .get('sections', [])
            )
            for section in explore_sections:
                items = section.get('items', [])
                for item in items:
                    listing = item.get('listing', {})
                    if not listing:
                        continue
                    name = listing.get('name', '')
                    listing_id = listing.get('id', '')
                    bedrooms = listing.get('bedrooms', 0)
                    beds = listing.get('beds', 0)
                    person_capacity = listing.get('person_capacity', 0)
                    avg_rating = listing.get('avg_rating', 0)
                    price_data = listing.get('price_data', {})
                    price = price_data.get('amount', 0)
                    currency = price_data.get('currency', 'USD')

                    # Check for hot tub in amenities
                    amenities = listing.get('amenities', [])
                    has_hot_tub = any(
                        'hot tub' in str(a.get('name', '')).lower() or
                        'jacuzzi' in str(a.get('name', '')).lower()
                        for a in amenities
                    )

                    if name and listing_id:
                        listings.append({
                            'name': name,
                            'url': f"https://www.airbnb.com/rooms/{listing_id}",
                            'bedrooms': bedrooms,
                            'beds': beds,
                            'sleeps': person_capacity,
                            'rating': avg_rating,
                            'price': price,
                            'currency': currency,
                            'has_hot_tub': has_hot_tub,
                            'platform': 'Airbnb',
                        })
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print(f"  Failed to parse Airbnb JSON: {e}", file=sys.stderr)

    # Fallback: regex-based extraction from HTML
    if not listings:
        # Look for property links and names
        property_pattern = r'aria-label="([^"]+)"[^>]*href="/rooms/(\d+)"'
        for match in re.finditer(property_pattern, html):
            name = match.group(1)
            listing_id = match.group(2)
            if name and listing_id:
                listings.append({
                    'name': name,
                    'url': f"https://www.airbnb.com/rooms/{listing_id}",
                    'bedrooms': 0,
                    'beds': 0,
                    'sleeps': 0,
                    'rating': 0,
                    'price': 0,
                    'currency': 'USD',
                    'has_hot_tub': False,
                    'platform': 'Airbnb',
                })

    return listings


def extract_listings_vrbo(html):
    """Extract property data from VRBO search results page HTML."""
    if not html:
        return []

    listings = []

    # Try to find JSON/embedded data
    json_match = re.search(r'window\.__INITIAL_STATE__\s*=\s*({.*?});\s*</script>', html, re.DOTALL)
    if json_match:
        try:
            data = json.loads(json_match.group(1))
            results = data.get('search', {}).get('results', [])
            for r in results:
                listing = r.get('listing', r)
                name = listing.get('name', '')
                listing_id = listing.get('id', listing.get('listingId', ''))
                bedrooms = listing.get('bedrooms', 0)
                max_sleep_capacity = listing.get('maxSleepCapacity', 0)
                average_rating = listing.get('averageRating', 0)
                price_per_night = listing.get('pricePerNight', {}).get('amount', 0)
                has_hot_tub = 'hot tub' in str(listing.get('amenities', [])).lower()

                if name and listing_id:
                    listings.append({
                        'name': name,
                        'url': f"https://www.vrbo.com/{listing_id}",
                        'bedrooms': bedrooms,
                        'beds': 0,
                        'sleeps': max_sleep_capacity,
                        'rating': average_rating,
                        'price': price_per_night,
                        'currency': 'USD',
                        'has_hot_tub': has_hot_tub,
                        'platform': 'VRBO',
                    })
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print(f"  Failed to parse VRBO JSON: {e}", file=sys.stderr)

    # Fallback: look for property links
    if not listings:
        property_pattern = r'href="/(\d+)"[^>]*aria-label="([^"]+)"'
        for match in re.finditer(property_pattern, html):
            listing_id = match.group(1)
            name = match.group(2)
            if name and listing_id and len(name) > 5:
                listings.append({
                    'name': name,
                    'url': f"https://www.vrbo.com/{listing_id}",
                    'bedrooms': 0,
                    'beds': 0,
                    'sleeps': 0,
                    'rating': 0,
                    'price': 0,
                    'currency': 'USD',
                    'has_hot_tub': False,
                    'platform': 'VRBO',
                })

    return listings


def main():
    parser = argparse.ArgumentParser(description='Search for short-term rental properties')
    parser.add_argument('--location', required=True, help='Location (e.g. "Bend, OR")')
    parser.add_argument('--checkin', required=True, help='Check-in date (YYYY-MM-DD)')
    parser.add_argument('--checkout', required=True, help='Check-out date (YYYY-MM-DD)')
    parser.add_argument('--bedrooms', type=int, default=2, help='Minimum bedrooms (default: 2)')
    parser.add_argument('--adults', type=int, default=4, help='Number of adults (default: 4)')
    parser.add_argument('--hot-tub', action='store_true', help='Prioritize hot tub properties')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--top', type=int, default=10, help='Max results to return (default: 10)')
    args = parser.parse_args()

    print(f"Searching for rentals in {args.location}...", file=sys.stderr)
    print(f"  Dates: {args.checkin} to {args.checkout}", file=sys.stderr)
    print(f"  Min bedrooms: {args.bedrooms}", file=sys.stderr)
    print(f"  Adults: {args.adults}", file=sys.stderr)
    if args.hot_tub:
        print(f"  Prioritizing hot tub properties", file=sys.stderr)
    print()

    all_listings = []

    # Search Airbnb
    airbnb_url = build_airbnb_url(args.location, args.checkin, args.checkout, args.bedrooms, args.adults)
    print(f"Fetching Airbnb results...", file=sys.stderr)
    airbnb_html = curl(airbnb_url)
    if airbnb_html:
        airbnb_listings = extract_listings_airbnb(airbnb_html)
        print(f"  Found {len(airbnb_listings)} Airbnb listings", file=sys.stderr)
        all_listings.extend(airbnb_listings)
    else:
        print(f"  Airbnb request failed (likely bot detection)", file=sys.stderr)

    # Search VRBO
    vrbo_url = build_vrbo_url(args.location, args.checkin, args.checkout, args.bedrooms, args.adults)
    print(f"Fetching VRBO results...", file=sys.stderr)
    vrbo_html = curl(vrbo_url)
    if vrbo_html:
        vrbo_listings = extract_listings_vrbo(vrbo_html)
        print(f"  Found {len(vrbo_listings)} VRBO listings", file=sys.stderr)
        all_listings.extend(vrbo_listings)
    else:
        print(f"  VRBO request failed (likely bot detection)", file=sys.stderr)

    # Filter by minimum bedrooms
    filtered = [l for l in all_listings if l.get('bedrooms', 0) >= args.bedrooms or l.get('bedrooms', 0) == 0]
    if args.hot_tub:
        # Sort: hot tub first, then by rating
        filtered.sort(key=lambda x: (not x.get('has_hot_tub', False), -(x.get('rating', 0) or 0)))
    else:
        filtered.sort(key=lambda x: -(x.get('rating', 0) or 0))

    # Cap results
    filtered = filtered[:args.top]

    if args.json:
        print(json.dumps(filtered, indent=2))
    else:
        if not filtered:
            print("No listings found.")
            print("This likely means the platforms blocked the scraping attempt.")
            print("Enable the `web` toolset for reliable search results.")
        else:
            print(f"\n{'='*70}")
            print(f"🏠  RENTAL LISTINGS: {args.location}")
            print(f"    Dates: {args.checkin} to {args.checkout}")
            print(f"    Min Bedrooms: {args.bedrooms}")
            print(f"    Found: {len(filtered)} properties")
            print(f"{'='*70}\n")

            print(f"| # | Property | Bedrooms | Sleeps | Price/Night | Hot Tub | Platform |")
            print(f"|---|----------|----------|--------|-------------|---------|----------|")
            for i, l in enumerate(filtered, 1):
                name = l.get('name', 'Unknown')[:40]
                url = l.get('url', '#')
                beds = l.get('bedrooms', '?')
                sleeps = l.get('sleeps', '?')
                price = l.get('price', 0)
                currency = l.get('currency', 'USD')
                price_str = f"${price:.0f}" if price else "N/A"
                hot_tub = "✅ Yes" if l.get('has_hot_tub') else "❌ No"
                platform = l.get('platform', 'Unknown')
                print(f"| {i} | [{name}]({url}) | {beds} | {sleeps} | {price_str} | {hot_tub} | {platform} |")
            print()


if __name__ == '__main__':
    main()
