document.addEventListener('DOMContentLoaded', function () {
	const input = document.getElementById('input') as HTMLTextAreaElement
	const output = document.getElementById('code') as HTMLDivElement

	// Добавляем обработчик для keydown на редакторе
	input.addEventListener('keydown', function (event: KeyboardEvent) {
		const textarea = event.target as HTMLTextAreaElement
		const cursorPosition = textarea.selectionStart
		const inputValue = textarea.value

		if ('+-*/^'.includes(event.key)) {
			event.preventDefault() // Предотвращаем стандартное поведение браузера

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

	// Добавляем обработчик для keypress на элементе input
	input.addEventListener('keypress', function (event: KeyboardEvent) {
		if ('+-*/^'.includes(event.key)) {
			event.preventDefault()
		}
	})

	// Функция для синхронизации прокрутки
	function syncScroll(event: Event) {
		if (event.target === input) {
			output.scrollTop = input.scrollTop
			output.scrollLeft = input.scrollLeft // Добавлено для горизонтальной прокрутки, если необходимо
		} else {
			input.scrollTop = output.scrollTop
			input.scrollLeft = output.scrollLeft // Добавлено для горизонтальной прокрутки, если необходимо
		}
	}

	// Добавляем обработчики прокрутки для input и output
	input.addEventListener('scroll', syncScroll)
	output.addEventListener('scroll', syncScroll)
})
