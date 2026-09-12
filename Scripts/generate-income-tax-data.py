#!/usr/bin/env python3
"""Reproducible generator for Numlex's bundled estimated income-tax tables.

Emits the versioned `income-tax-2026.2` dataset and its manifest:

  Sources/NumlexCore/Resources/NumlexIncomeTax/income-tax.json
  Sources/NumlexCore/Resources/NumlexIncomeTax/sources.json

Each table carries an explicit `taxPeriod` string (fiscal years cannot
always be described by one integer): US `2026`, UK `2026/27`, France
`2026 (income 2025)`, NL `2026`, DE `2026`, JP `2026`, RU `2026`,
Australia `2025-26`, Canada `2025`, India `AY 2026-27 (FY 2025-26)`.

Verified at the 2026-09-12 snapshot:
- US: IRS news release "IRS releases tax inflation adjustments for tax
  year 2026" (single brackets 12,400/50,400/105,700/201,775/256,225/
  640,600, standard deduction 16,100, folded into the brackets).
- UK: GOV.UK "Income Tax rates and Personal Allowances" — the current
  tax year at the snapshot is 6 April 2026 to 5 April 2027.
- DE: EStG §32a (gesetze-im-internet.de) tariff applicable from
  Veranlagungszeitraum 2026 (Grundfreibetrag 12,348).
- FR: Service-Public F1419 (verified 15 April 2026) barème applicable
  to 2025 income, i.e. the 2026 tax computation.
- NL: Belastingdienst box-1 tariffs 2026 (38,883 / 78,426 / 49.50%).
- JP: NTA No.2260 rate table current as of 1 April 2026.
- RU: progressive NDFL rates enacted from 2025 and applicable in 2026
  (thresholds not indexed in the consulted official source).

UNVERIFIED FOR 2026 (reported as blockers, schedules kept with their
TRUE periods — never relabelled): Australia (2025-26; the 2026-27
schedule could not be retrieved from the ATO), Canada (2025; canada.ca
unreachable from the generation network), India (AY 2026-27 / FY
2025-26; no official FY 2026-27 schedule found).

Model: rough national estimate for a single individual — progressive
brackets over the taxable amount with the basic allowance/standard
deduction folded in as a 0% slice; state/province/local taxes, credits,
social contributions and personal circumstances excluded. Germany uses
a flat approximation of its progressive zones.
"""

import hashlib
import json
import os

VERSION = "income-tax-2026.2"
SNAPSHOT = "2026-09-12"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sources", "NumlexCore", "Resources", "NumlexIncomeTax")

MODEL = ("Progressive national brackets for a single individual, including the "
         "basic zero-rate allowance/standard deduction folded in. Excludes "
         "state/province/local taxes, most credits and deductions, and social "
         "contributions.")

# country, aliases, currency, taxPeriod, brackets [(upTo|None, rate)], source, note
TABLES = [
    {
        "country": "US",
        "aliases": ["US", "USA", "United States", "United States of America"],
        "currency": "USD",
        "taxPeriod": "2026",
        "brackets": [[16100, 0.0], [28500, 0.10], [66500, 0.12],
                     [121800, 0.22], [217875, 0.24], [272325, 0.32],
                     [656700, 0.35], [None, 0.37]],
        "sourceTitle": ("IRS — IRS releases tax inflation adjustments for tax "
                        "year 2026 (single filer)"),
        "sourceURL": ("https://www.irs.gov/newsroom/irs-releases-tax-inflation-"
                      "adjustments-for-tax-year-2026-including-amendments-from-the-"
                      "one-big-beautiful-bill"),
        "note": ("Single filer, tax year 2026: 10/12/22/24/32/35/37% brackets "
                 "(12,400/50,400/105,700/201,775/256,225/640,600) with the "
                 "$16,100 standard deduction folded in as a 0% slice. State "
                 "taxes excluded."),
    },
    {
        "country": "GB",
        "aliases": ["GB", "UK", "United Kingdom", "Great Britain"],
        "currency": "GBP",
        "taxPeriod": "2026/27",
        "brackets": [[12570, 0.0], [50270, 0.20], [125140, 0.40], [None, 0.45]],
        "sourceTitle": ("GOV.UK — Income Tax rates and Personal Allowances "
                        "(current tax year 6 April 2026 to 5 April 2027)"),
        "sourceURL": "https://www.gov.uk/income-tax-rates",
        "note": ("England/Wales/Northern Ireland rates for 2026/27; personal "
                 "allowance £12,570 as a 0% bracket, no taper modelled."),
    },
    {
        "country": "DE",
        "aliases": ["DE", "Germany", "Deutschland"],
        "currency": "EUR",
        "taxPeriod": "2026",
        "brackets": [[12348, 0.0], [17799, 0.14], [69878, 0.24],
                     [277825, 0.42], [None, 0.45]],
        "sourceTitle": ("EStG §32a (gesetze-im-internet.de) — Tarif ab dem "
                        "Veranlagungszeitraum 2026"),
        "sourceURL": "https://www.gesetze-im-internet.de/estg/__32a.html",
        "note": ("Approximation: Grundfreibetrag 12,348 € as a 0% slice; the "
                 "progressive 14–24% and 24–42% zones are represented by flat "
                 "14%/24% steps, then the statutory 42%/45% bands. Solidarity "
                 "surcharge and social contributions excluded."),
    },
    {
        "country": "FR",
        "aliases": ["FR", "France"],
        "currency": "EUR",
        "taxPeriod": "2026 (income 2025)",
        "brackets": [[11600, 0.0], [29579, 0.11], [84577, 0.30],
                     [181917, 0.41], [None, 0.45]],
        "sourceTitle": ("Service-Public (Direction de l'information légale et "
                        "administrative) — barème 2026 applicable aux revenus "
                        "de 2025"),
        "sourceURL": "https://www.service-public.fr/particuliers/vosdroits/F1419",
        "note": ("Single share (1 part); the 10% professional allowance is not "
                 "modelled. Social levies excluded."),
    },
    {
        "country": "NL",
        "aliases": ["NL", "Netherlands", "Holland"],
        "currency": "EUR",
        "taxPeriod": "2026",
        "brackets": [[38883, 0.3575], [78426, 0.3756], [None, 0.495]],
        "sourceTitle": "Belastingdienst — Tarieven box 1, 2026",
        "sourceURL": ("https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/"
                      "belastingdienst/prive/inkomstenbelasting/heffingskortingen_"
                      "boxen_tarieven/boxen_en_tarieven/box_1/box_1"),
        "note": ("Box-1 rates for 2026 before heffingskortingen (which are "
                 "excluded)."),
    },
    {
        "country": "AU",
        "aliases": ["AU", "Australia"],
        "currency": "AUD",
        "taxPeriod": "2026-27",
        "brackets": [[18200, 0.0], [45000, 0.15], [135000, 0.30],
                     [190000, 0.37], [None, 0.45]],
        "sourceTitle": ("Australian Government Budget 2025–26 — Fact sheet: New "
                        "tax cuts (personal tax rates for 2026–27)"),
        "sourceURL": ("https://archive.budget.gov.au/2025-26/factsheets/download/"
                      "factsheet-new-tax-cuts.pdf"),
        "note": ("Resident rates for 2026–27: the 18,201–45,000 bracket legislated "
                 "down from 16% to 15% from 1 July 2026 (Budget 2025–26 fact "
                 "sheet); thresholds unchanged. Medicare levy and offsets "
                 "excluded."),
    },
    {
        "country": "CA",
        "aliases": ["CA", "Canada"],
        "currency": "CAD",
        "taxPeriod": "2026",
        "brackets": [[16452, 0.0], [74975, 0.14], [133497, 0.205],
                     [197892, 0.26], [274934, 0.29], [None, 0.33]],
        "sourceTitle": ("Canada Revenue Agency — Current year tax rates and income "
                        "brackets (2026) / Indexation adjustment for 2026"),
        "sourceURL": ("https://www.canada.ca/en/revenue-agency/services/tax/"
                      "individuals/tax-rates-brackets/current-year.html"),
        "note": ("Federal rates for 2026 (14% on the first bracket), with the 2026 "
                 "maximum basic personal amount ($16,452) folded in as a 0% "
                 "slice and the thresholds shifted accordingly (CRA indexation "
                 "adjustment, 2.0% for 2026). Provincial taxes excluded."),
    },
    {
        "country": "IN",
        "aliases": ["IN", "India"],
        "currency": "INR",
        "taxPeriod": "FY 2026-27 (AY 2027-28)",
        "brackets": [[400000, 0.0], [800000, 0.05], [1200000, 0.10],
                     [1600000, 0.15], [2000000, 0.20], [2400000, 0.25],
                     [None, 0.30]],
        "sourceTitle": ("Finance Bill 2026 (Bill No. 3 of 2026, introduced "
                        "1 Feb 2026) and the Income Tax Department new-regime "
                        "slab schedule"),
        "sourceURL": "https://www.indiabudget.gov.in/doc/Finance_Bill.pdf",
        "note": ("Income tax for FY 2026-27 is charged from 1 April 2026 under "
                 "the Act at the unchanged new-regime slabs (Budget 2026-27 "
                 "proposed no slab change; the Income Tax Act 2025 took effect "
                 "1 April 2026). Section 87A rebate, surcharge and cess "
                 "excluded; the standard deduction is not modelled."),
    },
    {
        "country": "RU",
        "aliases": ["RU", "Russia", "Russian Federation"],
        "currency": "RUB",
        "taxPeriod": "2026",
        "brackets": [[2400000, 0.13], [5000000, 0.15], [20000000, 0.18],
                     [50000000, 0.20], [None, 0.22]],
        "sourceTitle": ("ФНС России — прогрессивные ставки НДФЛ (действуют с 2025 "
                        "года, применяются в 2026)"),
        "sourceURL": "https://www.nalog.gov.ru/rn77/taxation/taxes/ndfl/",
        "note": ("Progressive NDFL rates enacted from 2025 and applicable in "
                 "2026 per the consulted official source; thresholds not "
                 "indexed there. Social contributions and investment deductions "
                 "excluded."),
    },
    {
        "country": "JP",
        "aliases": ["JP", "Japan"],
        "currency": "JPY",
        "taxPeriod": "2026",
        "brackets": [[480000, 0.0], [2430000, 0.05], [3780000, 0.10],
                     [7430000, 0.20], [9480000, 0.23], [18480000, 0.33],
                     [40480000, 0.40], [None, 0.45]],
        "sourceTitle": ("National Tax Agency — No.2260 Income tax rates "
                        "(current as of 1 April 2026)"),
        "sourceURL": "https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2260.htm",
        "note": ("National rates current for 2026; the statutory basic deduction "
                 "(¥480,000) is folded in as a 0% slice. The 2026 reform's "
                 "salary-income measures and the local inhabitant tax (10%) are "
                 "not modelled."),
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
    blockers = []
    for table in TABLES:
        brackets = []
        for up_to, rate in table["brackets"]:
            brackets.append({"upTo": up_to, "rate": rate})
        prev = 0
        for b in brackets[:-1]:
            assert b["upTo"] is not None and b["upTo"] > prev, table["country"]
            prev = b["upTo"]
        assert brackets[-1]["upTo"] is None, table["country"]
        if "BLOCKER" in table["note"]:
            blockers.append({"country": table["country"],
                             "taxPeriod": table["taxPeriod"],
                             "reason": table["note"].split("BLOCKER:")[1].strip()})
        payload["countries"].append({
            "country": table["country"],
            "aliases": table["aliases"],
            "currency": table["currency"],
            "taxYear": int(table["taxPeriod"].split("/")[0][:4])
            if table["taxPeriod"][0].isdigit() else 0,
            "taxPeriod": table["taxPeriod"],
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
        "attribution": payload["attribution"],
        "license": payload["license"],
        "generator": "Scripts/generate-income-tax-data.py",
        "taxPeriods": {c["country"]: c["taxPeriod"] for c in payload["countries"]},
        "unverifiedFor2026": blockers,
        "resources": {"income-tax.json": {"sha256": digest}},
    }
    with open(os.path.join(OUT_DIR, "sources.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {len(payload['countries'])} income-tax tables "
          f"({len(blockers)} 2026 blockers), sha256={digest}")


if __name__ == "__main__":
    main()
