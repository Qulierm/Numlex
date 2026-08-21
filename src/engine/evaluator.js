import { evaluateExpression } from './parser.js'
import { tryConversion } from './conversions.js'

function roundResult(value, decimalPlaces) {
	if (value % 1 !== 0) return parseFloat(value.toFixed(decimalPlaces))
	return value
}

function normalizeExpr(expr) {
	// Reference UI uses comma thousands separators and k/M suffixes (e.g. 236,287, 267.777k, 1.7M)
	// Strip commas then expand k/M for evaluation. Keep original line for display.
	let s = expr.replace(/,/g, '')
	s = s.replace(/(\d+(?:\.\d+)?)\s*k\b/gi, '($1*1000)')
	s = s.replace(/(\d+(?:\.\d+)?)\s*m\b/gi, '($1*1000000)')
	return s
}

function isValidIdentifier(name) {
	return /^[A-Za-z_]\w*$/.test(name)
}

function tryEvaluateCleaned(line, variables) {
	// Remove words that are not known variables, keeping numbers/operators/parens
	const cleaned = line.replace(/[A-Za-z_]\w*/g, (w) => (Object.prototype.hasOwnProperty.call(variables, w) ? w : ''))
	const trimmed = cleaned.trim()
	if (!trimmed || /^[\s+\-*/^%().]*$/.test(trimmed) && !/\d/.test(trimmed)) return null
	try {
		const val = evaluateExpression(trimmed, variables)
		return val
	} catch {
		return null
	}
}

function evalAssignment(line, variables, decimalPlaces) {
	const idx = line.indexOf('=')
	if (idx === -1) return null
	const left = line.slice(0, idx).trim()
	const rightRaw = line.slice(idx + 1).trim()
	const right = normalizeExpr(rightRaw)
	if (!isValidIdentifier(left)) return { kind: 'error', message: 'Invalid assignment' }
	if (!right) return { kind: 'error', message: 'Missing expression' }
	try {
		const raw = evaluateExpression(right, variables)
		const value = roundResult(raw, decimalPlaces)
		variables[left] = value
		return { kind: 'variable', name: left, value }
	} catch (e) {
		const cleanedVal = tryEvaluateCleaned(right, variables)
		if (cleanedVal != null) {
			const value = roundResult(cleanedVal, decimalPlaces)
			variables[left] = value
			return { kind: 'variable', name: left, value }
		}
		return { kind: 'error', message: e.message }
	}
}

function evalFreeExpression(line, variables, decimalPlaces) {
	const trimmed = normalizeExpr(line.trim())
	if (!trimmed) return null
	if (!/\d/.test(trimmed)) {
		// Cyrillic headings should be blank
		if (/[а-яА-ЯёЁ]/.test(trimmed)) return null
		const single = trimmed.trim()
		if (/^[A-Za-z_]\w*$/.test(single) && Object.prototype.hasOwnProperty.call(variables, single)) {
			// single known variable like "y" – allow evaluation
		} else {
			return null
		}
	}
	try {
		const raw = evaluateExpression(trimmed, variables)
		return { kind: 'number', value: roundResult(raw, decimalPlaces) }
	} catch {
		const cleanedVal = tryEvaluateCleaned(trimmed, variables)
		if (cleanedVal != null) {
			return { kind: 'number', value: roundResult(cleanedVal, decimalPlaces) }
		}
		return { kind: 'error', message: 'Invalid expression' }
	}
}

export function evalLine(line, state) {
	const { variables, rates, decimalPlaces } = state
	// 1. conversion (unit/currency)
	const conv = tryConversion(line, rates, decimalPlaces)
	if (conv) return conv // may be error for rates unavailable
	// 2. assignment
	if (line.includes('=')) {
		// Ensure it's not a conversion with "="? conversions never contain "="
		return evalAssignment(line, variables, decimalPlaces)
	}
	// 3. free expression
	return evalFreeExpression(line, variables, decimalPlaces)
}

export function evaluateSheet(source, state) {
	// state.variables is mutated (legacy persistence)
	const rows = []
	let isFirstEmptyLine = true
	for (const line of source.split('\n')) {
		if (line.trim() === '' || line.startsWith('#')) {
			if (!isFirstEmptyLine) rows.push({ kind: 'blank' })
			isFirstEmptyLine = true
			continue
		}
		isFirstEmptyLine = false
		if (line.startsWith('// ')) {
			rows.push({ kind: 'title', text: line.slice(2).trim() })
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

export function declaredVariables(source) {
	const declared = {}
	for (const line of source.split('\n')) {
		const m = line.match(/^\s*([A-Za-z_]\w*)\s*=/)
		if (m) declared[m[1]] = true
	}
	return declared
}
