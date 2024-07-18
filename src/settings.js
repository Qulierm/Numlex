function openSettings() {
	document.getElementById('settings-modal').style.display = 'block'
}

function closeSettings() {
	document.getElementById('settings-modal').style.display = 'none'
}

function saveSettings() {
	const fontSelector = document.getElementById('fontSelector')
	const selectedFont = fontSelector.value

	const textarea = document.getElementById('input')
	const pre = document.getElementById('code')
	editor.className = '' // Clear all current classes
	pre.className = '' // Clear all current classes
	textarea.classList.add(selectedColor) // Add selected class
	pre.classList.add(selectedFont)
	editor.classList.add(selectedFont)
}
