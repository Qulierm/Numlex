// sheets.ts
declare function updateCode(): void
interface Sheet {
	title: string
	content: string
	createdAt: string
	linesCount: number
}

declare var sheets: Sheet[]
declare var currentSheetIndex: number
declare var editor: any

function addNewSheet(): void {
	const currentTime = new Date()
	const hours = currentTime.getHours().toString().padStart(2, '0')
	const minutes = currentTime.getMinutes().toString().padStart(2, '0')
	const time = `${hours}:${minutes}`
	const sheetLang = (document.getElementById('input-field') as HTMLInputElement)
		.value
	const newSheet: Sheet = {
		title: `${sheetLang} ${sheets.length + 1}`,
		content: '',
		createdAt: time,
		linesCount: 0,
	}

	sheets.unshift(newSheet)
	switchSheet(0)
	renderSheets()
	const newSheetElement = document.querySelector('.sheets-list .sidebar-item')
	if (newSheetElement) {
		newSheetElement.classList.add('slide-in')
	}
}

function deleteSheet(index: number): void {
	const sheetElement = document.querySelectorAll('.sheets-list .sidebar-item')[
		index
	]
	if (sheetElement) {
		sheetElement.classList.add('slide-out')
	}
	setTimeout(() => {
		sheets.splice(index, 1)
		if (index === currentSheetIndex) {
			currentSheetIndex = 0
		}
		renderSheets()
		switchSheet(currentSheetIndex)
	}, 500) // Duration of animation in milliseconds
}

function switchSheet(index: number): void {
	currentSheetIndex = index
	const sheet = sheets[index]
	editor.setValue(sheet.content)
	updateCode()
	renderSheets()
}

function renderSheets(): void {
	const sheetsList = document.querySelector('.sheets-list') as HTMLDivElement
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

document.addEventListener('DOMContentLoaded', () => {
	renderSheets()
	switchSheet(currentSheetIndex)
})
