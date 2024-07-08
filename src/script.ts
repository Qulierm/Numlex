// interface Sheet {
// 	title: string
// 	content: string
// }

// let sheets: Sheet[] = [{ title: 'Sheet', content: '' }]
// let currentSheetIndex: number = 0
// let decimalPlaces: number = 6 // Default value
// let variables: { [key: string]: number } = {} // Store variables
// let declaredVariables: { [key: string]: boolean } = {}

// document
// 	.getElementById('decimal-places')
// 	.addEventListener('change', function (this: HTMLInputElement) {
// 		decimalPlaces = parseInt(this.value, 10)
// 		updateCode() // Recalculate result with the new decimal places
// 	})

// CodeMirror.defineMode('custom', function (config, parserConfig) {
// 	return {
// 		token: function (stream, state) {
// 			// Highlight comment lines
// 			if (stream.match(/^#.*/)) {
// 				return 'comment'
// 			}
// 			if (stream.match('to')) {
// 				return 'highlight-to'
// 			}
// 			// Highlight numbers
// 			if (stream.match(/^[0-9]+/)) {
// 				return 'highlight-number'
// 			}
// 			// Highlight mathematical operators
// 			if (stream.match(/^[+\-*/]/)) {
// 				return 'highlight-operator'
// 			}
// 			// Highlight variable declaration
// 			if (stream.match(/^\s*[a-zA-Z_]\w*(?=\s*=)/)) {
// 				const variable = stream.current().trim()
// 				declaredVariables[variable] = true
// 				return 'highlight-before-equals'
// 			}
// 			// Highlight used variables
// 			const match = stream.match(/^[a-zA-Z_]\w*/)
// 			if (match && declaredVariables.hasOwnProperty(match[0])) {
// 				return 'highlight-used-variable'
// 			}
// 			// Move cursor
// 			while (
// 				stream.next() != null &&
// 				!stream.match(
// 					/(to|^[0-9]+|^[+\-*/]|^\s*[a-zA-Z_]\w*(?=\s*=)|^[a-zA-Z_]\w*)/,
// 					false
// 				)
// 			) {}
// 			return null
// 		},
// 	}
// })

// let editor = CodeMirror.fromTextArea(
// 	document.getElementById('input') as HTMLTextAreaElement,
// 	{
// 		lineNumbers: false,
// 		scrollbarStyle: 'null',
// 		theme: 'default', // Choose editor theme
// 		lint: true,
// 		mode: 'custom',
// 		placeholder: 'Enter an expression to start',
// 	}
// )

// function updateDeclaredVariables() {
// 	declaredVariables = {} // Clear variables before re-analysis
// 	const lines = editor.getValue().split('\n')
// 	lines.forEach(line => {
// 		const match = line.match(/^\s*([a-zA-Z_]\w*)\s*=/)
// 		if (match) {
// 			declaredVariables[match[1]] = true
// 		}
// 	})
// 	editor.refresh() // Refresh editor for re-highlighting
// }

// editor.on('change', updateDeclaredVariables)

// async function updateCode() {
// 	const code = document.getElementById('code')
// 	const lines = editor.getValue().split('\n')
// 	let output = ''

// 	const response = await fetch('http://80.90.182.109:3000/rates')
// 	const data = await response.json()

// 	const exchangeRateUSD = data.USD
// 	const exchangeRateEUR = data.EUR
// 	const exchangeRateEURUSD = data.EURUSD

// 	let isFirstEmptyLine = true
// 	lines.forEach((line, index) => {
// 		if (line.trim() === '' || line.startsWith('#')) {
// 			if (!isFirstEmptyLine) {
// 				output += '\n' // Skip line only if previous line was not empty
// 			}
// 			isFirstEmptyLine = true
// 			return
// 		}

// 		let result

// 		if (line.startsWith('// ')) {
// 			output += `<span class="hljs-title">${line.substring(2)}</span>\n`
// 			isFirstEmptyLine = false
// 		} else if (line.startsWith('//')) {
// 			output += '\n'
// 			isFirstEmptyLine = true
// 		} else if (line.includes('km to meter')) {
// 			const kilometers = parseFloat(line.split(' ')[0])
// 			if (!isNaN(kilometers)) {
// 				result = kilometers * 1000 // Convert km to meters
// 				result = parseFloat(result.toFixed(4))
// 				output += `<span class="number">${result} meters</span>\n`
// 				isFirstEmptyLine = false
// 			}
// 		} else if (line.includes('meter to km')) {
// 			const meters = parseFloat(line.split(' ')[0])
// 			if (!isNaN(meters)) {
// 				result = meters / 1000 // Convert meters to km
// 				result = parseFloat(result.toFixed(4))
// 				output += `<span class="number">${result} km</span>\n`
// 				isFirstEmptyLine = false
// 			}
// 		}
// 		// Add more conversions as needed...
// 		else if (line.includes('=')) {
// 			const [variable, expression] = line.split('=').map(part => part.trim())
// 			let parsedValue
// 			try {
// 				const evaluatedExpression = expression
// 					.replace(/[^-()\d/*+.]/g, match => {
// 						if (variables.hasOwnProperty(match)) {
// 							return variables[match].toString()
// 						}
// 						return match
// 					})
// 					.replace(/\^/g, '**')
// 					.replace(/(\d+)%/g, '(($1) / 100)')
// 				parsedValue = eval(evaluatedExpression)
// 				if (!isNaN(parsedValue)) {
// 					variables[variable] = parsedValue
// 					output += `<span class="variable">${variable} = ${parsedValue}</span>\n`
// 					isFirstEmptyLine = false
// 				}
// 			} catch (e) {
// 				output += `<span class="error">Error</span>\n`
// 				isFirstEmptyLine = false
// 			}
// 		} else {
// 			let evaluatedLine = line
// 			Object.keys(variables).forEach(variable => {
// 				const variableValue = variables[variable]
// 				const regex = new RegExp(`\\b${variable}\\b`, 'g')
// 				evaluatedLine = evaluatedLine.replace(regex, variableValue.toString())
// 			})

// 			evaluatedLine = evaluatedLine.replace(/[a-zA-Z]+/g, '') // Remove non-variable words

// 			try {
// 				evaluatedLine = evaluatedLine
// 					.replace(/\^/g, '**')
// 					.replace(/(\d+)%/g, '(($1) / 100)')
// 				result = eval(evaluatedLine)
// 				if (result !== undefined) {
// 					if (result % 1 !== 0) {
// 						result = parseFloat(result.toFixed(decimalPlaces))
// 					}
// 					output += `<span class="number">${result}</span>\n`
// 					isFirstEmptyLine = false
// 				}
// 			} catch (e) {
// 				output += `<span class="error">Error</span>\n`
// 				isFirstEmptyLine = false
// 			}
// 		}
// 	})
// 	code.innerHTML = output
// 	sheets[currentSheetIndex].content = editor.getValue()
// }

// editor.on('change', updateCode)

// document.addEventListener('DOMContentLoaded', () => {
// 	updateCode() // Initial call to update code when the page loads
// })

// editor.on('keydown', function (event) {
// 	const textarea = event.target as HTMLTextAreaElement
// 	const cursorPosition = textarea.selectionStart
// 	const inputValue = textarea.value

// 	if ('+-*/^'.includes(event.key)) {
// 		event.preventDefault() // Prevent default browser behavior

// 		if (inputValue.charAt(cursorPosition - 1) !== ' ') {
// 			textarea.value =
// 				inputValue.slice(0, cursorPosition) +
// 				' ' +
// 				event.key +
// 				' ' +
// 				inputValue.slice(cursorPosition)
// 			textarea.setSelectionRange(cursorPosition + 3, cursorPosition + 3)
// 		}
// 	}
// })

// document.getElementById('input').addEventListener('keypress', function (event) {
// 	if ('+-*/^'.includes(event.key)) {
// 		event.preventDefault()
// 	}
// })

// document.addEventListener('DOMContentLoaded', function () {
// 	const input = document.getElementById('input') as HTMLTextAreaElement
// 	const output = document.getElementById('code')

// 	function syncScroll(event: Event) {
// 		if (event.target === input) {
// 			output.scrollTop = input.scrollTop
// 			output.scrollLeft = input.scrollLeft // Added for horizontal scroll if needed
// 		} else {
// 			input.scrollTop = output.scrollTop
// 			input.scrollLeft = output.scrollLeft // Added for horizontal scroll if needed
// 		}
// 	}

// 	input.addEventListener('scroll', syncScroll)
// 	output.addEventListener('scroll', syncScroll)
// })
