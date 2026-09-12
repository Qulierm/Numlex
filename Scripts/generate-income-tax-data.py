#!/usr/bin/env python3
"""Reproducible generator for Numlex's bundled estimated income-tax tables.

Emits the versioned `income-tax-2026.1` dataset and its manifest:

  Sources/NumlexCore/Resources/NumlexIncomeTax/income-tax.json
  Sources/NumlexCore/Resources/NumlexIncomeTax/sources.json

The tables are the latest FULLY PUBLISHED national schedules for a single
individual at the snapshot date; every table carries its own tax year,
local currency, official source title/URL and an explicit model note.
The loader verifies the recorded SHA-256, so a truncated or edited file
can never load. Runtime is fully offline.

Model: rough national estimate — progressive brackets over the taxable
amount (the zero-allowance/standard-deduction slice is a 0% bracket).
Excludes state/province/local taxes, credits, deductions beyond the
basic allowance and social contributions. Germany and France use a flat
approximation of their progressive zones, documented in each note.
"""

import hashlib
import json
import os
from datetime import date

VERSION = "income-tax-2026.1"
SNAPSHOT = "2026-09-12"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sources", "NumlexCore", "Resources", "NumlexIncomeTax")

MODEL = ("Progressive national brackets for a single individual, including the "
         "basic zero-rate allowance/standard deduction. Excludes state/province/"
         "local taxes, most credits and deductions, and social contributions.")

# country, aliases, currency, tax year, brackets [(upTo|None, rate)], source, note
TABLES = [
    {
        "country": "US",
        "aliases": ["US", "USA", "United States", "United States of America"],
        "currency": "USD",
        "taxYear": 2025,
        "brackets": [[15000, 0.0], [26925, 0.10], [63475, 0.12],
                     [118350, 0.22], [212300, 0.24], [265525, 0.32],
                     [641350, 0.35], [None, 0.37]],
        "sourceTitle": "IRS Rev. Proc. 2024-40 — 2025 tax brackets (single filer)",
        "sourceURL": "https://www.irs.gov/pub/irs-drop/rp-24-40.pdf",
        "note": ("Single filer; the 2025 standard deduction ($15,000) is folded "
                 "into the brackets as a 0% slice, with the statutory 10/12/22/24/"
                 "32/35/37% brackets shifted accordingly. State taxes excluded."),
    },
    {
        "country": "GB",
        "aliases": ["GB", "UK", "United Kingdom", "Great Britain"],
        "currency": "GBP",
        "taxYear": 2025,
        "brackets": [[12570, 0.0], [50270, 0.20], [125140, 0.40], [None, 0.45]],
        "sourceTitle": "GOV.UK — Income Tax rates and Personal Allowances (2025/26)",
        "sourceURL": "https://www.gov.uk/income-tax-rates",
        "note": ("England/Wales/Northern Ireland rates; personal allowance as a "
                 "0% bracket, no taper modelled."),
    },
    {
        "country": "DE",
        "aliases": ["DE", "Germany", "Deutschland"],
        "currency": "EUR",
        "taxYear": 2025,
        "brackets": [[12096, 0.0], [17443, 0.14], [68480, 0.24],
                     [277825, 0.42], [None, 0.45]],
        "sourceTitle": "Bundesministerium der Finanzen — Einkommensteuertarif 2025",
        "sourceURL": "https://www.bundesfinanzministerium.de/Web/DE/Themen/Steuern/Steuerarten/Einkommensteuer/einkommensteuer.html",
        "note": ("Approximation: the progressive 14–42% zones are represented by "
                 "flat 14%/24% steps; solidarity surcharge and social "
                 "contributions excluded. Single individual."),
    },
    {
        "country": "FR",
        "aliases": ["FR", "France"],
        "currency": "EUR",
        "taxYear": 2025,
        "brackets": [[11497, 0.0], [29315, 0.11], [83823, 0.30],
                     [177106, 0.41], [None, 0.45]],
        "sourceTitle": "impots.gouv.fr — Barème de l'impôt sur le revenu 2025",
        "sourceURL": "https://www.impots.gouv.fr/particulier/questions/comment-calculer-mon-impot-sur-le-revenu",
        "note": ("Single share (1 part); the 10% professional allowance is not "
                 "modelled. Social levies excluded."),
    },
    {
        "country": "AU",
        "aliases": ["AU", "Australia"],
        "currency": "AUD",
        "taxYear": 2025,
        "brackets": [[18200, 0.0], [45000, 0.16], [135000, 0.30],
                     [190000, 0.37], [None, 0.45]],
        "sourceTitle": "ATO — Resident tax rates 2024–25",
        "sourceURL": "https://www.ato.gov.au/tax-rates-and-codes/tax-rates-australian-residents",
        "note": ("Resident rates; Medicare levy and offsets excluded."),
    },
    {
        "country": "CA",
        "aliases": ["CA", "Canada"],
        "currency": "CAD",
        "taxYear": 2025,
        "brackets": [[16129, 0.0], [73504, 0.15], [130879, 0.205],
                     [194011, 0.26], [269543, 0.29], [None, 0.33]],
        "sourceTitle": "Canada Revenue Agency — 2025 federal income tax rates",
        "sourceURL": "https://www.canada.ca/en/revenue-agency/services/tax/individuals/frequently-asked-questions-individuals/canadian-income-tax-rates-individuals-current-previous-years.html",
        "note": ("Federal rates; the basic personal amount ($16,129) is folded "
                 "into the brackets as a 0% slice. Provincial taxes excluded."),
    },
    {
        "country": "NL",
        "aliases": ["NL", "Netherlands", "Holland"],
        "currency": "EUR",
        "taxYear": 2025,
        "brackets": [[38441, 0.3582], [76817, 0.3707], [None, 0.495]],
        "sourceTitle": "Belastingdienst — Tarieven inkomstenbelasting 2025",
        "sourceURL": "https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/belastingdienst/prive/inkomstenbelasting/heffingskortingen_boxen_tarieven/boxen_en_tarieven/box_1/box_1",
        "note": ("Box-1 rates before heffingskortingen (which are excluded)."),
    },
    {
        "country": "IN",
        "aliases": ["IN", "India"],
        "currency": "INR",
        "taxYear": 2025,
        "brackets": [[400000, 0.0], [800000, 0.05], [1200000, 0.10],
                     [1600000, 0.15], [2000000, 0.20], [2400000, 0.25],
                     [None, 0.30]],
        "sourceTitle": "Income Tax Department — New regime slab rates, FY 2025-26",
        "sourceURL": "https://www.incometax.gov.in/iec/foportal/help/individual/return-applicable-1",
        "note": ("New regime resident slabs; Section 87A rebate, surcharge and "
                 "cess excluded; the standard deduction is not modelled."),
    },
    {
        "country": "RU",
        "aliases": ["RU", "Russia", "Russian Federation"],
        "currency": "RUB",
        "taxYear": 2025,
        "brackets": [[2400000, 0.13], [5000000, 0.15], [20000000, 0.18],
                     [50000000, 0.20], [None, 0.22]],
        "sourceTitle": "ФНС России — прогрессивные ставки НДФЛ с 2025 года",
        "sourceURL": "https://www.nalog.gov.ru/rn77/news/activities_fts/14935962/",
        "note": ("Resident progressive NDFL rates; social contributions and "
                 "investment deductions excluded."),
    },
    {
        "country": "JP",
        "aliases": ["JP", "Japan"],
        "currency": "JPY",
        "taxYear": 2025,
        "brackets": [[480000, 0.0], [2430000, 0.05], [3780000, 0.10],
                     [7430000, 0.20], [9480000, 0.23], [18480000, 0.33],
                     [40480000, 0.40], [None, 0.45]],
        "sourceTitle": "National Tax Agency — Income tax rates (national, 2025)",
        "sourceURL": "https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2260.htm",
        "note": ("National rates; the basic deduction (¥480,000) is folded into "
                 "the brackets as a 0% slice. Local inhabitant tax excluded."),
    },
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    payload = {
        "version": VERSION,
        "snapshotDate": SNAPSHOT,
        "model": MODEL,
        "attribution": ("National tax schedules compiled by Numlex from the "
                        "official sources listed per country (factual data)."),
        "license": "Factual public data; the compiled dataset is CC0.",
        "countries": [],
    }
    for table in TABLES:
        brackets = []
        for up_to, rate in table["brackets"]:
            brackets.append({"upTo": up_to, "rate": rate})
        # Structure validation: sorted, finite, last open-ended.
        prev = 0
        for b in brackets[:-1]:
            assert b["upTo"] is not None and b["upTo"] > prev, table["country"]
            prev = b["upTo"]
        assert brackets[-1]["upTo"] is None, table["country"]
        payload["countries"].append({
            "country": table["country"],
            "aliases": table["aliases"],
            "currency": table["currency"],
            "taxYear": table["taxYear"],
            "brackets": brackets,
            "source": {"title": table["sourceTitle"], "url": table["sourceURL"]},
            "note": table["note"],
        })
    data = json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False).encode("utf-8") + b"\n"
    with open(os.path.join(OUT_DIR, "income-tax.json"), "wb") as fh:
        fh.write(data)
    digest = hashlib.sha256(data).hexdigest()
    manifest = {
        "version": VERSION,
        "snapshotDate": SNAPSHOT,
        "taxYearNote": ("Dataset released 2026; each table carries the latest "
                        "fully published national schedule at the snapshot date."),
        "attribution": payload["attribution"],
        "license": payload["license"],
        "generator": "Scripts/generate-income-tax-data.py",
        "resources": {"income-tax.json": {"sha256": digest}},
    }
    with open(os.path.join(OUT_DIR, "sources.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {len(payload['countries'])} income-tax tables, sha256={digest}")


if __name__ == "__main__":
    main()
