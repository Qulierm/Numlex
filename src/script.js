let sheets = [{ title: 'Sheet', content: '' }]
let currentSheetIndex = 0

function updateCode() {
	const input = document.getElementById('input')
	const code = document.getElementById('code')
	const lines = input.value.split('\n')
	let output = ''

	lines.forEach(line => {
		let result
		if (line.startsWith('# ')) {
			output += `<span class="hljs-title">${line.substring(2)}</span>\n`
		} else if (line.startsWith('## ')) {
			output += `<span class="hljs-subtitle">${line.substring(3)}</span>\n`
		} else {
			try {
				if (line.trim() !== '') {
					const mathExpression = line.replace(/[^-()\d/*+.]/g, '')
					result = eval(mathExpression)
					output += `<span class="number">${result}</span>\n`
				}
			} catch (e) {
				output += `<span class="error">Error</span>\n`
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
}

function deleteSheet(index) {
	sheets.splice(index, 1)
	if (index === currentSheetIndex) {
		currentSheetIndex = 0
	}
	renderSheets()
	switchSheet(currentSheetIndex)
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
            <span>${sheet.title}</span>
            <span>${sheet.createdAt}</span>
            <img class="delete-sheet-button" src="delete.svg" alt="Delete" onclick="deleteSheet(${index})">
        `
		sheetElement.addEventListener('click', () => switchSheet(index))
		sheetsList.appendChild(sheetElement)
	})
}

document.addEventListener('DOMContentLoaded', () => {
	renderSheets()
	updateCode()
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
