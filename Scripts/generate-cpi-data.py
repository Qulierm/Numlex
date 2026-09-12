#!/usr/bin/env python3
"""Reproducible generator for Numlex's bundled BLS CPI-U series.

Fetches the official BLS series `CUUR0000SA0` (CPI-U, U.S. city average,
all items, 1982-84=100) in 10-year windows from the public BLS API, then
writes:

  Sources/NumlexCore/Resources/NumlexCPI/cpi-u.json
  Sources/NumlexCore/Resources/NumlexCPI/sources.json

Annual averages cover 1913 through the latest COMPLETE year (2025). A
2026 entry is included ONLY as a provisional YTD average of the official
monthly observations (the manifest records the included months, the
latest observation and the snapshot date) — no 2026 annual average is
fabricated. The loader verifies the recorded SHA-256; runtime is fully
offline. BLS data is a U.S. Government work (public domain).
"""

import hashlib
import json
import os
import sys
import time
import urllib.request

VERSION = "cpi-u-2026.1"
SNAPSHOT = "2026-09-12"
SERIES = "CUUR0000SA0"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sources", "NumlexCore", "Resources", "NumlexCPI")
API = "https://api.bls.gov/publicAPI/v2/timeseries/data/"


CACHE_DIR = None


def fetch(start, end):
    # An explicit cache directory (--cache-dir, or NUMLEX_BLS_CACHE) lets
    # a rate-limited environment regenerate from previously fetched raw
    # API responses; the committed dataset remains the source of truth.
    if CACHE_DIR:
        cached = os.path.join(CACHE_DIR, f"bls_{start}.json")
        if os.path.exists(cached):
            with open(cached, "r", encoding="utf-8") as fh:
                payload = json.load(fh)
            if payload.get("status") == "REQUEST_SUCCEEDED":
                return payload["Results"]["series"][0]["data"]
    body = json.dumps({
        "seriesid": [SERIES],
        "startyear": str(start),
        "endyear": str(end),
        "annualaverage": True,
    }).encode("utf-8")
    request = urllib.request.Request(
        API, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if payload.get("status") != "REQUEST_SUCCEEDED":
        raise SystemExit(f"BLS request failed for {start}-{end}: {payload}")
    return payload["Results"]["series"][0]["data"]


def main():
    global CACHE_DIR
    if len(sys.argv) > 2 and sys.argv[1] == "--cache-dir":
        CACHE_DIR = sys.argv[2]
    elif os.environ.get("NUMLEX_BLS_CACHE"):
        CACHE_DIR = os.environ["NUMLEX_BLS_CACHE"]
    os.makedirs(OUT_DIR, exist_ok=True)
    annual = {}
    monthly_2026 = {}
    windows = [(y, min(y + 9, 2026)) for y in list(range(1913, 2013, 10)) + [2020]]
    for start, end in windows:
        for item in fetch(start, end):
            if item["value"] in ("-", "", None):
                continue
            year = int(item["year"])
            value = float(item["value"])
            if item["period"] == "M13":
                annual[year] = round(value, 3)
            elif year == 2026 and item["period"].startswith("M"):
                monthly_2026[int(item["period"][1:])] = round(value, 3)
        time.sleep(0.5)

    latest_annual_year = max(annual)
    provisional = None
    if monthly_2026:
        months = sorted(monthly_2026)
        ytd = round(sum(monthly_2026[m] for m in months) / len(months), 3)
        latest_month = months[-1]
        provisional = {
            "year": 2026,
            "months": months,
            "monthly": {str(m): monthly_2026[m] for m in months},
            "ytdAverage": ytd,
            "latestMonth": latest_month,
            "latestValue": monthly_2026[latest_month],
            "method": ("Provisional YTD average of the official BLS monthly "
                       "observations; NOT a BLS annual average."),
        }
        latest_year = 2026
        latest_index = ytd
    else:
        latest_year = latest_annual_year
        latest_index = annual[latest_annual_year]

    payload = {
        "version": VERSION,
        "snapshotDate": SNAPSHOT,
        "series": SERIES,
        "seriesTitle": ("Consumer Price Index for All Urban Consumers (CPI-U): "
                        "U.S. city average, all items"),
        "basePeriod": "1982-84=100",
        "seasonalAdjustment": "Not seasonally adjusted",
        "source": {
            "title": "U.S. Bureau of Labor Statistics — CPI-U (CUUR0000SA0)",
            "url": "https://www.bls.gov/cpi/",
            "api": API,
        },
        "license": "Public domain (U.S. Government work)",
        "annual": {str(y): annual[y] for y in sorted(annual)},
        "provisional": provisional,
        "latestAnnualYear": latest_annual_year,
        "latestSnapshotYear": latest_year,
        "latestSnapshotIndex": latest_index,
    }
    data = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    with open(os.path.join(OUT_DIR, "cpi-u.json"), "wb") as fh:
        fh.write(data)
    digest = hashlib.sha256(data).hexdigest()
    manifest = {
        "version": VERSION,
        "snapshotDate": SNAPSHOT,
        "series": SERIES,
        "annualCoverage": [min(annual), latest_annual_year],
        "provisional": (None if provisional is None else {
            "year": provisional["year"],
            "months": provisional["months"],
            "latestMonth": provisional["latestMonth"],
            "latestValue": provisional["latestValue"],
            "ytdAverage": provisional["ytdAverage"],
        }),
        "attribution": "U.S. Bureau of Labor Statistics, CPI-U All Items (public domain)",
        "license": "Public domain (U.S. Government work)",
        "generator": "Scripts/generate-cpi-data.py",
        "resources": {"cpi-u.json": {"sha256": digest}},
    }
    with open(os.path.join(OUT_DIR, "sources.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print(f"wrote {len(annual)} annual averages "
          f"({min(annual)}-{latest_annual_year}); provisional 2026 YTD "
          f"{provisional['ytdAverage'] if provisional else 'none'}; "
          f"sha256={digest}")


if __name__ == "__main__":
    main()
