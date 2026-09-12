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

VERSION = "tax-presets-2026.2"
SNAPSHOT = "2026-09-12"
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "Sources", "NumlexCore", "Resources", "NumlexTax")

PRESETS = [
    ("AU", "GST", 10.0, "Australia GST, 10%",
     "Australian Taxation Office — GST", "https://www.ato.gov.au/businesses-and-organisations/gst-excise-and-indirect-taxes/gst"),
    ("GB", "VAT", 20.0, "United Kingdom VAT, 20%",
     "GOV.UK — VAT rates", "https://www.gov.uk/vat-rates"),
    ("DE", "VAT", 19.0, "Germany VAT (Mehrwertsteuer), 19%",
     "UStG §12 (gesetze-im-internet.de) — Steuersätze", "https://www.gesetze-im-internet.de/ustg_1980/__12.html"),
    ("NL", "VAT", 21.0, "Netherlands VAT (BTW), 21%",
     "Belastingdienst — Btw-tarieven", "https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/belastingdienst/zakelijk/btw/btw_berekenen_aan_uw_klanten/btw_tarieven/btw_tarieven"),
    ("FR", "VAT", 20.0, "France TVA, 20%",
     "impots.gouv.fr — La TVA", "https://www.impots.gouv.fr/professionnel/la-tva"),
    ("IT", "VAT", 22.0, "Italy IVA, 22%",
     "Agenzia delle Entrate — Aliquote IVA", "https://www.agenziaentrate.gov.it/portale/web/guest/schede/iva/iva-aliquote"),
    ("ES", "VAT", 21.0, "Spain IVA, 21%",
     "Agencia Tributaria — IVA", "https://sede.agenciatributaria.gob.es/Sede/en_gb/iva.html"),
    ("IE", "VAT", 23.0, "Ireland VAT, 23%",
     "Revenue Commissioners — VAT rates", "https://www.revenue.ie/en/vat/vat-rates/index.aspx"),
    ("AT", "VAT", 20.0, "Austria VAT (USt), 20%",
     "Bundesministerium für Finanzen — Umsatzsteuer", "https://www.bmf.gv.at/services/steuern/umsatzsteuer.html"),
    ("BE", "VAT", 21.0, "Belgium VAT (TVA/BTW), 21%",
     "SPF Finances — TVA", "https://finances.belgium.be/fr/entreprises/tva"),
    ("PL", "VAT", 23.0, "Poland VAT (PTU), 23%",
     "Podatki.gov.pl — Stawki VAT", "https://www.podatki.gov.pl/vat/stawki-vat/"),
    ("PT", "VAT", 23.0, "Portugal IVA, 23%",
     "Portal das Finanças — Tabelas de taxas de IVA", "https://www.portaldasfinancas.gov.pt/pt/consultaTabelasTaxas.action"),
    ("SE", "VAT", 25.0, "Sweden VAT (moms), 25%",
     "Skatteverket — Moms", "https://www.skatteverket.se/foretag/moms.html"),
    ("DK", "VAT", 25.0, "Denmark VAT (moms), 25%",
     "Skattestyrelsen — Moms", "https://skat.dk/erhverv/moms"),
    ("NO", "VAT", 25.0, "Norway VAT (mva), 25%",
     "Skatteetaten — Merverdiavgift", "https://www.skatteetaten.no/bedrift-og-organisasjon/avgifter/mva/"),
    ("FI", "VAT", 25.5, "Finland VAT (ALV), 25.5% (2024 standard rate)",
     "Verohallinto — Value added tax", "https://www.vero.fi/en/businesses-and-corporations/taxes-and-charges/vat/"),
    ("CH", "VAT", 8.1, "Switzerland VAT (MWST), 8.1% (2024 standard rate)",
     "ESTV — Value added tax", "https://www.estv.admin.ch/estv/en/home/value-added-tax.html"),
    ("NZ", "GST", 15.0, "New Zealand GST, 15%",
     "Inland Revenue — GST", "https://www.ird.govt.nz/gst"),
    ("SG", "GST", 9.0, "Singapore GST, 9% (2024)",
     "IRAS — GST rate", "https://www.iras.gov.sg/taxes/goods-services-tax-(gst)/gst-rate"),
    ("JP", "Consumption Tax", 10.0, "Japan consumption tax, 10% standard",
     "National Tax Agency — Consumption tax", "https://www.nta.go.jp/english/taxes/consumption_tax/index.htm"),
    ("CA", "GST", 5.0, "Canada federal GST, 5% (provincial taxes excluded)",
     "Canada Revenue Agency — GST/HST rates", "https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/gst-hst-businesses/gst-hst-rates.html"),
    ("IN", "GST", 18.0, "India GST standard rate, 18%",
     "CBIC — Goods and Services Tax", "https://www.cbic.gov.in/entities/gst"),
    ("ZA", "VAT", 15.0, "South Africa VAT, 15%",
     "SARS — Value-Added Tax", "https://www.sars.gov.za/customs-and-excise/valued-added-tax-vat/"),
    ("MX", "VAT", 16.0, "Mexico IVA, 16%",
     "SAT — IVA", "https://www.sat.gob.mx/consultas/44031/conoce-las-tasas-de-iva"),
    ("US", "Sales Tax", None,
     "United States: no national rate — enter your local rate manually",
     "IRS — State and local sales tax deduction (sales tax is state/local; "
     "there is no national US sales tax rate)",
     "https://www.irs.gov/businesses/small-businesses-self-employed/state-and-local-sales-tax-deduction"),
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
            {"region": region, "name": name, "ratePercent": rate, "note": note,
             "sourceTitle": title, "sourceURL": url}
            for region, name, rate, note, title, url in PRESETS
        ],
    }
    data = json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False).encode("utf-8") + b"\n"
    with open(os.path.join(OUT_DIR, "tax-presets.json"), "wb") as fh:
        fh.write(data)
    digest = hashlib.sha256(data).hexdigest()
    missing = [p["region"] for p in payload["presets"]
               if not p["sourceTitle"] or not p["sourceURL"].startswith("https://")]
    if missing:
        raise SystemExit(f"presets missing official HTTPS provenance: {missing}")
    manifest = {
        "version": VERSION,
        "snapshotDate": SNAPSHOT,
        "attribution": payload["attribution"],
        "license": payload["license"],
        "generator": "Scripts/generate-tax-presets.py",
        "sources": {p["region"]: {"title": p["sourceTitle"], "url": p["sourceURL"]}
                    for p in payload["presets"]},
        "resources": {"tax-presets.json": {"sha256": digest}},
    }
    with open(os.path.join(OUT_DIR, "sources.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {len(PRESETS)} tax presets, sha256={digest}")


if __name__ == "__main__":
    main()
