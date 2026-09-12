#!/usr/bin/env python3
"""Reproducible generator for Numlex's bundled sales-tax presets.

Writes the versioned `tax-presets-2026.1` table and its manifest:

  Sources/NumlexCore/Resources/NumlexTax/tax-presets.json
  Sources/NumlexCore/Resources/NumlexTax/sources.json

Every row is the official STANDARD national rate (VAT/GST/consumption
tax) at the snapshot date; regional and sub-national rates are out of
scope by design. The United States has NO automatic national rate
(`ratePercent: null`) and always requires a manual entry. The loader
verifies the recorded SHA-256 and fails closed; runtime is fully
offline.
"""

import hashlib
import json
import os

VERSION = "tax-presets-2026.1"
SNAPSHOT = "2026-09-12"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sources", "NumlexCore", "Resources", "NumlexTax")

PRESETS = [
    ("AU", "GST", 10.0, "Australia GST, 10%"),
    ("GB", "VAT", 20.0, "United Kingdom VAT, 20%")
    ,
    ("DE", "VAT", 19.0, "Germany VAT (Mehrwertsteuer), 19%"),
    ("NL", "VAT", 21.0, "Netherlands VAT (BTW), 21%"),
    ("FR", "VAT", 20.0, "France TVA, 20%"),
    ("IT", "VAT", 22.0, "Italy IVA, 22%"),
    ("ES", "VAT", 21.0, "Spain IVA, 21%"),
    ("IE", "VAT", 23.0, "Ireland VAT, 23%"),
    ("AT", "VAT", 20.0, "Austria VAT (USt), 20%"),
    ("BE", "VAT", 21.0, "Belgium VAT (TVA/BTW), 21%"),
    ("PL", "VAT", 23.0, "Poland VAT (PTU), 23%"),
    ("PT", "VAT", 23.0, "Portugal IVA, 23%"),
    ("SE", "VAT", 25.0, "Sweden VAT (moms), 25%"),
    ("DK", "VAT", 25.0, "Denmark VAT (moms), 25%"),
    ("NO", "VAT", 25.0, "Norway VAT (mva), 25%"),
    ("FI", "VAT", 25.5, "Finland VAT (ALV), 25.5% (2024 standard rate)"),
    ("CH", "VAT", 8.1, "Switzerland VAT (MWST), 8.1% (2024 standard rate)"),
    ("NZ", "GST", 15.0, "New Zealand GST, 15%"),
    ("SG", "GST", 9.0, "Singapore GST, 9% (2024)"),
    ("JP", "Consumption Tax", 10.0, "Japan consumption tax, 10% standard"),
    ("CA", "GST", 5.0, "Canada federal GST, 5% (provincial taxes excluded)"),
    ("IN", "GST", 18.0, "India GST standard rate, 18%"),
    ("ZA", "VAT", 15.0, "South Africa VAT, 15%"),
    ("MX", "VAT", 16.0, "Mexico IVA, 16%"),
    ("US", "Sales Tax", None,
     "United States: no national rate — enter your local rate manually"),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    payload = {
        "version": VERSION,
        "snapshotDate": SNAPSHOT,
        "attribution": ("Standard national VAT/GST/consumption-tax rates compiled "
                        "by Numlex from official government sources (factual data)."),
        "license": "Factual public data; the compiled dataset is CC0.",
        "presets": [
            {"region": region, "name": name, "ratePercent": rate, "note": note}
            for region, name, rate, note in PRESETS
        ],
    }
    data = json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False).encode("utf-8") + b"\n"
    with open(os.path.join(OUT_DIR, "tax-presets.json"), "wb") as fh:
        fh.write(data)
    digest = hashlib.sha256(data).hexdigest()
    manifest = {
        "version": VERSION,
        "snapshotDate": SNAPSHOT,
        "attribution": payload["attribution"],
        "license": payload["license"],
        "generator": "Scripts/generate-tax-presets.py",
        "resources": {"tax-presets.json": {"sha256": digest}},
    }
    with open(os.path.join(OUT_DIR, "sources.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {len(PRESETS)} tax presets, sha256={digest}")


if __name__ == "__main__":
    main()
