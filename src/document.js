editor.addEventListener('keydown', function (event) {
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
			output.scrollLeft = input.scrollLeft // Добавлено для горизонтальной прокрутки, если необходимо
		} else {
			input.scrollTop = output.scrollTop
			input.scrollLeft = output.scrollLeft // Добавлено для горизонтальной прокрутки, если необходимо
		}
	}

	input.addEventListener('scroll', syncScroll)
	output.addEventListener('scroll', syncScroll)
})