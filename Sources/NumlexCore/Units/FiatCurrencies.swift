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

    /// User-facing English names for the major currencies (singular and
    /// plural; qualified forms where a bare name would be ambiguous).
    /// Deliberately EXCLUDED to keep the unit grammar honest: bare
    /// `pound` (collides with the mass pound), bare `peso`, `franc`,
    /// `dinar`, `riyal`, `shilling`, `rupee` (each names several
    /// distinct currencies) and bare `dollar` for anything other than
    /// USD (bare `dollar` is deliberately the US dollar). Keys are the
    /// canonical codes; `UnitCatalog` registers `[code] + aliases`.
    public static let aliases: [String: [String]] = [
        "USD": ["US dollar", "US dollars", "American dollar", "American dollars",
                "dollar", "dollars"],
        "EUR": ["euro", "euros", "european euro", "european euros"],
        "GBP": ["British pound", "British pounds", "pound sterling", "sterling"],
        "JPY": ["Japanese yen", "yen"],
        "CNY": ["Chinese yuan", "yuan", "renminbi", "RMB"],
        "CHF": ["Swiss franc", "Swiss francs"],
        "CAD": ["Canadian dollar", "Canadian dollars"],
        "AUD": ["Australian dollar", "Australian dollars"],
        "NZD": ["New Zealand dollar", "New Zealand dollars"],
        "HKD": ["Hong Kong dollar", "Hong Kong dollars"],
        "SGD": ["Singapore dollar", "Singapore dollars"],
        "INR": ["Indian rupee", "Indian rupees", "rupee", "rupees"],
        "KRW": ["South Korean won", "Korean won", "won"],
        "BRL": ["Brazilian real", "Brazilian reais", "reais"],
        "MXN": ["Mexican peso", "Mexican pesos"],
        "PLN": ["Polish zloty", "Polish zlotys", "zloty", "zlotys"],
        "CZK": ["Czech koruna", "koruna"],
        "HUF": ["Hungarian forint", "forint"],
        "RON": ["Romanian leu", "leu"],
        "BGN": ["Bulgarian lev", "lev"],
        "TRY": ["Turkish lira", "lira", "liras"],
        "UAH": ["Ukrainian hryvnia", "hryvnia"],
        "RUB": ["Russian ruble", "Russian rubles", "ruble", "rubles",
                "rouble", "roubles"],
        "ILS": ["Israeli new shekel", "Israeli new shekels",
                "new shekel", "new shekels", "shekel", "shekels"],
        "AED": ["UAE dirham", "UAE dirhams", "dirham", "dirhams"],
        "SAR": ["Saudi riyal", "Saudi riyals"],
        "QAR": ["Qatari riyal", "Qatari riyals"],
        "KWD": ["Kuwaiti dinar", "Kuwaiti dinars"],
        "BHD": ["Bahraini dinar", "Bahraini dinars"],
        "JOD": ["Jordanian dinar", "Jordanian dinars"],
        "EGP": ["Egyptian pound", "Egyptian pounds"],
        "ZAR": ["South African rand", "rand"],
        "NGN": ["Nigerian naira", "naira"],
        "KES": ["Kenyan shilling", "Kenyan shillings"],
        "GHS": ["Ghanaian cedi", "cedi"],
        "THB": ["Thai baht", "baht"],
        "VND": ["Vietnamese dong", "dong"],
        "PHP": ["Philippine peso", "Philippine pesos"],
        "IDR": ["Indonesian rupiah", "rupiah"],
        "MYR": ["Malaysian ringgit", "ringgit"],
        "TWD": ["New Taiwan dollar", "New Taiwan dollars"],
        "PKR": ["Pakistani rupee", "Pakistani rupees"],
        "BDT": ["Bangladeshi taka", "taka"],
        "KZT": ["Kazakhstani tenge", "tenge"],
        "GEL": ["Georgian lari", "lari"],
        "CLP": ["Chilean peso", "Chilean pesos"],
        "COP": ["Colombian peso", "Colombian pesos"],
        "ARS": ["Argentine peso", "Argentine pesos"],
        "PEN": ["Peruvian sol", "Peruvian soles", "sol", "soles"],
    ]
}
