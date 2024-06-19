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

	const responseUSD = await fetch(
		'https://v6.exchangerate-api.com/v6/{API-KEY}/latest/USD'
	)
	const dataUSD = await responseUSD.json()
	const exchangeRateUSD = dataUSD.conversion_rates.RUB

	const responseEUR = await fetch(
		'https://v6.exchangerate-api.com/v6/{API-KEY}/latest/EUR'
	)
	const dataEUR = await responseEUR.json()
	const exchangeRateEUR = dataEUR.conversion_rates.RUB

	const responseEURUSD = await fetch(
		'https://v6.exchangerate-api.com/v6/{API-KEY}/latest/USD'
	)
	const dataEURUSD = await responseEURUSD.json()
	const exchangeRateEURUSD = dataEURUSD.conversion_rates.EUR

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
		} else if (line.includes('ml to teaspoon')) {
			const ml = parseFloat(line.split(' ')[0])
			if (!isNaN(ml)) {
				result = meters / 5 // Преобразование метров в км
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} tуфыз</span>\n`
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

function addNewSheet() {
	const currentTime = new Date()
	const hours = currentTime.getHours().toString().padStart(2, '0')
	const minutes = currentTime.getMinutes().toString().padStart(2, '0')
	const time = `${hours}:${minutes}`

	const newSheet = {
		title: `Sheet ${sheets.length + 1}`,
		content: '',
		createdAt: time,
		linesCount: 0,
	}

	sheets.unshift(newSheet)
	switchSheet(0)
	renderSheets()

	const newSheetElement = document.querySelector('.sheets-list .sidebar-item')
	newSheetElement.classList.add('slide-in')
}

function deleteSheet(index) {
	const sheetElement = document.querySelectorAll('.sheets-list .sidebar-item')[
		index
	]
	sheetElement.classList.add('slide-out')
	setTimeout(() => {
		sheets.splice(index, 1)
		if (index === currentSheetIndex) {
			currentSheetIndex = 0
		}
		renderSheets()
		switchSheet(currentSheetIndex)
	}, 500) // Duration of animation in milliseconds
}

function switchSheet(index) {
	currentSheetIndex = index
	const sheet = sheets[index]
	document.getElementById('input').value = sheet.content
	updateCode()
	renderSheets()
}

function renderSheets() {
	const sheetsList = document.querySelector('.sheets-list')
	sheetsList.innerHTML = ''

	sheets.forEach((sheet, index) => {
		const sheetElement = document.createElement('div')
		sheetElement.className =
			'sidebar-item' + (index === currentSheetIndex ? ' active' : '')
		sheetElement.innerHTML = `
            <span class="sheet-title">${sheet.title}</span>
            <span class="sheet-time">${sheet.createdAt || ''}</span>
            ${
							index === currentSheetIndex
								? `<img class="delete-sheet-button" src="./icons/delete.svg" alt="Delete" onclick="deleteSheet(${index})">`
								: ''
						}
        `
		sheetElement.addEventListener('click', () => switchSheet(index))
		sheetsList.appendChild(sheetElement)
	})
}

document.addEventListener('DOMContentLoaded', function () {
	renderSheets()
	switchSheet(currentSheetIndex)
})

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

function openSettings() {
	document.getElementById('settings-modal').style.display = 'block'
}

function closeSettings() {
	document.getElementById('settings-modal').style.display = 'none'
}

function saveSettings() {
	const colorSelector = document.getElementById('colorSelector')
	const selectedColor = colorSelector.value
	const fontSelector = document.getElementById('fontSelector')
	const selectedFont = fontSelector.value

	const textarea = document.getElementById('input')
	const pre = document.getElementById('code')
	textarea.className = '' // Clear all current classes
	pre.className = '' // Clear all current classes
	textarea.classList.add(selectedColor) // Add selected class
	pre.classList.add(selectedFont)
	textarea.classList.add(selectedFont)
}
