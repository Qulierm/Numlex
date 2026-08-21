import { tokenize } from './tokenizer.js'

export function evaluateExpression(expr, variables = {}) {
	if (!expr || expr.trim() === '') throw new Error('Empty expression')
	const tokens = tokenize(expr)
	let pos = 0
	function peek() {
		return tokens[pos] || null
	}
	function consume() {
		return tokens[pos++]
	}
	function parseExpression() {
		let left = parseTerm()
		while (peek() && peek().type === 'operator' && (peek().value === '+' || peek().value === '-')) {
			const op = consume().value
			const right = parseTerm()
			if (op === '+') left = left + right
			else left = left - right
		}
		return left
	}
	function parseTerm() {
		let left = parseFactor()
		while (peek() && peek().type === 'operator' && (peek().value === '*' || peek().value === '/')) {
			const op = consume().value
			const right = parseFactor()
			if (op === '*') left = left * right
			else {
				if (right === 0) throw new Error('Division by zero')
				left = left / right
			}
		}
		return left
	}
	function parseFactor() {
		let left = parseUnary()
		if (peek() && peek().type === 'operator' && peek().value === '^') {
			consume()
			const right = parseFactor() // right associative
			left = Math.pow(left, right)
		}
		return left
	}
	function parseUnary() {
		if (peek() && peek().type === 'operator' && (peek().value === '+' || peek().value === '-')) {
			const op = consume().value
			const val = parseUnary()
			return op === '-' ? -val : val
		}
		return parsePrimary()
	}
	function parsePrimary() {
		const tok = peek()
		if (!tok) throw new Error('Unexpected end')
		let value
		if (tok.type === 'number') {
			consume()
			value = tok.value
		} else if (tok.type === 'identifier') {
			consume()
			const name = tok.value
			if (!Object.prototype.hasOwnProperty.call(variables, name)) throw new Error(`Unknown variable '${name}'`)
			value = variables[name]
			if (typeof value !== 'number' || isNaN(value)) throw new Error(`Invalid variable '${name}'`)
		} else if (tok.type === 'paren' && tok.value === '(') {
			consume()
			value = parseExpression()
			const closing = peek()
			if (!closing || closing.type !== 'paren' || closing.value !== ')') throw new Error('Missing closing parenthesis')
			consume()
		} else {
			throw new Error(`Unexpected token '${tok.value}'`)
		}
		// postfix percent: value% => value/100, may repeat
		while (peek() && peek().type === 'operator' && peek().value === '%') {
			consume()
			value = value / 100
		}
		return value
	}
	const result = parseExpression()
	if (pos < tokens.length) throw new Error(`Unexpected token '${tokens[pos].value}'`)
	return result
}
