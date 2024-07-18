function openSettings() {
	document.getElementById('settings-modal').style.display = 'block'
}

function closeSettings() {
	document.getElementById('settings-modal').style.display = 'none'
}

function saveSettings() {
    const fontSelector = document.getElementById('fontSelector');
    const selectedFontSize = fontSelector.value;

    // Destroy previous editor instance if it exists
    if (editor) {
        editor.toTextArea();
    }}