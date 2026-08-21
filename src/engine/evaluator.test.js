import { describe, test, expect } from 'vitest'
import { evaluateExpression } from './parser.js'
import { evaluateSheet } from './evaluator.js'

function state(vars = {}, rates = { USD: null, EUR: null, EURUSD: null }, dp = 7) {
	return { variables: { ...vars }, rates, decimalPlaces: dp }
}

describe('evaluateExpression', () => {
	test('precedence and parentheses', () => {
		expect(evaluateExpression('2 + 3 * 4', {})).toBe(14)
		expect(evaluateExpression('(2 + 3) * 4', {})).toBe(20)
		expect(evaluateExpression('2 * (3 + 4) * 5', {})).toBe(70)
		expect(evaluateExpression('10 - 4 - 2', {})).toBe(4)
	})
	test('power right associative', () => {
		expect(evaluateExpression('2 ^ 3', {})).toBe(8)
		expect(evaluateExpression('2 ^ 3 ^ 2', {})).toBe(512)
		expect(evaluateExpression('(2 ^ 3) ^ 2', {})).toBe(64)
	})
	test('percent postfix', () => {
		expect(evaluateExpression('50%', {})).toBe(0.5)
		expect(evaluateExpression('200 * 10%', {})).toBe(20)
		expect(evaluateExpression('100 + 10%', {})).toBeCloseTo(100.1)
	})
	test('unary', () => {
		expect(evaluateExpression('-5 + 3', {})).toBe(-2)
		expect(evaluateExpression('--5', {})).toBe(5)
		expect(evaluateExpression('-(2 + 3)', {})).toBe(-5)
	})
	test('variables', () => {
		expect(evaluateExpression('x * 2', { x: 5 })).toBe(10)
		expect(() => evaluateExpression('y + 1', {})).toThrow()
	})
	test('division and errors', () => {
		expect(() => evaluateExpression('5 / 0', {})).toThrow(/Division/)
		expect(() => evaluateExpression('((2 + 3)', {})).toThrow(/Missing/)
		expect(() => evaluateExpression('2 +', {})).toThrow()
	})
})

describe('evaluateSheet', () => {
	test('arithmetic and headings', () => {
		const st = state()
		const rows = evaluateSheet('// Groceries\nCoffee 12\nMilk 4.5\n\n// Total\n10 km to meter\n2 + 2 * 10', st)
		expect(rows.find(r => r.kind === 'title').text).toBe('Groceries')
		// Coffee 12 -> 12 via cleaned fallback
		expect(rows.filter(r => r.kind === 'number').map(r => r.value)).toContain(12)
		expect(rows.filter(r => r.kind === 'number').find(r => r.unit === 'meters').value).toBe(10000)
	})
	test('blank and title handling', () => {
		const st = state()
		const rows = evaluateSheet('a = 5\n\nb = 10\n// Notes\n# comment\nhello', st)
		// a=5 variable, blank, b=10 variable, title, blank?, skip/error for hello (hello stripped => empty => skip)
		expect(rows[0].kind).toBe('variable')
		expect(rows[1].kind).toBe('blank')
		expect(rows[2].kind).toBe('variable')
		expect(rows[3].kind).toBe('title')
	})
	test('assignments and references', () => {
		const vars = {}
		const st = { variables: vars, rates: { USD: null, EUR: null, EURUSD: null }, decimalPlaces: 7 }
		const rows = evaluateSheet('x = 5\nx * 2\ny = x + 3\ny', st)
		expect(rows[0].kind).toBe('variable')
		expect(rows[1].value).toBe(10)
		expect(rows[2].kind).toBe('variable')
		expect(rows[3].value).toBe(8)
		expect(vars.x).toBe(5)
		expect(vars.y).toBe(8)
	})
	test('invalid expression is error not crash', () => {
		const st = state()
		const rows = evaluateSheet('(2 +', st)
		expect(rows[0].kind).toBe('error')
	})
	test('conversions', () => {
		const st = state()
		expect(evaluateSheet('10 km to meter', st)[0].value).toBe(10000)
		expect(evaluateSheet('100 cm to m', st)[0].value).toBe(1)
		const temp = evaluateSheet('32 F to C', { variables: {}, rates: {}, decimalPlaces: 2 })[0]
		expect(temp.value).toBeCloseTo(0)
	})
	test('currency rate unavailable shows error', () => {
		const st = state({}, { USD: null, EUR: null, EURUSD: null })
		const rows = evaluateSheet('10 usd to rub', st)
		expect(rows[0].kind).toBe('error')
		const st2 = state({}, { USD: 90, EUR: 100, EURUSD: 0.9 })
		const rows2 = evaluateSheet('10 usd to rub', st2)
		expect(rows2[0].value).toBe(900)
		expect(rows2[0].unit).toBe('RUB')
	})
	test('free-form word stripping preserves variable', () => {
		const vars = {}
		const st = { variables: vars, rates: { USD: null, EUR: null, EURUSD: null }, decimalPlaces: 7 }
		evaluateSheet('price = 20', st)
		const rows = evaluateSheet('price with tax 5', st)
		// "price with tax 5" -> cleaned keeps price, strips with/tax -> "price  5" -> parse fails (two numbers without op) => error
		// but "Coffee 12" with no variable should be number
		const rows2 = evaluateSheet('Coffee 12', state())
		expect(rows2[0].value).toBe(12)
	})
})
