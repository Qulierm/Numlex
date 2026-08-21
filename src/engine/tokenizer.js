export function tokenize(expr) {
	const tokens = []
	let i = 0
	while (i < expr.length) {
		const ch = expr[i]
		if (/\s/.test(ch)) {
			i++
			continue
		}
		if (ch === '(' || ch === ')') {
			tokens.push({ type: 'paren', value: ch })
			i++
			continue
		}
		if (/[+\-*/^%]/.test(ch)) {
			tokens.push({ type: 'operator', value: ch })
			i++
			continue
		}
		if (/\d/.test(ch) || ch === '.') {
			let num = ''
			let dots = 0
			while (i < expr.length && /[\d.]/.test(expr[i])) {
				if (expr[i] === '.') dots++
				num += expr[i]
				i++
			}
			if (dots > 1 || num === '.' || num === '') throw new Error('Invalid number')
			tokens.push({ type: 'number', value: parseFloat(num) })
			continue
		}
		if (/[A-Za-z_]/.test(ch)) {
			let id = ''
			while (i < expr.length && /\w/.test(expr[i])) {
				id += expr[i]
				i++
			}
			tokens.push({ type: 'identifier', value: id })
			continue
		}
		throw new Error(`Unexpected character '${ch}'`)
	}
	return tokens
}
