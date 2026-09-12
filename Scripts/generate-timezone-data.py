#!/usr/bin/env python3
"""Generate the bundled offline timezone dataset for NumlexCore.

Reproducible and network-free at runtime: this script is the ONLY place that
talks to the network, and only when regenerating. It downloads the pinned
authoritative sources, verifies the recorded SHA-256 of each, filters to the
compact data the app ships, and writes deterministic TSV/JSON resources into
Sources/NumlexCore/Resources/NumlexTimezones/.

Sources (all legally redistributable):
  * IANA tzdata (public domain)          — canonical zone ids, aliases
  * GeoNames cities15000 (CC BY 4.0)     — cities with population >= 100k
  * airportsdata (MIT)                   — IATA/ICAO -> IANA tz

Usage:
    python3 Scripts/generate-timezone-data.py [--verify-only]

--verify-only re-downloads nothing: it hashes the COMMITTED resources and
compares them with resources/sources.json (the integrity check the tests use).
"""

import hashlib
import io
import json
import os
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Sources", "NumlexCore", "Resources", "NumlexTimezones")

# Pinned sources: URL, expected SHA-256, license, attribution.
SOURCES = {
    "zone1970.tab": (
        "https://data.iana.org/time-zones/data/zone1970.tab",
        "cf7a21adf7153794a684c03e499e882ee119f828ad77a579ed99db26ceeae87b",
        "Public domain (IANA tz database)",
        "IANA Time Zone Database (tzdata), https://www.iana.org/time-zones",
    ),
    "backward": (
        "https://data.iana.org/time-zones/data/backward",
        "b8296b9ef1ece72d813878132c0f17e2c52b26af6004eeb9c37d049b64cd9401",
        "Public domain (IANA tz database)",
        "IANA Time Zone Database (tzdata), https://www.iana.org/time-zones",
    ),
    "cities15000.zip": (
        "https://download.geonames.org/export/dump/cities15000.zip",
        "4f6fd2209a5660fed2989fccc8842947e3107ff595c14efc35ab281bba0ee467",
        "CC BY 4.0",
        "GeoNames, https://www.geonames.org (cities15000)",
    ),
    "airports.csv": (
        "https://raw.githubusercontent.com/mborsetti/airportsdata/main/airportsdata/airports.csv",
        "516c57d9d999f7a3be28ca649d2badbe3b972f07e57dc6173ab973b72d51cf52",
        "MIT",
        "airportsdata, https://github.com/mborsetti/airportsdata",
    ),
}
VERSION_URL = "https://data.iana.org/time-zones/data/version"
MIN_POPULATION = 100_000


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(url: str, expected: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    actual = sha256(data)
    if expected and actual != expected:
        raise SystemExit(f"hash mismatch for {url}\n  expected {expected}\n  actual   {actual}")
    return data


def load_sources() -> dict:
    cache = os.path.join(OUT, "sources.json")
    if os.path.exists(cache):
        with open(cache, encoding="utf-8") as handle:
            return json.load(handle)
    return {}


def canonical_and_aliases(zone1970: str, backward: str) -> tuple:
    """(canonical ids with country codes, alias -> canonical)."""
    canonical = {}
    for line in zone1970.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 3:
            continue
        countries, zone = fields[1], fields[2]
        canonical[zone] = countries
    aliases = {}
    for line in backward.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "Link":
            target, link = parts[1], parts[2]
            aliases[link] = target
    return canonical, aliases


def load_cities(blob: bytes, known: set) -> list:
    cities = []
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        name = [n for n in archive.namelist() if n.endswith(".txt")][0]
        with archive.open(name) as handle:
            for raw in io.TextIOWrapper(handle, encoding="utf-8"):
                fields = raw.rstrip("\n").split("\t")
                if len(fields) < 19:
                    continue
                population = int(fields[14] or 0)
                zone = fields[17]
                if population < MIN_POPULATION or zone not in known:
                    continue
                cities.append((fields[1], fields[2], fields[8], population, zone,
                               fields[7]))
    cities.sort(key=lambda c: (-c[3], c[0], c[1]))
    return cities


def load_airports(text: str, known: set) -> list:
    import csv as csvmod
    rows = []
    for row in csvmod.DictReader(io.StringIO(text)):
        zone = (row.get("tz") or "").strip()
        iata = (row.get("iata") or "").strip().upper()
        icao = (row.get("icao") or "").strip().upper()
        if not zone or zone not in known or (not iata and not icao):
            continue
        rows.append((iata, icao, zone))
    rows.sort()
    return rows


def capitals(cities: list) -> list:
    """country -> capital zone, from the GeoNames capital feature (PPLC)."""
    seen = {}
    for name, ascii_name, country, population, zone, feature in cities:
        _ = (name, ascii_name, population)
        if feature == "PPLC" and country not in seen:
            seen[country] = zone
    return sorted(seen.items())


def write(path: str, text: str) -> str:
    data = text.encode("utf-8")
    with open(path, "wb") as handle:
        handle.write(data)
    return sha256(data)


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    verify_only = "--verify-only" in sys.argv
    if verify_only:
        sources = load_sources()
        if not sources:
            raise SystemExit("no sources.json to verify against")
        bad = []
        for name, meta in sources["resources"].items():
            with open(os.path.join(OUT, name), "rb") as handle:
                if sha256(handle.read()) != meta["sha256"]:
                    bad.append(name)
        if bad:
            raise SystemExit("integrity failure: " + ", ".join(bad))
        print("verify-only: OK", sources["resources"].keys())
        return 0

    fetched = {}
    for name, (url, expected, _license, _attribution) in SOURCES.items():
        print(f"fetching {url}")
        fetched[name] = fetch(url, expected)
    try:
        version = fetch(VERSION_URL, "").decode("utf-8").strip()
    except Exception as error:  # noqa: BLE001 - the version is informational
        version = f"unknown ({error})"

    canonical, aliases = canonical_and_aliases(
        fetched["zone1970.tab"].decode("utf-8"), fetched["backward"].decode("utf-8"))
    # Foundation knows every canonical id the OS ships; ids that are neither
    # canonical nor aliases (Etc/*) are treated as canonical too.
    known = set(canonical) | set(aliases)
    cities = load_cities(fetched["cities15000.zip"], known)
    airports = load_airports(fetched["airports.csv"].decode("utf-8"), known)

    zones_lines = []
    for zone in sorted(canonical):
        zone_aliases = sorted(k for k, v in aliases.items() if v == zone)
        zones_lines.append(f"{zone}\t{canonical[zone]}\t{','.join(zone_aliases)}")
    cities_lines = [f"{name}\t{ascii_name}\t{country}\t{population}\t{zone}"
                    for name, ascii_name, country, population, zone, _f in cities]
    country_lines = [f"{cc}\t{zone}" for cc, zone in capitals(cities)]
    airport_lines = [f"{iata}\t{icao}\t{zone}" for iata, icao, zone in airports]

    resources = {
        "iana-zones.tsv": write(os.path.join(OUT, "iana-zones.tsv"),
                                "\n".join(zones_lines) + "\n"),
        "cities.tsv": write(os.path.join(OUT, "cities.tsv"),
                            "\n".join(cities_lines) + "\n"),
        "countries.tsv": write(os.path.join(OUT, "countries.tsv"),
                               "\n".join(country_lines) + "\n"),
        "airports.tsv": write(os.path.join(OUT, "airports.tsv"),
                              "\n".join(airport_lines) + "\n"),
    }
    meta = {
        "generator": "Scripts/generate-timezone-data.py",
        "ianaVersion": version,
        "minPopulation": MIN_POPULATION,
        "sources": {
            name: {
                "url": url,
                "sha256": sha256(fetched[name]),
                "license": license_,
                "attribution": attribution,
            }
            for name, (url, _expected, license_, attribution) in SOURCES.items()
        },
        "resources": {name: {"sha256": digest} for name, digest in resources.items()},
        "counts": {
            "zones": len(zones_lines),
            "aliases": len(aliases),
            "cities": len(cities_lines),
            "countries": len(country_lines),
            "airports": len(airport_lines),
        },
    }
    with open(os.path.join(OUT, "sources.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("wrote", json.dumps(meta["counts"], sort_keys=True), "tzdata", version)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
