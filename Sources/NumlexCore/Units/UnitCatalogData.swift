import Foundation

/// Dimension-vector shorthand for the catalog data.
private extension DimensionVector {
    static let L = DimensionVector(l: 1)
    static let M = DimensionVector(m: 1)
    static let T = DimensionVector(t: 1)
    static let A = DimensionVector(a: 1)
    static let I = DimensionVector(i: 1)
    static let L2 = DimensionVector(l: 2)
    static let L3 = DimensionVector(l: 3)
    static let T1 = DimensionVector(t: -1)
    static let T2 = DimensionVector(t: -2)
    static let T3 = DimensionVector(t: -3)
    static let LT = DimensionVector(l: 1, t: -1)
    static let L2T2 = DimensionVector(l: 2, t: -2)
    static let MLT2 = DimensionVector(l: 1, m: 1, t: -2)
    static let ML2T2 = DimensionVector(l: 2, m: 1, t: -2)
    static let MPerLT2 = DimensionVector(l: -1, m: 1, t: -2)
    static let L3T1 = DimensionVector(l: 3, t: -1)
    static let T1A1 = DimensionVector(t: 1, a: 1)
    static let ML2T3 = DimensionVector(l: 2, m: 1, t: -3)
    static let ML2T3A1 = DimensionVector(l: 2, m: 1, t: -3, a: -1)
    static let ML2T3A2 = DimensionVector(l: 2, m: 1, t: -3, a: -2)
    static let T4A2ML2 = DimensionVector(l: -2, m: -1, t: 4, a: 2)
    static let ML2T2A2 = DimensionVector(l: 2, m: 1, t: -2, a: -2)
    static let T3A2ML2 = DimensionVector(l: -2, m: -1, t: 3, a: 2)
    static let ML2T2A1 = DimensionVector(l: 2, m: 1, t: -2, a: -1)
    static let MT2A1 = DimensionVector(m: 1, t: -2, a: -1)
    static let IPerL2 = DimensionVector(l: -2, i: 1)
    /// Dynamic viscosity M/(L·T) — Pa·s base (no existing owner).
    static let MPerLT1 = DimensionVector(l: -1, m: 1, t: -1)
    /// Kinematic viscosity L²/T — m²/s base (no existing owner).
    static let L2T1 = DimensionVector(l: 2, t: -1)
}

extension UnitCatalog {

    /// The complete data-driven catalog. Registration order matters:
    /// the case-folded fallback keeps the FIRST registered owner when a
    /// folded form is unambiguous.
    static let allUnits: [UnitDef] = {
        var u: [UnitDef] = []
        func lin(_ id: String, _ v: DimensionVector, _ f: Double, _ label: String,
                 _ aliases: [String], _ prefixes: [String] = [],
                 family: UnitFamily = .none) {
            u.append(UnitDef(id: id, kind: .factor(v, f), label: label,
                             family: family, aliases: aliases, prefixes: prefixes))
        }
        func special(_ id: String, _ kind: UnitKind, _ label: String,
                     _ aliases: [String], _ family: UnitFamily = .none) {
            u.append(UnitDef(id: id, kind: kind, label: label,
                             family: family, aliases: aliases, prefixes: []))
        }

        // MARK: Length (base m)
        lin("meter", .L, 1, "m",
            ["m", "meter", "meters", "metre", "metres"],
            ["p", "n", "µ", "m", "c", "d", "k", "K", "M", "G", "T"])
        lin("kilometer", .L, 1000, "km",
            ["km", "kilometer", "kilometers"], [])
        lin("inch", .L, 0.0254, "in", ["in", "inch", "inches", "in."], [])
        lin("foot", .L, 0.3048, "ft", ["ft", "foot", "feet"], [])
        lin("yard", .L, 0.9144, "yd", ["yd", "yard", "yards"], [])
        lin("mile", .L, 1609.344, "mi", ["mi", "mile", "miles"], [])
        lin("nautical-mile", .L, 1852, "nmi",
            ["nmi", "nautical mile", "international nautical mile"], [])
        lin("mil", .L, 2.54e-5, "mil", ["mil", "mils", "thou", "thous"], [])
        lin("astronomical-unit", .L, 149597870700, "AU",
            ["AU", "au", "astronomical unit"], [])
        lin("light-year", .L, 9460730472580800, "ly",
            ["ly", "light year", "light-year"], [])
        lin("parsec", .L, 3.0856775814913673e16, "pc",
            ["pc", "parsec", "parsecs"], [])
        lin("angstrom", .L, 1e-10, "Å",
            ["Å", "angstrom", "angstroms"], [])
        lin("micron", .L, 1e-6, "µm",
            ["µm", "micron", "microns"], [])
        lin("hand", .L, 0.1016, "hand", ["hand", "hands"], [])
        // US survey foot: the legal foot 1200/3937 m (NOT 0.3048).
        lin("us-survey-foot", .L, 1200.0 / 3937.0, "US ft",
            ["US ft", "us survey foot", "survey foot"], [])
        lin("fathom", .L, 1.8288, "fathom", ["fathom", "fathoms"], [])
        lin("rod", .L, 5.0292, "rod", ["rod", "rods", "pole", "poles"], [])
        lin("chain", .L, 20.1168, "chain", ["chain", "chains"], [])
        lin("furlong", .L, 201.168, "furlong", ["furlong", "furlongs", "fur"], [])
        // Typographic point — the label is qualified so it never
        // collides with the US pint `pt`.
        lin("type-point", .L, 0.0254 / 72.0, "pt (type)",
            ["pt (type)", "typographic point", "type point"], [])
        lin("pica", .L, 0.0254 / 6.0, "pica", ["pica", "picas", "type pica"], [])

        // MARK: Area (base m²)
        lin("sq-meter", .L2, 1, "m²",
            ["m²", "m2", "square meter", "square metre", "sq m", "sqm"],
            ["m", "c", "k", "K", "M"])
        lin("hectare", .L2, 10_000, "ha", ["ha", "hectare", "hectares"], [])
        lin("acre", .L2, 4046.8564224, "acre", ["acre", "acres"], [])
        lin("sq-foot", .L2, 0.09290304, "ft²",
            ["ft²", "ft2", "square foot", "square feet", "sq ft", "sqft"], [])
        lin("sq-inch", .L2, 0.00064516, "in²",
            ["in²", "in2", "square inch", "sq in"], [])
        lin("sq-yard", .L2, 0.83612736, "yd²",
            ["yd²", "yd2", "square yard"], [])
        lin("sq-mile", .L2, 2_589_988.110336, "mi²",
            ["mi²", "mi2", "square mile"], [])
        lin("are", .L2, 100, "are", ["are"], [])
        lin("rood", .L2, 1011.7141056, "rood", ["rood", "roods"], [])
        lin("barn", .L2, 1e-28, "barn", ["barn", "barns"], [])
        lin("section", .L2, 2_589_988.110336, "section",
            ["section", "sections"], [])

        // MARK: Volume (base m³)
        lin("liter", .L3, 0.001, "L",
            ["L", "l", "liter", "litre", "liters", "litres"],
            ["µ", "c", "d", "k", "K"])
        lin("milliliter", .L3, 1e-6, "ml",
            ["ml", "mL", "milliliter", "milliliters"], [])
        lin("cubic-meter", .L3, 1, "m³",
            ["m³", "m3", "cubic meter", "cubic metre"],
            ["k", "K", "M"])
        lin("cubic-inch", .L3, 1.6387064e-5, "in³",
            ["in³", "in3", "cubic inch"], [])
        lin("cubic-foot", .L3, 0.028316846592, "ft³",
            ["ft³", "ft3", "cubic foot", "cubic feet"], [])
        lin("cubic-yard", .L3, 0.764554857984, "yd³",
            ["yd³", "yd3", "cubic yard"], [])
        lin("us-teaspoon", .L3, 4.92892159375e-6, "tsp",
            ["tsp", "teaspoon", "teaspoons", "us teaspoon"], [])
        lin("metric-teaspoon", .L3, 0.000005, "metric tsp",
            ["metric teaspoon", "metric tsp"], [])
        lin("us-tablespoon", .L3, 1.478676478125e-5, "tbsp",
            ["tbsp", "tablespoon", "tablespoons", "us tablespoon"], [])
        lin("us-fluid-ounce", .L3, 2.95735295625e-5, "fl oz",
            ["fl oz", "us fl oz", "us fluid ounce", "fluid ounce"], [])
        lin("us-cup", .L3, 0.0002365882365, "cup",
            ["cup", "cups", "us cup"], [])
        lin("us-pint", .L3, 0.000473176473, "pt",
            ["pt", "pint", "pints", "us pint"], [])
        lin("us-quart", .L3, 0.000946352946, "qt",
            ["qt", "quart", "quarts", "us quart"], [])
        lin("us-gallon", .L3, 0.003785411784, "gal",
            ["gal", "gallon", "gallons", "us gallon"], [])
        lin("uk-fluid-ounce", .L3, 2.84130625e-5, "uk fl oz",
            ["uk fl oz", "imperial fluid ounce", "uk fluid ounce"], [])
        lin("uk-pint", .L3, 0.00056826125, "uk pt",
            ["uk pt", "imperial pint", "uk pint"], [])
        lin("uk-quart", .L3, 0.0011365225, "uk qt",
            ["uk qt", "imperial quart", "uk quart"], [])
        lin("uk-gallon", .L3, 0.00454609, "uk gal",
            ["uk gal", "uk_gal", "imperial gallon", "imperial gallons", "uk gallon"], [])
        lin("metric-cup", .L3, 0.00025, "metric cup",
            ["metric cup", "metric cups"], [])
        lin("metric-tablespoon", .L3, 15e-6, "metric tbsp",
            ["metric tablespoon", "metric tablespoons"], [])
        lin("imperial-tablespoon", .L3, 17.7581640625e-6, "imp tbsp",
            ["imperial tablespoon", "imperial tablespoons", "uk tablespoon"], [])
        lin("dessertspoon", .L3, 10e-6, "dessertspoon",
            ["dessertspoon", "dessertspoons", "dsp"], [])
        lin("us-fluid-dram", .L3, 3.6966911953125e-6, "US fl dr",
            ["us fluid dram", "fluid dram"], [])
        lin("us-oil-barrel", .L3, 0.158987294928, "bbl",
            ["bbl", "barrel", "barrels", "us oil barrel", "oil barrel", "petroleum barrel"], [])
        lin("us-bushel", .L3, 0.03523907016688, "bushel",
            ["bushel", "bushels", "us bushel"], [])
        lin("us-peck", .L3, 0.00880976754172, "peck",
            ["peck", "pecks", "us peck"], [])

        // MARK: Mass (base kg)
        lin("gram", .M, 0.001, "g",
            ["g", "gram", "grams"],
            ["p", "n", "µ", "m", "c", "d", "k", "K"])
        lin("kilogram", .M, 1, "kg",
            ["kg", "kilogram", "kilograms"], [])
        lin("tonne", .M, 1000, "t",
            ["t", "tonne", "tonnes", "metric ton", "ton"], [])
        lin("grain", .M, 6.479891e-5, "grain", ["grain", "grains", "gr"], [])
        lin("carat", .M, 0.0002, "ct", ["ct", "carat", "carats", "karat"], [])
        lin("ounce", .M, 0.028349523125, "oz",
            ["oz", "ounce", "ounces", "avoirdupois ounce"], [])
        lin("pound", .M, 0.45359237, "lb",
            ["lb", "pound", "pounds", "pound avoirdupois"], [])
        lin("stone", .M, 6.35029318, "st", ["st", "stone", "stones"], [])
        lin("short-ton", .M, 907.18474, "short ton",
            ["short ton", "us ton", "short tons", "shortton"], [])
        lin("long-ton", .M, 1016.0469088, "long ton",
            ["long ton", "uk ton", "long tons", "longton", "british ton"], [])
        // Bare `oz`/`pound` stay avoirdupois; troy is qualified only.
        lin("dalton", .M, 1.66053906660e-27, "Da",
            ["Da", "dalton", "daltons", "amu", "atomic mass unit",
             "unified atomic mass unit"], [])
        lin("slug", .M, 14.59390293720636, "slug", ["slug", "slugs"], [])
        lin("quintal", .M, 100, "quintal", ["quintal", "quintals"], [])
        lin("us-hundredweight", .M, 45.359237, "cwt (US)",
            ["us hundredweight", "us cwt", "short hundredweight"], [])
        lin("uk-hundredweight", .M, 50.80234544, "cwt (UK)",
            ["uk hundredweight", "uk cwt", "long hundredweight",
             "imperial hundredweight"], [])
        lin("troy-ounce", .M, 0.0311034768, "oz t",
            ["oz t", "ozt", "troy ounce", "troy ounces"], [])
        lin("pennyweight", .M, 0.00155517384, "dwt",
            ["dwt", "pennyweight", "pennyweights"], [])

        // MARK: Temperature (affine; base kelvin)
        special("celsius", .temperature(.celsius), "C°",
                ["c", "C", "°c", "celsius", "c°"])
        special("fahrenheit", .temperature(.fahrenheit), "F°",
                ["f", "F", "°f", "fahrenheit", "f°"])
        special("kelvin", .temperature(.kelvin), "K°",
                ["k", "K", "°k", "kelvin", "k°"])
        special("rankine", .temperature(.rankine), "R°",
                ["r", "R", "°r", "rankine", "r°"])

        // MARK: Time (base s)
        lin("second", .T, 1, "s",
            ["s", "second", "seconds", "sec", "secs"],
            ["n", "µ", "m"])
        lin("millisecond", .T, 1e-3, "ms",
            ["ms", "millisecond", "milliseconds"], [])
        lin("minute", .T, 60, "min", ["min", "minute", "minutes"], [])
        lin("hour", .T, 3600, "h", ["h", "hour", "hours", "hr", "hrs"], [])
        lin("day", .T, 86_400, "day", ["day", "days"], [])
        lin("week", .T, 604_800, "week", ["week", "weeks", "wk"], [])
        lin("fortnight", .T, 1_209_600, "fortnight",
            ["fortnight", "fortnights", "fn"], [])
        lin("julian-year", .T, 31_557_600, "jyear",
            ["jyear", "julian year", "jy"], [])
        // Calendar AVERAGES (documented): the Gregorian average year is
        // 365.2425 days, the average Gregorian month a quarter of it.
        // The Julian year stays a distinct unit.
        lin("gregorian-year", .T, 31_556_952, "yr",
            ["yr", "year", "years", "gregorian year", "average year",
             "average gregorian year"], [])
        lin("average-month", .T, 2_629_746, "mo",
            ["mo", "month", "months", "average month",
             "average gregorian month"], [])
        lin("common-year", .T, 31_536_000, "common year",
            ["common year", "common year (365 days)"], [])
        lin("average-quarter", .T, 7_889_238, "quarter (time)",
            ["quarter (time)", "average quarter"], [])

        // MARK: Speed (base m/s)
        lin("m-per-s", .LT, 1, "m/s",
            ["m/s", "meters per second"], ["k", "K", "M"])
        lin("km-per-h", .LT, 1.0 / 3.6, "km/h",
            ["km/h", "kph", "kmh", "kilometers per hour", "kilometres per hour"], [])
        lin("mph", .LT, 0.44704, "mph",
            ["mph", "miles per hour", "mi/h"], [])
        lin("ft-per-s", .LT, 0.3048, "ft/s",
            ["ft/s", "feet per second"], [])
        lin("knot", .LT, 1852.0 / 3600, "kn", ["kn", "knot", "knots"], [])
        // Exact SI: 299 792 458 m/s.
        lin("speed-of-light", .LT, 299_792_458, "c₀",
            ["c₀", "c0", "speed of light"], [])
        // Standard Mach: 340.29 m/s (sea level, 15 °C ISA assumption).
        lin("mach", .LT, 340.29, "Mach",
            ["Mach", "standard mach", "mach number"], [])

        // MARK: Acceleration (base m/s²)
        lin("m-per-s2", .L2T2, 1, "m/s²",
            ["m/s²", "m/s2", "meters per second squared"], ["k", "K"])
        lin("ft-per-s2", .L2T2, 0.3048, "ft/s²",
            ["ft/s²", "ft/s2", "feet per second squared"], [])
        lin("standard-gravity", .L2T2, 9.80665, "g₀",
            ["standard gravity", "g0", "gn", "gravity", "g-force", "gforce"], [])
        lin("km-per-h-s", .L2T2, 1.0 / 3.6, "km/h/s",
            ["km/h/s", "kph/s", "kilometers per hour per second"], [])

        // MARK: Angle (dimensionless, family angle; base rad)
        lin("radian", .zero, 1, "rad", ["rad", "radian", "radians"], [], family: .angle)
        lin("degree", .zero, Double.pi / 180, "deg",
            ["deg", "degree", "degrees", "°"], [], family: .angle)
        lin("gradian", .zero, Double.pi / 200, "grad",
            ["grad", "gradian", "grads", "gon"], [], family: .angle)
        lin("turn", .zero, 2 * Double.pi, "turn",
            ["turn", "turns", "revolution", "revolutions", "rev", "cycle", "cycles"], [], family: .angle)
        lin("arcmin", .zero, Double.pi / 10_800, "arcmin",
            ["arcmin", "arc minute", "arcminutes", "minute of arc", "′"], [], family: .angle)
        lin("arcsec", .zero, Double.pi / 648_000, "arcsec",
            ["arcsec", "arc second", "arcseconds", "second of arc", "″"], [], family: .angle)

        // MARK: Pressure (base Pa)
        lin("pascal", .MPerLT2, 1, "Pa",
            ["Pa", "pascal", "pascals"],
            ["µ", "m", "c", "k", "K", "M", "G"])
        lin("hectopascal", .MPerLT2, 100, "hPa",
            ["hPa", "hectopascal", "hectopascals"], [])
        lin("bar", .MPerLT2, 100_000, "bar", ["bar", "bars"], ["m"])
        lin("atmosphere", .MPerLT2, 101_325, "atm",
            ["atm", "atmosphere", "atmospheres", "standard atmosphere"], [])
        lin("torr", .MPerLT2, 101_325.0 / 760, "torr",
            ["torr", "torrs", "mmhg", "mm hg"], [])
        lin("psi", .MPerLT2, 6894.757293168, "psi",
            ["psi", "lbf/in²", "pounds per square inch", "pound per square inch"], [])
        lin("ksi", .MPerLT2, 6_894_757.293168, "ksi",
            ["ksi", "kip per square inch"], [])
        lin("inhg", .MPerLT2, 3386.389, "inHg",
            ["inHg", "in hg", "inches of mercury"], [])
        // Technical atmosphere (at): 1 kgf/cm² exactly 98 066.5 Pa.
        lin("techn-atm", .MPerLT2, 98_066.5, "at",
            ["at", "technical atmosphere", "techn atm"], [])
        lin("kgf-per-cm2", .MPerLT2, 98_066.5, "kgf/cm²",
            ["kgf/cm²", "kgf/cm2", "kilogram force per square centimeter"], [])
        lin("mm-h2o", .MPerLT2, 9.80665, "mmH2O",
            ["mmH2O", "mm h2o", "millimeter of water"], [])
        lin("cm-h2o", .MPerLT2, 98.0665, "cmH2O",
            ["cmH2O", "cm h2o", "centimeter of water"], [])
        lin("psf", .MPerLT2, 47.88025898033584, "psf",
            ["psf", "pound per square foot"], [])

        // MARK: Force (base N)
        lin("newton", .MLT2, 1, "N",
            ["N", "newton", "newtons"],
            ["µ", "m", "c", "k", "K", "M", "G"])
        lin("dyne", .MLT2, 1e-5, "dyne", ["dyne", "dynes"], [])
        lin("lbf", .MLT2, 4.4482216152605, "lbf",
            ["lbf", "pound force", "pound-force", "lb force"], [])
        lin("kgf", .MLT2, 9.80665, "kgf",
            ["kgf", "kilogram force", "kilogram-force", "kp"], [])
        lin("ounce-force", .MLT2, 0.27801385095378125, "ozf",
            ["ozf", "ounce force", "ounce-force"], [])
        lin("kip", .MLT2, 4448.2216152605, "kip", ["kip", "kips", "kilopound"], [])
        lin("poundal", .MLT2, 0.138254954376, "poundal",
            ["poundal", "poundals", "pdl"], [])
        lin("us-ton-force", .MLT2, 8896.443230521, "tonf (US)",
            ["us ton force", "us ton-force", "short ton force"], [])
        lin("tonne-force", .MLT2, 9806.65, "tonf (t)",
            ["tonne force", "tonne-force", "tf", "metric ton force"], [])

        // MARK: Torque (base N·m; family torque — never joules)
        lin("newton-meter", .ML2T2, 1, "N·m",
            ["N·m", "N m", "N*m"], [], family: .torque)
        lin("lbf-foot", .ML2T2, 1.3558179483314004, "lbf·ft",
            ["lbf·ft", "lbf ft", "lb-ft"], [], family: .torque)
        lin("lbf-inch", .ML2T2, 0.1129848290276167, "lbf·in",
            ["lbf·in", "lbf in", "lb-in"], [], family: .torque)
        lin("kgf-meter", .ML2T2, 9.80665, "kgf·m",
            ["kgf·m", "kgf m", "kgf*m"], [], family: .torque)
        lin("newton-centimeter", .ML2T2, 0.01, "N·cm",
            ["N·cm", "N cm", "N*cm", "newton centimeter"], [], family: .torque)
        lin("newton-millimeter", .ML2T2, 0.001, "N·mm",
            ["N·mm", "N mm", "N*mm", "newton millimeter"], [], family: .torque)
        // ozf·in = ounce-force × inch, exact product of the declared
        // factors (kept in step with `ounce-force` and `inch`).
        lin("ozf-inch", .ML2T2, 0.27801385095378125 * 0.0254, "ozf·in",
            ["ozf·in", "ozf in", "oz-in", "ounce force inch"], [], family: .torque)

        // MARK: Energy (base J; family energy — never N·m)
        lin("joule", .ML2T2, 1, "J",
            ["J", "joule", "joules"],
            ["m", "µ", "k", "K", "M", "G", "T"], family: .energy)
        lin("watt-hour", .ML2T2, 3600, "Wh",
            ["Wh", "watt hour", "watt-hour", "watt hours"], [], family: .energy)
        lin("kilowatt-hour", .ML2T2, 3.6e6, "kWh",
            ["kWh", "kilowatt hour", "kilowatt-hour"], [], family: .energy)
        lin("megawatt-hour", .ML2T2, 3.6e9, "MWh",
            ["MWh", "megawatt hour"], [], family: .energy)
        lin("gigawatt-hour", .ML2T2, 3.6e12, "GWh",
            ["GWh", "gigawatt hour"], [], family: .energy)
        lin("calorie", .ML2T2, 4.184, "cal",
            ["cal", "calorie", "calories"], ["k", "K"], family: .energy)
        lin("kilocalorie", .ML2T2, 4184, "kcal",
            ["kcal", "kilocalorie", "kilocalories", "Calorie", "Calories", "big calorie"], [], family: .energy)
        lin("btu", .ML2T2, 1055.05585262, "BTU",
            ["BTU", "btu", "BTUs", "british thermal unit"], [], family: .energy)
        lin("therm", .ML2T2, 1.05505585262e8, "therm",
            ["therm", "therms", "us therm"], [], family: .energy)
        lin("ft-lbf", .ML2T2, 1.3558179483314004, "ft·lbf",
            ["ft·lbf", "ft lbf", "foot pound force", "foot-pound force", "ftlbf"], [], family: .energy)
        lin("electronvolt", .ML2T2, 1.602176634e-19, "eV",
            ["eV", "electronvolt", "electron volt"],
            ["M", "G", "T"], family: .energy)
        lin("erg", .ML2T2, 1e-7, "erg", ["erg", "ergs"], [], family: .energy)
        lin("ton-tnt", .ML2T2, 4.184e9, "t TNT",
            ["t TNT", "ton TNT", "tonne TNT", "ton of TNT"], [], family: .energy)
        lin("quad", .ML2T2, 1.05505585262e18, "quad",
            ["quad", "quads", "quadrillion BTU"], [], family: .energy)
        // Mechanical horsepower-hour = 745.6998715822702 W × 3600 s.
        lin("horsepower-hour", .ML2T2, 745.6998715822702 * 3600.0, "hph",
            ["hph", "horsepower hour", "mechanical horsepower hour"],
            [], family: .energy)
        lin("tonne-oil-equivalent", .ML2T2, 41.868e9, "toe",
            ["toe", "tonne of oil equivalent", "ton oil equivalent"],
            [], family: .energy)

        // MARK: Power (base W)
        lin("watt", .ML2T3, 1, "W",
            ["W", "watt", "watts"],
            ["m", "µ", "k", "K", "M", "G", "T"])
        lin("horsepower", .ML2T3, 745.6998715822702, "hp",
            ["hp", "horsepower", "horse power", "mechanical horsepower", "imperial horsepower"], [])
        lin("metric-horsepower", .ML2T3, 735.49875, "metric hp",
            ["metric hp", "metric horsepower", "cv", "ps", "pferd"], [])
        lin("btu-per-h", .ML2T3, 0.29307107017, "BTU/h",
            ["BTU/h", "btu/h", "btuh", "btu per hour"], [])
        lin("electric-horsepower", .ML2T3, 746, "hp (electric)",
            ["electric horsepower", "electric hp", "US horsepower"], [])
        lin("boiler-horsepower", .ML2T3, 9809.5, "hp (boiler)",
            ["boiler horsepower", "boiler hp"], [])
        lin("ton-refrigeration", .ML2T3, 3516.8528420667, "TR",
            ["TR", "ton refrigeration", "ton of refrigeration"], [])

        // MARK: Frequency (base Hz; plain 1/T — not activity)
        lin("hertz", .T1, 1, "Hz", ["Hz", "hertz"],
            ["k", "K", "M", "G"])
        lin("rpm", .T1, 1.0 / 60, "rpm",
            ["rpm", "r/min", "revolutions per minute", "rev per minute"], [])
        lin("bpm", .T1, 1.0 / 60, "bpm", ["bpm", "beats per minute"], [])

        // MARK: Data (dimensionless, family data; base bit)
        lin("bit", .zero, 1, "bit",
            ["bit", "bits", "b"],
            ["k", "K", "M", "G", "T", "P"], family: .data)
        lin("byte", .zero, 8, "B",
            ["B", "byte", "bytes"],
            ["k", "K", "M", "G", "T", "P"], family: .data)
        lin("kibibyte", .zero, 8192, "KiB",
            ["KiB", "kibibyte", "kibibytes"], [], family: .data)
        lin("mebibyte", .zero, 8_388_608, "MiB",
            ["MiB", "mebibyte", "mebibytes"], [], family: .data)
        lin("gibibyte", .zero, 8_589_934_592, "GiB",
            ["GiB", "gibibyte", "gibibytes"], [], family: .data)
        lin("tebibyte", .zero, 1_099_511_627_776, "TiB",
            ["TiB", "tebibyte", "tebibytes"], [], family: .data)
        lin("pebibyte", .zero, 1_125_899_906_842_624, "PiB",
            ["PiB", "pebibyte", "pebibytes"], [], family: .data)
        lin("kibibit", .zero, 1024, "Kib",
            ["Kib", "kibibit", "kibibits"], [], family: .data)
        lin("mebibit", .zero, 1_048_576, "Mib",
            ["Mib", "mebibit", "mebibits"], [], family: .data)
        lin("gibibit", .zero, 1_073_741_824, "Gib",
            ["Gib", "gibibit", "gibibits"], [], family: .data)
        lin("tebibit", .zero, 1_099_511_627_776, "Tib",
            ["Tib", "tebibit", "tebibits"], [], family: .data)
        lin("pebibit", .zero, 1_125_899_906_842_624, "Pib",
            ["Pib", "pebibit", "pebibits"], [], family: .data)

        // MARK: Data rate (base bit/s; family data)
        lin("bit-per-s", .T1, 1, "bit/s",
            ["bit/s", "bps", "bits per second", "b/s"],
            ["k", "K", "M", "G", "T"], family: .data)
        lin("byte-per-s", .T1, 8, "B/s",
            ["B/s", "bytes per second", "BPS"],
            ["k", "K", "M", "G", "T"], family: .data)

        // MARK: Volumetric flow (base m³/s)
        lin("liter-per-s", .L3T1, 0.001, "L/s",
            ["L/s", "liters per second", "litres per second"],
            ["m", "k", "K"])
        lin("liter-per-min", .L3T1, 0.001 / 60, "L/min",
            ["L/min", "liters per minute"], [])
        lin("liter-per-h", .L3T1, 0.001 / 3600, "L/h",
            ["L/h", "liters per hour"], [])
        lin("m3-per-s", .L3T1, 1, "m³/s",
            ["m³/s", "m3/s", "cubic meters per second"], [])
        lin("m3-per-h", .L3T1, 1.0 / 3600, "m³/h",
            ["m³/h", "m3/h", "cubic meters per hour"], [])
        lin("gpm", .L3T1, 0.003785411784 / 60, "gpm",
            ["gpm", "us gpm", "us gallons per minute"], [])
        lin("cfs", .L3T1, 0.028316846592, "cfs",
            ["cfs", "cubic feet per second"], [])
        lin("uk-gpm", .L3T1, 0.00454609 / 60.0, "UK gpm",
            ["uk gpm", "imperial gpm", "imperial gallons per minute"], [])
        lin("cfm", .L3T1, 0.028316846592 / 60.0, "cfm",
            ["cfm", "cubic feet per minute", "ft³/min"], [])
        lin("us-mgd", .L3T1, 0.003785411784 * 1e6 / 86400.0, "US mgd",
            ["us mgd", "million gallons per day"], [])
        lin("bbl-per-d", .L3T1, 0.158987294928 / 86400.0, "bbl/d",
            ["bbl/d", "barrels per day", "oil barrel per day"], [])

        // MARK: Fuel economy (pseudo-dimension L/m base)
        // reciprocal=false: consumption form (value × factor = L/m).
        // reciprocal=true: economy form (1 / (value × factor) = L/m).
        special("l100km", .fuel(factor: 1e-5, reciprocal: false), "L/100km",
                ["l/100km", "L per 100 km", "l per 100km",
                 "liters per 100 km", "litres per 100 km"], .fuel)
        special("lkm", .fuel(factor: 1e-3, reciprocal: false), "L/km",
                ["l/km", "L per km", "l per km", "liters per km", "litres per km"], .fuel)
        // Economy (reciprocal) factors are m PER LITER of fuel:
        // 1 km/L = 1000 m/L, 1 US mpg = 1609.344/3.785411784 m/L,
        // 1 UK mpg = 1609.344/4.54609 m/L.
        special("kml", .fuel(factor: 1000, reciprocal: true), "km/L",
                ["km/l", "km per liter", "km per litre", "kmpl"], .fuel)
        special("mpg-us", .fuel(factor: 425.143707430272, reciprocal: true),
                "US mpg",
                ["mpg", "us mpg", "mpg (us)", "us_mpg", "mpg_us", "usmpg"], .fuel)
        // Fuel crossing convention: economy factors = meters per liter
        // (km/L = 1000, US mpg = 425.1437…), consumption factors =
        // liters per meter (L/km = 0.001, L/100km = 1e-5).
        // UK mpg = 1609.344/4.54609 m/L.
        special("mpg-uk", .fuel(factor: 354.0061899346471, reciprocal: true),
                "UK mpg",
                ["uk mpg", "mpg (uk)", "uk_mpg", "mpg_uk", "ukmpg",
                 "imperial mpg", "miles per imperial gallon"], .fuel)
        // miles/L economy (1 mile = 1609.344 m per liter).
        special("miles-per-liter", .fuel(factor: 1609.344, reciprocal: true),
                "mi/L", ["mi/l", "miles per liter", "miles per litre"], .fuel)
        // Consumption forms (L/m). Crossings are exact by construction:
        // 1 US mpg = exactly 100 US gal/100mi, and the UK analogue
        // (100 miles = 160 934.4 m is the shared base).
        special("us-gal100mi", .fuel(
            factor: 3.785411784 / (100.0 * 1609.344), reciprocal: false),
            "US gal/100mi",
            ["us gal/100mi", "us gallons per 100 miles"], .fuel)
        special("uk-gal100mi", .fuel(
            factor: 4.54609 / (100.0 * 1609.344), reciprocal: false),
            "UK gal/100mi",
            ["uk gal/100mi", "uk gallons per 100 miles"], .fuel)

        // MARK: Viscosity (vectors are collision-free; no family needed)
        // Dynamic viscosity M/(L·T), base Pa·s.
        lin("pascal-second", .MPerLT1, 1, "Pa·s",
            ["Pa·s", "Pa s", "Pa*s", "pascal second"], [])
        lin("poise", .MPerLT1, 0.1, "P", ["P", "poise", "poises"], [])
        lin("centipoise", .MPerLT1, 0.001, "cP",
            ["cP", "centipoise", "centipoises"], [])
        lin("reyn", .MPerLT1, 6894.757293168, "reyn", ["reyn", "reyns"], [])
        // Kinematic viscosity L²/T, base m²/s.
        lin("m2-per-s", .L2T1, 1, "m²/s",
            ["m²/s", "m2/s", "square meters per second"], [])
        lin("stokes", .L2T1, 1e-4, "St", ["St", "stokes", "stoke"], [])
        lin("centistokes", .L2T1, 1e-6, "cSt", ["cSt", "centistokes"], [])
        lin("ft2-per-s", .L2T1, 0.09290304, "ft²/s",
            ["ft²/s", "ft2/s", "square feet per second"], [])

        // MARK: Electric current (base A)
        lin("ampere", .A, 1, "A",
            ["A", "ampere", "amperes", "amp", "amps"],
            ["n", "µ", "m", "k", "K"])
        // MARK: Voltage (base V)
        lin("volt", .ML2T3A1, 1, "V",
            ["V", "volt", "volts"],
            ["µ", "m", "k", "K", "M"])
        // MARK: Resistance (base Ω)
        lin("ohm", .ML2T3A2, 1, "Ω",
            ["Ω", "ohm", "ohms"],
            ["k", "K", "M", "G"])
        // MARK: Charge (base C — label `C`; input `coulomb`)
        lin("coulomb", .T1A1, 1, "C",
            ["coulomb", "coulombs"],
            ["m", "k", "K"])
        lin("amp-hour", .T1A1, 3600, "Ah",
            ["Ah", "amp hour", "ampere hour", "amphour"], [])
        lin("millicoulomb", .T1A1, 1e-3, "mC",
            ["mC", "millicoulomb"], [])
        lin("kilocoulomb", .T1A1, 1000, "kC",
            ["kC", "kilocoulomb"], [])
        lin("mah", .T1A1, 3.6, "mAh",
            ["mAh", "milliamp hour", "milliampere hour"], [])
        // MARK: Capacitance (base F — label `F`; input `farad`)
        lin("farad", .T4A2ML2, 1, "F",
            ["farad", "farads"], [])
        lin("picofarad", .T4A2ML2, 1e-12, "pF",
            ["pF", "picofarad", "picofarads"], [])
        lin("nanofarad", .T4A2ML2, 1e-9, "nF",
            ["nF", "nanofarad", "nanofarads"], [])
        lin("microfarad", .T4A2ML2, 1e-6, "µF",
            ["µF", "microfarad", "microfarads"], [])
        lin("millifarad", .T4A2ML2, 1e-3, "mF",
            ["mF", "millifarad", "millifarads"], [])
        // MARK: Inductance (base H)
        lin("henry", .ML2T2A2, 1, "H",
            ["H", "henry", "henries"],
            ["m", "µ"])
        // MARK: Conductance (base S)
        lin("siemens", .T3A2ML2, 1, "S",
            ["S", "siemens", "siemen", "mho"],
            ["m", "µ"])
        // MARK: Magnetic flux (base Wb)
        lin("weber", .ML2T2A1, 1, "Wb",
            ["Wb", "weber", "webers"], ["m"])
        // MARK: Magnetic flux density (base T)
        lin("tesla", .MT2A1, 1, "T",
            ["T", "tesla", "teslas"],
            ["m", "µ"])
        lin("gauss", .MT2A1, 1e-4, "G", ["G", "gauss"], [])

        // MARK: Photometric
        lin("candela", .I, 1, "cd",
            ["cd", "candela", "candelas"], [], family: .luminousIntensity)
        lin("lumen", .I, 1, "lm",
            ["lm", "lumen", "lumens"], ["k", "K", "M"], family: .luminousFlux)
        lin("lux", .IPerL2, 1, "lx",
            ["lx", "lux"], [], family: .luminousFlux)
        lin("footcandle", .IPerL2, 10.76391041670972, "fc",
            ["fc", "foot-candle", "foot candle", "footcandle", "footcandles"], [], family: .luminousFlux)

        // MARK: Radioactivity & dose
        lin("becquerel", .T1, 1, "Bq",
            ["Bq", "becquerel", "becquerels"],
            ["m", "k", "K", "M", "G"], family: .activity)
        lin("curie", .T1, 3.7e10, "Ci",
            ["Ci", "curie", "curies"], [], family: .activity)
        lin("gray", .ML2T2, 1, "Gy",
            ["Gy", "gray", "grays"],
            ["m", "µ", "k", "K", "M"], family: .absorbedDose)
        lin("rad-dose", .ML2T2, 0.01, "rad (dose)",
            ["rads", "radiation absorbed dose", "rad dose", "absorbed rad"], [],
            family: .absorbedDose)
        lin("sievert", .ML2T2, 1, "Sv",
            ["Sv", "sievert", "sieverts"],
            ["m", "k", "K", "M"], family: .doseEquivalent)
        lin("rem", .ML2T2, 0.001, "rem",
            ["rem", "rems"], [], family: .doseEquivalent)

        // MARK: Currency (fiat codes; live rates). The code stays the
        // canonical label/id; user-facing English names ride along as
        // input aliases (`10 Indian rupees to Japanese yen`).
        for code in FiatCurrencies.codes {
            u.append(UnitDef(id: "cur-\(code)", kind: .currency(code),
                             label: code, family: .none,
                             aliases: [code] + (FiatCurrencies.aliases[code] ?? []),
                             prefixes: []))
        }

        return u
    }()
}
