function addNewSheet() {
	const currentTime = new Date()
	const hours = currentTime.getHours().toString().padStart(2, '0')
	const minutes = currentTime.getMinutes().toString().padStart(2, '0')
	const time = `${hours}:${minutes}`
	const sheetLang = document.getElementById('input-field').value
	const newSheet = {
		title: `${sheetLang} ${sheets.length + 1}`,
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
	editor.setValue(sheet.content)
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
