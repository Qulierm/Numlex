// Function to open the settings modal
function openSettings(): void {
	const settingsModal = document.getElementById('settings-modal')
	if (settingsModal) {
		settingsModal.style.display = 'block'
	} else {
		console.error('Settings modal element not found.')
	}
}

// Function to close the settings modal
function closeSettings(): void {
	const settingsModal = document.getElementById('settings-modal')
	if (settingsModal) {
		settingsModal.style.display = 'none'
	} else {
		console.error('Settings modal element not found.')
	}
}

// Function to save settings and apply them to the editor
function saveSettings(): void {
	const fontSelector = document.getElementById(
		'fontSelector'
	) as HTMLSelectElement
	const selectedFont = fontSelector.value

	const textarea = document.getElementById('input')
	const pre = document.getElementById('code')
	const editorElement = document.querySelector('.CodeMirror') as HTMLElement // Assuming the editor has a class "CodeMirror"

	if (textarea && pre && editorElement) {
		textarea.className = '' // Clear all current classes
		pre.className = '' // Clear all current classes
		editorElement.className = '' // Clear all current classes

		textarea.classList.add(selectedFont) // Add selected class
		pre.classList.add(selectedFont)
		editorElement.classList.add(selectedFont)
	} else {
		console.error('Textarea, pre or editor element not found.')
	}
}

// Export functions if needed
export { openSettings, closeSettings, saveSettings }
