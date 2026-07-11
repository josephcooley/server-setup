#!/usr/bin/env python3
"""
Flight price tracker: PDX → ANC round trip, 5-day stay (±1 day flexibility).
Alaska Airlines direct flights only. Finds cheapest departure window.
"""

import os
import re
import sys
import json
import time
import random
import tempfile
import sqlite3
import logging
import requests
from datetime import datetime, timedelta, timezone
from pathlib import Path

# ── Configuration ──────────────────────────────────────────────────────────────

ORIGIN = "PDX"
DESTINATION = "ANC"
AIRLINE = "Alaska"
TRIP_DAYS = 5
FLEXIBILITY = 1  # ±1 day if cheaper
MAX_PRICE_THRESHOLD = int(os.environ.get("MAX_PRICE", "500"))
CHECK_WINDOW_DAYS = 90  # Look 90 days ahead
REQUEST_TIMEOUT_SECONDS = 20
REQUEST_RETRY_ATTEMPTS = 3
REQUEST_BACKOFF_BASE_SECONDS = 1.0
REQUEST_JITTER_SECONDS = 0.35
INTER_REQUEST_DELAY_SECONDS = 0.6
LOCK_STALE_AFTER_SECONDS = 2 * 60 * 60

DB_DIR = Path(__file__).parent
DB_PATH = DB_DIR / "flight_prices.db"
LOG_PATH = DB_DIR / "tracker.log"
LOCK_PATH = DB_DIR / ".flight_tracker.lock"

# Direct flights PDX ↔ ANC on Alaska Airlines
DIRECT_FLIGHTS = [
    {"flight": "AS2111", "direction": "outbound", "from": "PDX", "to": "ANC", "depart": "07:00", "arrive": "11:45", "duration_min": 225},
    {"flight": "AS2231", "direction": "outbound", "from": "PDX", "to": "ANC", "depart": "17:45", "arrive": "22:35", "duration_min": 230},
    {"flight": "AS2232", "direction": "return",  "from": "ANC", "to": "PDX", "depart": "12:30", "arrive": "17:20", "duration_min": 230},
    {"flight": "AS2112", "direction": "return",  "from": "ANC", "to": "PDX", "depart": "06:15", "arrive": "11:05", "duration_min": 230},
]

# ── Logging ────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_PATH),
    ],
)
log = logging.getLogger("flight-tracker")

# ── Database ───────────────────────────────────────────────────────────────────

def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS trip_prices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            origin TEXT NOT NULL,
            destination TEXT NOT NULL,
            airline TEXT,
            departure_date TEXT,
            return_date TEXT,
            trip_days INTEGER,
            outbound_flight TEXT,
            return_flight TEXT,
            price INTEGER,
            currency TEXT DEFAULT 'USD',
            notes TEXT
        );
        CREATE TABLE IF NOT EXISTS browse_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            search_date TEXT,
            route TEXT,
            departure_date TEXT,
            return_date TEXT,
            trip_days INTEGER,
            price INTEGER,
            stops TEXT,
            airline TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_trip_depart ON trip_prices(departure_date);
        CREATE INDEX IF NOT EXISTS idx_browse_route ON browse_results(route);
    """)
    conn.commit()
    return conn

def save_trip_price(conn, dep_date, ret_date, trip_days, price, outbound="", return_flight="", notes=""):
    conn.execute(
        """INSERT INTO trip_prices (timestamp, origin, destination, airline, departure_date, return_date, trip_days, outbound_flight, return_flight, price, notes)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (datetime.now(timezone.utc).isoformat(), ORIGIN, DESTINATION, AIRLINE,
         dep_date, ret_date, trip_days, outbound, return_flight, price, notes)
    )
    conn.commit()

def save_browse_result(conn, dep_date, ret_date, trip_days, price):
    conn.execute(
        """INSERT INTO browse_results (timestamp, search_date, route, departure_date, return_date, trip_days, price, stops, airline)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (datetime.now(timezone.utc).isoformat(), datetime.now(timezone.utc).strftime("%Y-%m-%d"),
         f"{ORIGIN}→{DESTINATION}→{ORIGIN}", dep_date, ret_date, trip_days, price, "nonstop", AIRLINE)
    )
    conn.commit()

def get_latest_trip_price(conn):
    return conn.execute(
        "SELECT price, departure_date, return_date, trip_days, timestamp FROM trip_prices ORDER BY timestamp DESC LIMIT 1"
    ).fetchone()

def get_lowest_ever(conn):
    row = conn.execute("SELECT MIN(price), departure_date, return_date FROM trip_prices").fetchone()
    return row[0] if row else None

def get_trip_history(conn, days=90):
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    return conn.execute(
        """SELECT timestamp, departure_date, return_date, trip_days, price, outbound_flight, return_flight
           FROM trip_prices WHERE timestamp > ? ORDER BY timestamp ASC""",
        (cutoff,)
    ).fetchall()

def get_browse_history(conn, days=90):
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    return conn.execute(
        """SELECT timestamp, departure_date, return_date, trip_days, price, route
           FROM browse_results WHERE timestamp > ? ORDER BY timestamp ASC""",
        (cutoff,)
    ).fetchall()

def get_best_trip_per_date(conn):
    """Get the best (cheapest) trip for each departure date."""
    return conn.execute("""
        SELECT departure_date, return_date, trip_days, price, outbound_flight, return_flight, timestamp
        FROM trip_prices tp
        WHERE id = (
            SELECT id
            FROM trip_prices t2
            WHERE t2.departure_date = tp.departure_date
            ORDER BY t2.price ASC, t2.timestamp DESC
            LIMIT 1
        )
        ORDER BY departure_date
    """).fetchall()


def atomic_write_text(path: Path, text: str, encoding: str = "utf-8"):
    """Write a file atomically to avoid partial JSON on interruption/concurrency."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False, encoding=encoding) as tmp:
        tmp.write(text)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp_path = Path(tmp.name)
    tmp_path.replace(path)


def acquire_lock(lock_path: Path):
    """Acquire a single-instance lock file; returns fd or None if already running."""
    now = time.time()

    if lock_path.exists():
        age = now - lock_path.stat().st_mtime
        if age > LOCK_STALE_AFTER_SECONDS:
            log.warning("Removing stale lock file: %s", lock_path)
            try:
                lock_path.unlink()
            except OSError:
                pass

    try:
        fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.write(fd, str(os.getpid()).encode("utf-8"))
        return fd
    except FileExistsError:
        return None


def release_lock(fd, lock_path: Path):
    try:
        os.close(fd)
    finally:
        try:
            lock_path.unlink()
        except OSError:
            pass

# ── Scraping ───────────────────────────────────────────────────────────────────

def make_session():
    s = requests.Session()
    s.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.5",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    })
    return s

def _retry_sleep(attempt: int):
    delay = REQUEST_BACKOFF_BASE_SECONDS * (2 ** (attempt - 1))
    delay += random.uniform(0, REQUEST_JITTER_SECONDS)
    time.sleep(delay)


def scrape_google_flights_roundtrip(session, origin, destination, dep_date, ret_date):
    """Scrape Google Flights for a specific round-trip date range."""
    url = (f"https://www.google.com/travel/flights?q=Flights%20from%20{origin}%20to%20{destination}"
           f"%20departing%20{dep_date}%20returning%20{ret_date}%20nonstop%20Alaska%20Airlines&curr=USD")

    log.info(f"Fetching: {origin}→{destination} dep={dep_date} ret={ret_date}")

    for attempt in range(1, REQUEST_RETRY_ATTEMPTS + 1):
        try:
            resp = session.get(url, timeout=REQUEST_TIMEOUT_SECONDS)
            resp.raise_for_status()
        except requests.RequestException as e:
            log.warning("Request failed (attempt %s/%s): %s", attempt, REQUEST_RETRY_ATTEMPTS, e)
            if attempt < REQUEST_RETRY_ATTEMPTS:
                _retry_sleep(attempt)
                continue
            return None

        html = resp.text

        if "consent.google" in resp.url:
            log.error("Blocked by Google consent page")
            return None

        # Extract prices from aria-labels
        prices_raw = re.findall(r'aria-label="(\d+)\s+US\s+dollars"', html)
        prices = sorted(set(int(p) for p in prices_raw))

        if prices:
            return {"lowest": min(prices), "all_prices": prices}

        log.warning("No prices found (attempt %s/%s)", attempt, REQUEST_RETRY_ATTEMPTS)
        if attempt < REQUEST_RETRY_ATTEMPTS:
            _retry_sleep(attempt)

    return None


def browse_flexible_trip(conn):
    """
    Browse for the best 5-day trip with ±1 day flexibility.
    For each base departure date, check dep-1, dep, dep+1 with corresponding returns.
    Find the cheapest combo.
    """
    session = make_session()
    today = datetime.now(timezone.utc).date()
    best_overall = None
    all_results = []
    windows_attempted = 0

    # Search every 5 days across the window
    search_points = range(7, CHECK_WINDOW_DAYS, 5)

    for day_offset in search_points:
        base_dep = today + timedelta(days=day_offset)

        # Try ±1 day on departure, keeping ~5 day trip length
        flex_windows = []
        for dep_delta in range(-FLEXIBILITY, FLEXIBILITY + 1):
            dep_date = base_dep + timedelta(days=dep_delta)
            ret_date = dep_date + timedelta(days=TRIP_DAYS)
            flex_windows.append((dep_date.strftime("%Y-%m-%d"), ret_date.strftime("%Y-%m-%d"), TRIP_DAYS))

            # Also try 4-day and 6-day variants
            for td in [TRIP_DAYS - 1, TRIP_DAYS + 1]:
                ret_date_alt = dep_date + timedelta(days=td)
                flex_windows.append((dep_date.strftime("%Y-%m-%d"), ret_date_alt.strftime("%Y-%m-%d"), td))

        for dep_str, ret_str, td in flex_windows:
            windows_attempted += 1
            result = scrape_google_flights_roundtrip(session, ORIGIN, DESTINATION, dep_str, ret_str)

            if result:
                entry = {
                    "departure_date": dep_str,
                    "return_date": ret_str,
                    "trip_days": td,
                    "price": result["lowest"],
                    "all_prices": result["all_prices"],
                }
                all_results.append(entry)
                save_browse_result(conn, dep_str, ret_str, td, result["lowest"])

                if best_overall is None or result["lowest"] < best_overall["price"]:
                    best_overall = entry
                    log.info(f"  ★ New best: depart={dep_str} ret={ret_str} {td}days ${result['lowest']}")

            # Rate limiting
                time.sleep(INTER_REQUEST_DELAY_SECONDS)

            return best_overall, all_results, windows_attempted

# ── Main ───────────────────────────────────────────────────────────────────────

def run():
    log.info("=" * 60)
    log.info(f"Trip Tracker: {ORIGIN} → {DESTINATION} → {ORIGIN}")
    log.info(f"Stay: {TRIP_DAYS} days (±{FLEXIBILITY} day flexibility) | Target: ${MAX_PRICE_THRESHOLD}")
    log.info("=" * 60)

    lock_fd = acquire_lock(LOCK_PATH)
    if lock_fd is None:
        msg = {
            "error": "Flight tracker is already running",
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        }
        print(json.dumps(msg))
        return

    try:
        conn = init_db()
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

        # 1. Browse flexible trip options
        best_trip, all_results, windows_attempted = browse_flexible_trip(conn)

        if not best_trip:
            print(json.dumps({
                "error": "No trip data found",
                "timestamp": timestamp,
                "windows_attempted": windows_attempted,
            }))
            conn.close()
            return

        # 2. Save the best trip found
        save_trip_price(
            conn,
            best_trip["departure_date"],
            best_trip["return_date"],
            best_trip["trip_days"],
            best_trip["price"],
            notes=f"Best of {windows_attempted} flexible windows searched"
        )

        # 3. Get previous best for comparison
        prev = get_latest_trip_price(conn)
        prev_price = None
        if prev:
            # Get second-to-last (since we just saved the new one)
            prev2 = conn.execute(
                "SELECT price FROM trip_prices ORDER BY timestamp DESC LIMIT 1 OFFSET 1"
            ).fetchone()
            prev_price = prev2[0] if prev2 else prev[0]

        # 4. Build report
        report = build_report(conn, timestamp, best_trip, all_results, prev_price, windows_attempted)

        conn.close()

        # Save JSON for dashboard atomically
        json_path = DB_DIR / "data.json"
        atomic_write_text(json_path, json.dumps(report, indent=2))
        log.info(f"Dashboard data saved to {json_path}")

        print(json.dumps(report, indent=2))
    finally:
        release_lock(lock_fd, LOCK_PATH)


def build_report(conn, timestamp, best_trip, all_results, prev_price, windows_attempted):
    price = best_trip["price"]
    report = {
        "timestamp": timestamp,
        "trip_type": "round_trip",
        "route": f"{ORIGIN}→{DESTINATION}→{ORIGIN}",
        "airline": AIRLINE,
        "stops": "nonstop/direct",
        "target_price": MAX_PRICE_THRESHOLD,
        "flexibility_days": FLEXIBILITY,
        "trip_days": best_trip["trip_days"],
        "best_trip": {
            "departure_date": best_trip["departure_date"],
            "return_date": best_trip["return_date"],
            "trip_days": best_trip["trip_days"],
            "price": price,
        },
        "all_prices_found": sorted(set(r["price"] for r in all_results)),
        "total_windows_searched": windows_attempted,
        "successful_windows": len(all_results),
        "direct_flights": DIRECT_FLIGHTS,
    }

    # Price change
    if prev_price is not None:
        diff = price - prev_price
        if diff < 0:
            report["price_change"] = f"DOWN ${abs(diff):,} from ${prev_price:,}"
            report["alert"] = True
        elif diff > 0:
            report["price_change"] = f"UP ${diff:,} from ${prev_price:,}"
            report["alert"] = False
        else:
            report["price_change"] = "Unchanged"
            report["alert"] = False
    else:
        report["price_change"] = "First recording"
    report["previous_price"] = prev_price

    # Threshold
    report["threshold_met"] = price <= MAX_PRICE_THRESHOLD
    report["alert"] = report.get("alert", False) or report["threshold_met"]

    # Historical
    lowest = get_lowest_ever(conn)
    trip_history = get_trip_history(conn, days=90)
    browse_history = get_browse_history(conn, days=90)
    best_per_date = get_best_trip_per_date(conn)

    report["lowest_ever"] = lowest
    report["total_recordings"] = len(trip_history)
    report["trip_history"] = [
        {"date": r[0], "departure": r[1], "return": r[2], "days": r[3], "price": r[4],
         "outbound": r[5], "return_flight": r[6]}
        for r in trip_history
    ]
    report["browse_history"] = [
        {"date": r[0], "departure": r[1], "return": r[2], "days": r[3], "price": r[4]}
        for r in browse_history
    ]
    report["best_trips_by_date"] = [
        {"departure": r[0], "return": r[1], "days": r[2], "price": r[3],
         "outbound": r[4], "return_flight": r[5]}
        for r in best_per_date
    ]

    return report


if __name__ == "__main__":
    run()
