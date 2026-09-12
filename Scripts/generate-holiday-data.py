#!/usr/bin/env python3
"""Reproducible generator for Numlex's bundled public-holiday profiles.

Computes the NATIONAL public holidays for a fixed set of countries and a
fixed year range from deterministic rule tables (fixed dates, nth-weekday
rules and Gregorian Easter offsets), then writes:

  Sources/NumlexCore/Resources/NumlexHolidays/holidays.tsv
  Sources/NumlexCore/Resources/NumlexHolidays/sources.json

The output is byte-stable for a given version: rerunning the script on any
machine produces the same files, and the loader verifies the recorded
SHA-256 of holidays.tsv. No network access, no locale dependence.
"""

import hashlib
import json
import os
from datetime import date, timedelta

VERSION = "2026.1"
YEARS = range(2019, 2036)
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sources", "NumlexCore", "Resources", "NumlexHolidays")


def easter(year):
    """Anonymous Gregorian computus (Western Easter Sunday)."""
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return date(year, month, day)


def nth_weekday(year, month, weekday, n):
    """The n-th `weekday` (0=Mon) of a month."""
    first = date(year, month, 1)
    offset = (weekday - first.weekday()) % 7
    return first + timedelta(days=offset + 7 * (n - 1))


def last_weekday(year, month, weekday):
    if month == 12:
        last = date(year, 12, 31)
    else:
        last = date(year, month + 1, 1) - timedelta(days=1)
    offset = (last.weekday() - weekday) % 7
    return last - timedelta(days=offset)


def fixed(month, day):
    return lambda y: date(y, month, day)


def good_friday(y):
    return easter(y) - timedelta(days=2)


def easter_monday(y):
    return easter(y) + timedelta(days=1)


def ascension(y):
    return easter(y) + timedelta(days=39)


def whit_monday(y):
    return easter(y) + timedelta(days=50)


def corpus_christi(y):
    return easter(y) + timedelta(days=60)


def since(start_year, rule):
    """A rule that only applies from `start_year` (earlier years return Jan 1,
    which is already a holiday and is de-duplicated)."""
    return lambda y: rule(y) if y >= start_year else date(y, 1, 1)


def vernal_equinox(y):
    """The Japan Meteorological Agency vernal equinox formula (valid
    1980-2099)."""
    day = int(20.8431 + 0.242194 * (y - 1980) - ((y - 1980) // 4))
    return date(y, 3, day)


def autumnal_equinox(y):
    day = int(23.2488 + 0.242194 * (y - 1980) - ((y - 1980) // 4))
    return date(y, 9, day)


def midsummer(y):
    d = date(y, 6, 20)
    while d.weekday() != 5:
        d += timedelta(days=1)
    return d


def all_saints_sweden(y):
    d = date(y, 10, 31)
    while d.weekday() != 5:
        d += timedelta(days=1)
    return d


F = fixed
GF = good_friday
EM = easter_monday
ASC = ascension
WM = whit_monday
CC = corpus_christi

# country -> list of zero-argument (year) rules. National holidays only.
RULES = {
    "US": [F(1, 1), lambda y: nth_weekday(y, 1, 0, 3), lambda y: nth_weekday(y, 2, 0, 3),
           lambda y: last_weekday(y, 5, 0), F(7, 4), lambda y: nth_weekday(y, 9, 0, 1),
           lambda y: nth_weekday(y, 10, 0, 2), F(11, 11),
           lambda y: nth_weekday(y, 11, 3, 4), F(12, 25),
           since(2021, F(6, 19))],
    "CA": [F(1, 1), GF,
           lambda y: date(y, 5, 25) - timedelta(days=date(y, 5, 25).weekday()),
           F(7, 1), lambda y: nth_weekday(y, 9, 0, 1), lambda y: nth_weekday(y, 10, 0, 2),
           F(11, 11), F(12, 25), F(12, 26)],
    "GB": [F(1, 1), GF, EM, lambda y: nth_weekday(y, 5, 0, 1),
           lambda y: last_weekday(y, 5, 0), lambda y: last_weekday(y, 8, 0),
           F(12, 25), F(12, 26)],
    "DE": [F(1, 1), GF, EM, F(5, 1), ASC, WM, F(10, 3), F(12, 25), F(12, 26)],
    "FR": [F(1, 1), EM, F(5, 1), F(5, 8), ASC, WM, F(7, 14), F(8, 15),
           F(11, 1), F(11, 11), F(12, 25)],
    "IT": [F(1, 1), F(1, 6), EM, F(4, 25), F(5, 1), F(6, 2), F(8, 15),
           F(11, 1), F(12, 8), F(12, 25), F(12, 26)],
    "ES": [F(1, 1), F(1, 6), GF, F(5, 1), F(8, 15), F(10, 12), F(11, 1),
           F(12, 6), F(12, 8), F(12, 25)],
    "RU": [F(1, 1), F(1, 2), F(1, 3), F(1, 4), F(1, 5), F(1, 6), F(1, 7), F(1, 8),
           F(2, 23), F(3, 8), F(5, 1), F(5, 9), F(6, 12), F(11, 4)],
    "JP": [F(1, 1), lambda y: nth_weekday(y, 1, 0, 2), F(2, 11), F(2, 23),
           vernal_equinox, F(4, 29), F(5, 3), F(5, 4), F(5, 5),
           lambda y: nth_weekday(y, 7, 0, 3), F(8, 11),
           lambda y: nth_weekday(y, 9, 0, 3), autumnal_equinox,
           lambda y: nth_weekday(y, 10, 0, 2), F(11, 3), F(11, 23)],
    "CN": [F(1, 1), F(5, 1), F(5, 2), F(5, 3), F(10, 1), F(10, 2), F(10, 3),
           F(10, 4), F(10, 5), F(10, 6), F(10, 7)],
    "AU": [F(1, 1), F(1, 26), GF, EM, F(4, 25), F(12, 25), F(12, 26)],
    "BR": [F(1, 1), GF, F(4, 21), F(5, 1), F(9, 7), F(10, 12), F(11, 2),
           F(11, 15), F(12, 25)],
    "IN": [F(1, 26), F(8, 15), F(10, 2)],
    "KR": [F(1, 1), F(3, 1), F(5, 5), F(6, 6), F(8, 15), F(10, 3), F(10, 9),
           F(12, 25)],
    "NL": [F(1, 1), GF, EM, F(4, 27), ASC, WM, F(12, 25), F(12, 26)],
    "PL": [F(1, 1), F(1, 6), EM, F(5, 1), F(5, 3), CC, F(8, 15), F(11, 1),
           F(11, 11), F(12, 25), F(12, 26)],
    "SE": [F(1, 1), F(1, 6), GF, EM, F(5, 1), ASC, F(6, 6), midsummer,
           all_saints_sweden, F(12, 25), F(12, 26)],
    "CH": [F(1, 1), ASC, F(8, 1), F(12, 25)],
    "AT": [F(1, 1), F(1, 6), EM, F(5, 1), ASC, WM, CC, F(8, 15), F(10, 26),
           F(11, 1), F(12, 8), F(12, 25), F(12, 26)],
    "BE": [F(1, 1), EM, F(5, 1), ASC, WM, F(7, 21), F(8, 15), F(11, 1),
           F(11, 11), F(12, 25)],
    "PT": [F(1, 1), GF, F(4, 25), F(5, 1), CC, F(6, 10), F(8, 15), F(10, 5),
           F(11, 1), F(12, 1), F(12, 8), F(12, 25)],
    "IE": [F(1, 1), F(3, 17), EM, lambda y: nth_weekday(y, 5, 0, 1),
           lambda y: nth_weekday(y, 6, 0, 1), lambda y: nth_weekday(y, 8, 0, 1),
           lambda y: last_weekday(y, 10, 0), F(12, 25), F(12, 26)],
    "MX": [F(1, 1), lambda y: nth_weekday(y, 2, 0, 1),
           lambda y: nth_weekday(y, 3, 0, 3), F(5, 1), F(9, 16),
           lambda y: nth_weekday(y, 11, 0, 3), F(12, 25)],
    "NZ": [F(1, 1), F(1, 2), F(2, 6), GF, EM, F(4, 25),
           lambda y: nth_weekday(y, 6, 0, 1), lambda y: nth_weekday(y, 10, 0, 4),
           F(12, 25), F(12, 26)],
    "ZA": [F(1, 1), F(3, 21), GF, EM, F(4, 27), F(5, 1), F(6, 16), F(8, 9),
           F(9, 24), F(12, 16), F(12, 25), F(12, 26)],
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    lines = ["# country\tdate\tholiday"]
    counts = {}
    for country in sorted(RULES):
        count = 0
        for year in YEARS:
            seen = set()
            for rule in RULES[country]:
                d = rule(year)
                if d.year != year or d in seen:
                    continue
                seen.add(d)
                lines.append(f"{country}\t{d.isoformat()}\tholiday")
                count += 1
        counts[country] = count
    payload = "\n".join(lines) + "\n"
    data = payload.encode("utf-8")
    digest = hashlib.sha256(data).hexdigest()
    with open(os.path.join(OUT_DIR, "holidays.tsv"), "wb") as fh:
        fh.write(data)
    manifest = {
        "attribution": "National public-holiday rule tables compiled by Numlex from public government calendars (national holidays only; regional/state observances excluded).",
        "countries": counts,
        "generator": "Scripts/generate-holiday-data.py",
        "license": "Public-domain rule tables; the generated data set is provided under CC0.",
        "resources": {"holidays.tsv": {"sha256": digest}},
        "version": VERSION,
        "yearRange": [min(YEARS), max(YEARS)],
    }
    with open(os.path.join(OUT_DIR, "sources.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print(f"wrote {len(lines) - 1} holidays for {len(counts)} countries "
          f"({min(YEARS)}-{max(YEARS)}), sha256={digest}")


if __name__ == "__main__":
    main()
