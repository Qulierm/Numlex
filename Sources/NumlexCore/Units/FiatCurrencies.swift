// Bundled fiat currency code catalog (ISO 4217 active codes as
// published by open.er-api.com, fetched 2026-08-26).
//
// Fiat only: the provider free open endpoint excludes
// cryptocurrencies and precious metals, matching the approved
// scope. Codes double as unit ids, labels and input aliases;
// the live rate table (Rates) is keyed by these same codes.

public enum FiatCurrencies {

    /// All supported ISO currency codes (stable sorted order).
    public static let codes: [String] = [
        "AED", "AFN", "ALL", "AMD", "ANG", "AOA",
        "ARS", "AUD", "AWG", "AZN", "BAM", "BBD",
        "BDT", "BGN", "BHD", "BIF", "BMD", "BND",
        "BOB", "BRL", "BSD", "BTN", "BWP", "BYN",
        "BZD", "CAD", "CDF", "CHF", "CLF", "CLP",
        "CNH", "CNY", "COP", "CRC", "CUP", "CVE",
        "CZK", "DJF", "DKK", "DOP", "DZD", "EGP",
        "ERN", "ETB", "EUR", "FJD", "FKP", "FOK",
        "GBP", "GEL", "GGP", "GHS", "GIP", "GMD",
        "GNF", "GTQ", "GYD", "HKD", "HNL", "HRK",
        "HTG", "HUF", "IDR", "ILS", "IMP", "INR",
        "IQD", "IRR", "ISK", "JEP", "JMD", "JOD",
        "JPY", "KES", "KGS", "KHR", "KID", "KMF",
        "KRW", "KWD", "KYD", "KZT", "LAK", "LBP",
        "LKR", "LRD", "LSL", "LYD", "MAD", "MDL",
        "MGA", "MKD", "MMK", "MNT", "MOP", "MRU",
        "MUR", "MVR", "MWK", "MXN", "MYR", "MZN",
        "NAD", "NGN", "NIO", "NOK", "NPR", "NZD",
        "OMR", "PAB", "PEN", "PGK", "PHP", "PKR",
        "PLN", "PYG", "QAR", "RON", "RSD", "RUB",
        "RWF", "SAR", "SBD", "SCR", "SDG", "SEK",
        "SGD", "SHP", "SLE", "SLL", "SOS", "SRD",
        "SSP", "STN", "SYP", "SZL", "THB", "TJS",
        "TMT", "TND", "TOP", "TRY", "TTD", "TVD",
        "TWD", "TZS", "UAH", "UGX", "USD", "UYU",
        "UZS", "VES", "VND", "VUV", "WST", "XAF",
        "XCD", "XCG", "XDR", "XOF", "XPF", "YER",
        "ZAR", "ZMW", "ZWG", "ZWL",
    ]

    /// The default base code used when no base is set: US dollar.
    public static let defaultBase: String = "USD"
}
