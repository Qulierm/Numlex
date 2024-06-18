let sheets = [{ title: 'Sheet', content: '' }]
let currentSheetIndex = 0
let decimalPlaces = 6 // Значение по умолчанию
fetch('https://v6.exchangerate-api.com/v6/423d3f392eb1edd51a6f844a/latest/USD') 
	.then(response => response.json())
	.then(data => {
		// Обработка ответа от API
		const exchangeRateUSD = data.conversion_rates.RUB
	})

document
	.getElementById('decimal-places')
	.addEventListener('change', function () {
		decimalPlaces = this.value
		updateCode() // Пересчитать результат с новым количеством знаков после запятой
	})

async function updateCode() {
	const input = document.getElementById('input')
	const code = document.getElementById('code')
	const lines = input.value.split('\n')
	let output = ''
	
	const responseUSD = await fetch('https://v6.exchangerate-api.com/v6/423d3f392eb1edd51a6f844a/latest/USD')
	const dataUSD = await responseUSD.json()
	const exchangeRateUSD = dataUSD.conversion_rates.RUB

	const responseEUR = await fetch('https://v6.exchangerate-api.com/v6/423d3f392eb1edd51a6f844a/latest/EUR')
	const dataEUR = await responseEUR.json()
	const exchangeRateEUR = dataEUR.conversion_rates.RUB

	const responseEURUSD = await fetch('https://v6.exchangerate-api.com/v6/423d3f392eb1edd51a6f844a/latest/USD')
	const dataEURUSD = await responseEURUSD.json()
	const exchangeRateEURUSD = dataEURUSD.conversion_rates.EUR

	let isFirstEmptyLine = true

	lines.forEach((line, index) => {
		if (line.trim() === '' || line.startsWith('#')) {
			if (!isFirstEmptyLine) {
				output += '\n' // Пропуск строки только если предыдущая строка не была пустой
			}
			isFirstEmptyLine = true
			return
		}

		let result

		if (line.startsWith('# ')) {
			output += `<span class="hljs-title">${line.substring(2)}</span>\n`
			isFirstEmptyLine = false
		} else if (line.startsWith('#')) {
			// Пропускаем строку в выводе, если она начинается с #
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
				output += `<span class="number">${result} rub</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('eur to rub')) {
			const eur = parseFloat(line.split(' ')[0])
			if (!isNaN(eur)) {
				result = eur * exchangeRateEUR // преобразование евро в рубли
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} rub</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('rub to eur')) {
			const rub = parseFloat(line.split(' ')[0])
			if (!isNaN(rub)) {
				result = rub / exchangeRateEUR // преобразование рубли в евро
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} eur</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('usd to eur')) {
			const usd = parseFloat(line.split(' ')[0])
			if (!isNaN(usd)) {
				result = usd * exchangeRateEURUSD // преобразование долары в евро
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} eur</span>\n`
				isFirstEmptyLine = false
			}
		} else if (line.includes('eur to usd')) {
			const eur = parseFloat(line.split(' ')[0])
			if (!isNaN(eur)) {
				result = eur / exchangeRateEURUSD // преобразование долары в евро
				result = parseFloat(result.toFixed(4))
				output += `<span class="number">${result} usd</span>\n`
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
		} else {
			try {
				const mathExpression = line.replace(/[^-()\d/*+.]/g, '')
				result = eval(mathExpression)
				if (result !== undefined) {
					// Проверка на undefined и округление до 4 знаков после запятой, если необходимо
					if (result % 1 !== 0) {
						result = parseFloat(result.toFixed(4))
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
	}, 500) // Длительность анимации в миллисекундах
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

	// Проверяем, нажата ли клавиша с математическим знаком
	if ('+-*/'.includes(event.key)) {
		event.preventDefault() // Предотвращаем стандартное поведение браузера

		// Проверяем, что перед курсором нет пробелов
		if (inputValue.charAt(cursorPosition - 1) !== ' ') {
			// Добавляем пробелы перед и после математического знака
			textarea.value =
				inputValue.slice(0, cursorPosition) +
				' ' +
				event.key +
				' ' +
				inputValue.slice(cursorPosition)
			// Устанавливаем позицию курсора после добавленных пробелов
			textarea.setSelectionRange(cursorPosition + 3, cursorPosition + 3)
		}
	}
})

document.getElementById('input').addEventListener('keypress', function (event) {
	// Предотвращаем стандартное поведение браузера при вводе символов
	if ('+-*/'.includes(event.key)) {
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
	textarea.className = '' // Очистим все текущие классы
	pre.className = '' // Очистим все текущие классы
	textarea.classList.add(selectedColor) // Добавим выбранный класс
	pre.classList.add(selectedFont)
	textarea.classList.add(selectedFont)

}
