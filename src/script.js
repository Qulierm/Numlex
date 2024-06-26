let sheets = [{ title: 'Sheet', content: '' }]
let currentSheetIndex = 0
let decimalPlaces = 6 // Default value
let variables = {} // Store variables

document
	.getElementById('decimal-places')
	.addEventListener('change', function () {
		decimalPlaces = this.value
		updateCode() // Recalculate result with the new decimal places
	})

async function updateCode() {
	const input = document.getElementById('input')
	const code = document.getElementById('code')
	const lines = input.value.split('\n')
	let output = ''

	const response = await fetch('http://80.90.182.109:3000/rates')
	const data = await response.json()

	const exchangeRateUSD = data.USD
	const exchangeRateEUR = data.EUR
	const exchangeRateEURUSD = data.EURUSD

	let isFirstEmptyLine = true

	lines.forEach((line, index) => {
		if (line.trim() === '' || line.startsWith('#')) {
			if (!isFirstEmptyLine) {
				output += '\n' // Skip line only if previous line was not empty
			}
			isFirstEmptyLine = true
			return
		}

		let result

		if (line.startsWith('# ')) {
			output += `<span class="hljs-title">${line.substring(2)}</span>\n`
			isFirstEmptyLine = false
		} else if (line.startsWith('#')) {
			output += '\n'
			isFirstEmptyLine = true
		} else if (line.includes('km to meter')) {
			const kilometers = parseFloat(line.split(' ')[0])
			if (!isNaN(kilometers)) {
				result = kilometers * 1000 // Преобразование км в метры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} meters</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('meter to km')) {
			const meters = parseFloat(line.split(' ')[0])
			if (!isNaN(meters)) {
				result = meters / 1000 // Преобразование метров в км
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} km</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('kg to t')) {
			const kg = parseFloat(line.split(' ')[0])
			if (!isNaN(kg)) {
				result = kg / 1000 // Преобразование км в метры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} ton</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('t to kg')) {
			const t = parseFloat(line.split(' ')[0])
			if (!isNaN(t)) {
				result = t * 1000 // Преобразование км в метры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} kg</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('mg to kg')) {
			const mg = parseFloat(line.split(' ')[0])
			if (!isNaN(mg)) {
				result = mg / 1000 // Преобразование км в метры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} kg</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('kg to mg')) {
			const kg = parseFloat(line.split(' ')[0])
			if (!isNaN(kg)) {
				result = kg * 1000 // Преобразование км в метры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} mg</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('ml to teaspoon')) {
			const ml = parseFloat(line.split(' ')[0])
			if (!isNaN(ml)) {
				result = meters / 5 // Преобразование метров в км
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} teaspoons</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('liter to ml')) {
			const liters = parseFloat(line.split(' ')[0])
			if (!isNaN(liters)) {
				result = liters * 1000 // Преобразование литров в миллилитры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} ml</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('ml to liter')) {
			const ml = parseFloat(line.split(' ')[0])
			if (!isNaN(ml)) {
				result = ml / 1000 // Преобразование миллилитров в литры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} L</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('F to C')) {
			const F = parseFloat(line.split(' ')[0])
			if (!isNaN(F)) {
				result = ((F - 32) * 5) / 9 // Преобразование литров в миллилитры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} C°</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('C to F')) {
			const C = parseFloat(line.split(' ')[0])
			if (!isNaN(C)) {
				result = C * 1.8 + 32 // Преобразование литров в миллилитры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} F°</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('K to C')) {
			const K = parseFloat(line.split(' ')[0])
			if (!isNaN(K)) {
				result = K - 273.15 // Преобразование миллилитров в литры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} C°</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('C to K')) {
			const C = parseFloat(line.split(' ')[0])
			if (!isNaN(C)) {
				result = C + 273.15 // Преобразование миллилитров в литры
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} K°</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('usd to rub')) {
			const usd = parseFloat(line.split(' ')[0])
			if (!isNaN(usd)) {
				result = usd * exchangeRateUSD // Преобразование долларов в рубли
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} RUB</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('eur to rub')) {
			const eur = parseFloat(line.split(' ')[0])
			if (!isNaN(eur)) {
				result = eur * exchangeRateEUR // преобразование евро в рубли
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} RUB</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('rub to eur')) {
			const rub = parseFloat(line.split(' ')[0])
			if (!isNaN(rub)) {
				result = rub / exchangeRateEUR // преобразование рубли в евро
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} EUR</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('usd to eur')) {
			const usd = parseFloat(line.split(' ')[0])
			if (!isNaN(usd)) {
				result = usd * exchangeRateEURUSD // преобразование долары в евро
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} EUR</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('eur to usd')) {
			const eur = parseFloat(line.split(' ')[0])
			if (!isNaN(eur)) {
				result = eur / exchangeRateEURUSD // преобразование долары в евро
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} USD</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('rub to usd')) {
			const rub = parseFloat(line.split(' ')[0])
			if (!isNaN(rub)) {
				result = rub / exchangeRateUSD // Преобразование рублей в доллары
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} usd</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('=')) {
			const [variable, expression] = line.split('=').map(part => part.trim())
			let parsedValue
			try {
				const evaluatedExpression = expression
					.replace(/[^-()\d/*+.]/g, match => {
						if (variables.hasOwnProperty(match)) {
							return variables[match]
						}
						return match
					})
					.replace(/\^/g, '**')
					.replace(/(\d+)%/g, '(($1) / 100)')
				parsedValue = eval(evaluatedExpression)
				if (!isNaN(parsedValue)) {
					variables[variable] = parsedValue
					output += `<span class="variable">${variable} = ${parsedValue}</span>\n`
					isFirstEmptyLine = false
				}
			} catch (e) {
				output += `<span class="error">Error</span>\n`
				isFirstEmptyLine = false
			}
		} else {
			let evaluatedLine = line
			Object.keys(variables).forEach(variable => {
				const variableValue = variables[variable]
				const regex = new RegExp(`\\b${variable}\\b`, 'g')
				evaluatedLine = evaluatedLine.replace(regex, variableValue)
			})

			evaluatedLine = evaluatedLine.replace(/[a-zA-Z]+/g, '') // Remove non-variable words

			try {
				evaluatedLine = evaluatedLine
					.replace(/\^/g, '**')
					.replace(/(\d+)%/g, '(($1) / 100)')
				result = eval(evaluatedLine)
				if (result !== undefined) {
					if (result % 1 !== 0) {
						result = parseFloat(result.toFixed(decimalPlaces))
					}
					output += `<span class="number">${result}</span>\n`
					isFirstEmptyLine = false
				}
			} catch (e) {
				output += `<span class="error">Error</span>\n`
				isFirstEmptyLine = false
			}
		}
	})

	code.innerHTML = output
	sheets[currentSheetIndex].content = input.value
}

document.getElementById('input').addEventListener('keydown', function (event) {
	const textarea = event.target
	const cursorPosition = textarea.selectionStart
	const inputValue = textarea.value

	if ('+-*/^'.includes(event.key)) {
		event.preventDefault() // Prevent default browser behavior

		if (inputValue.charAt(cursorPosition - 1) !== ' ') {
			textarea.value =
				inputValue.slice(0, cursorPosition) +
				' ' +
				event.key +
				' ' +
				inputValue.slice(cursorPosition)
			textarea.setSelectionRange(cursorPosition + 3, cursorPosition + 3)
		}
	}
})

document.getElementById('input').addEventListener('keypress', function (event) {
	if ('+-*/^'.includes(event.key)) {
		event.preventDefault()
	}
})

document.addEventListener('DOMContentLoaded', function () {
	const input = document.getElementById('input')
	const output = document.getElementById('code')

	function syncScroll(event) {
		if (event.target === input) {
			output.scrollTop = input.scrollTop
		} else {
			input.scrollTop = output.scrollTop
		}
	}

	input.addEventListener('scroll', syncScroll)
	output.addEventListener('scroll', syncScroll)
})