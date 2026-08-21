// Core evaluation engine, ported from the legacy src/script.js (updateCode).
// Semantics are intentionally identical: variable persistence across
// evaluations, integer results unrounded, fractional results rounded to
// `decimalPlaces`, word stripping for free-form arithmetic.

// Each conversion: [match substring, from->to factor, output unit label]
const CONVERSIONS = [
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
	['F to C', null, 'C°', (F) => ((F - 32) * 5) / 9],
	['C to F', null, 'F°', (C) => C * 1.8 + 32],
	['K to C', null, 'C°', (K) => K - 273.15],
	['C to K', null, 'K°', (C) => C + 273.15],
]

// Evaluate one line; returns a result object or null.
// state: { variables, rates, decimalPlaces }
function evalLine(line, state) {
	const { rates, decimalPlaces } = state
	const variables = state.variables

	// Unit conversions
	for (const entry of CONVERSIONS) {
		const [needle, factor, unit, custom] = entry
		if (line.includes(needle)) {
			const num = parseFloat(line.split(' ')[0])
			if (isNaN(num)) continue
			const result = custom ? custom(num) : num * factor
			return { kind: 'number', value: roundResult(result, decimalPlaces), unit }
		}
	}

	// Currency conversions
	const rateUSD = rates.USD
	const rateEUR = rates.EUR
	const rateEURUSD = rates.EURUSD
	const head = parseFloat(line.split(' ')[0])
	const currency = (rate, expr, outUnit) => {
		if (rate == null) return null
		const result = expr(parseFloat(line.split(' ')[0]))
		return { kind: 'number', value: roundResult(result, decimalPlaces), unit: outUnit }
	}
	if (line.includes('usd to rub') && rateUSD != null && !isNaN(head)) return currency(rateUSD, v => v * rateUSD, 'RUB')
	if (line.includes('eur to rub') && rateEUR != null && !isNaN(head)) return currency(rateEUR, v => v * rateEUR, 'RUB')
	if (line.includes('rub to eur') && rateEUR != null && !isNaN(head)) return currency(rateEUR, v => v / rateEUR, 'EUR')
	if (line.includes('usd to eur') && rateEURUSD != null && !isNaN(head)) return currency(rateEURUSD, v => v * rateEURUSD, 'EUR')
	if (line.includes('eur to usd') && rateEURUSD != null && !isNaN(head)) return currency(rateEURUSD, v => v / rateEURUSD, 'USD')
	if (line.includes('rub to usd') && rateUSD != null && !isNaN(head)) return currency(rateUSD, v => v / rateUSD, 'usd')

	// Variable assignment
	if (line.includes('=')) {
		const [variable, expression] = line.split('=').map(part => part.trim())
		const substituted = expression
			.replace(/[^-()\d/*+.]/g, match => {
				if (variables.hasOwnProperty(match)) {
					return variables[match]
				}
				return match
			})
			.replace(/\^/g, '**')
			.replace(/(\d+)%/g, '(($1) / 100)')
		try {
			// eslint-disable-next-line no-eval
			const value = eval(substituted)
			if (!isNaN(value)) {
				variables[variable] = value
				return { kind: 'variable', name: variable, value }
			}
		} catch {
			return { kind: 'error' }
		}
		return null
	}

	// Free expression with variable substitution
	let evaluatedLine = line
	for (const name of Object.keys(variables)) {
		const value = variables[name]
		const regex = new RegExp(`\\b${name}\\b`, 'g')
		evaluatedLine = evaluatedLine.replace(regex, value)
	}
	evaluatedLine = evaluatedLine.replace(/[a-zA-Z]+/g, '')
	try {
		const finalExpr = evaluatedLine
			.replace(/\^/g, '**')
			.replace(/(\d+)%/g, '(($1) / 100)')
		// eslint-disable-next-line no-eval
		const result = eval(finalExpr)
		if (result !== undefined) {
			return { kind: 'number', value: roundResult(result, decimalPlaces) }
		}
	} catch {
		return { kind: 'error' }
	}
	return null
}

// Legacy rounding: integers stay integers, fractional values use toFixed(decimalPlaces)
function roundResult(result, decimalPlaces) {
	if (result % 1 !== 0) {
		return parseFloat(result.toFixed(decimalPlaces))
	}
	return result
}

/**
 * Evaluate the whole sheet.
 * Returns an array of output rows, one per source line:
 *  { kind: 'skip' }            — empty line / # comment (collapsed first empty run)
 *  { kind: 'blank' }           — // separator
 *  { kind: 'title', text }     — // title
 *  { kind: 'number', value, unit? }
 *  { kind: 'variable', name, value }
 *  { kind: 'error' }
 */
export function evaluateSheet(source, state) {
	const rows = []
	let isFirstEmptyLine = true
	for (const line of source.split('\n')) {
		if (line.trim() === '' || line.startsWith('#')) {
			if (!isFirstEmptyLine) {
				rows.push({ kind: 'blank' })
			}
			isFirstEmptyLine = true
			continue
		}
		isFirstEmptyLine = false
		if (line.startsWith('// ')) {
			rows.push({ kind: 'title', text: line.substring(2) })
			continue
		}
		if (line.startsWith('//')) {
			rows.push({ kind: 'blank' })
			isFirstEmptyLine = true
			continue
		}
		const result = evalLine(line, state)
		if (result == null) {
			rows.push({ kind: 'skip' })
			continue
		}
		rows.push(result)
	}
	return rows
}

// Variables declared at line start ("name =") — used by the editor mode.
export function declaredVariables(source) {
	const declared = {}
	for (const line of source.split('\n')) {
		const match = line.match(/^\s*([a-zA-Z_]\w*)\s*=/)
		if (match) declared[match[1]] = true
	}
	return declared
}
