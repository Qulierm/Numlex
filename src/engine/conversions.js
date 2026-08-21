// Unit and currency conversion map (case-insensitive)
export const CONVERSIONS = [
	['km to meter', 1000, 'meters'],
	['meter to km', 1 / 1000, 'km'],
	['mile to km', 1.60934, 'km'],
	['km to mile', 1 / 1.60934, 'miles'],
	['cm to m', 1 / 100, 'm'],
	['m to cm', 100, 'cm'],
	['cm to km', 1 / 100000, 'km'],
	['km to cm', 100000, 'km'],
	['kg to t', 1 / 1000, 'ton'],
	['t to kg', 1000, 'kg'],
	['mg to kg', 1 / 1000, 'kg'],
	['kg to mg', 1000, 'mg'],
	['ml to teaspoon', 1 / 5, 'teaspoons'],
	['teaspoon to ml', 5, 'ml'],
	['liter to ml', 1000, 'ml'],
	['ml to liter', 1 / 1000, 'L'],
]

export const TEMP_CONVERSIONS = {
	'f to c': (F) => ((F - 32) * 5) / 9,
	'c to f': (C) => C * 1.8 + 32,
	'k to c': (K) => K - 273.15,
	'c to k': (C) => C + 273.15,
}

export const TEMP_UNITS = {
	'f to c': 'C°',
	'c to f': 'F°',
	'k to c': 'C°',
	'c to k': 'K°',
}

const conversionMap = new Map()
for (const [needle, factor, unit] of CONVERSIONS) {
	conversionMap.set(needle.toLowerCase(), { factor, unit, custom: null })
}
for (const [needle, fn] of Object.entries(TEMP_CONVERSIONS)) {
	conversionMap.set(needle, { factor: null, unit: TEMP_UNITS[needle], custom: fn })
}

function roundResult(value, decimalPlaces) {
	if (value % 1 !== 0) return parseFloat(value.toFixed(decimalPlaces))
	return value
}

export function tryConversion(line, rates, decimalPlaces) {
	const trimmed = line.trim()
	// Expect "<number> <from> to <to>" – extract leading number
	const m = trimmed.match(/^([+-]?\d*\.?\d+)\s+(.+)$/i)
	if (!m) return null
	const num = parseFloat(m[1])
	if (isNaN(num)) return null
	const rest = m[2].trim().toLowerCase()
	// direct map lookup for rest exactly (normalize multiple spaces)
	const normalized = rest.replace(/\s+/g, ' ')
	if (conversionMap.has(normalized)) {
		const { factor, unit, custom } = conversionMap.get(normalized)
		const result = custom ? custom(num) : num * factor
		return { kind: 'number', value: roundResult(result, decimalPlaces), unit }
	}
	// currency: e.g. "100 usd to rub"
	const currencyMatch = normalized.match(/^(\w+)\s+to\s+(\w+)$/)
	if (currencyMatch) {
		const from = currencyMatch[1]
		const to = currencyMatch[2]
		const key = `${from} to ${to}`
		// check known currency pairs
		const lowerKey = key.toLowerCase()
		const head = num
		if (isNaN(head)) return null
		// rates: USD, EUR, EURUSD
		const { USD, EUR, EURUSD } = rates || {}
		let value = null
		let unit = null
		if (lowerKey === 'usd to rub') {
			if (USD == null) return { kind: 'error', message: 'Rates unavailable' }
			value = head * USD
			unit = 'RUB'
		} else if (lowerKey === 'eur to rub') {
			if (EUR == null) return { kind: 'error', message: 'Rates unavailable' }
			value = head * EUR
			unit = 'RUB'
		} else if (lowerKey === 'rub to eur') {
			if (EUR == null) return { kind: 'error', message: 'Rates unavailable' }
			value = head / EUR
			unit = 'EUR'
		} else if (lowerKey === 'usd to eur') {
			if (EURUSD == null) return { kind: 'error', message: 'Rates unavailable' }
			value = head * EURUSD
			unit = 'EUR'
		} else if (lowerKey === 'eur to usd') {
			if (EURUSD == null) return { kind: 'error', message: 'Rates unavailable' }
			value = head / EURUSD
			unit = 'USD'
		} else if (lowerKey === 'rub to usd') {
			if (USD == null) return { kind: 'error', message: 'Rates unavailable' }
			value = head / USD
			unit = 'usd'
		} else {
			return null
		}
		if (value != null) {
			return { kind: 'number', value: roundResult(value, decimalPlaces), unit }
		}
	}
	return null
}
