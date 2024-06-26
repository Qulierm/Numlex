const translations = {
	en: {
		newSheet: 'New sheet',
		enter: 'Enter an expression to start',
		settings: 'Settings',
		round: 'Rounding numbers:',
		fontcolor: 'Font color:',
		blue: 'Blue',
		purple: 'Purple',
		red: 'Red',
		green: 'Green',
		white: 'White',
		fontsize: 'Font size:',
	},
	ru: {
		newSheet: 'Новый лист',
		enter: 'Введите выражение чтобы начать',
		settings: 'Настройки',
		round: 'Округление чисел:',
		fontcolor: 'Цвет текста:',
		blue: 'Синий',
		purple: 'Фиолетовый',
		red: 'Красный',
		green: 'Зеленый',
		white: 'Белый',
		fontsize: 'Размер текста:',
	},
	de: {
		newSheet: 'Neues Blatt',
		enter: 'Geben Sie einen Ausdruck ein, um zu beginnen',
		settings: 'Einstellungen',
		round: 'Rundung von Zahlen',
		fontcolor: 'Schriftfarbe:',
		blue: 'Blau',
		purple: 'Violett',
		red: 'Rot',
		green: 'Grün',
		white: 'Weiss',
		fontsize: 'Schriftgröße',
	},
}

function updateLanguageTexts() {
	const lang = translations[currentLanguage]
	document.getElementById('new-sheet').textContent = lang.newSheet
	document.getElementById('input').placeholder = lang.enter
	document.getElementById('settings-title').textContent = lang.settings
	document.getElementById('round-label').textContent = lang.round
	document.getElementById('color-label').textContent = lang.fontcolor
	document.getElementById('font-label').textContent = lang.fontsize
	document.getElementById('lang-label').textContent = lang.language

	const colorSelector = document.getElementById('colorSelector')
	for (let option of colorSelector.options) {
		option.textContent = lang[option.value]
	}
}

function changeLanguage() {
	const langSelector = document.getElementById('langSelector')
	currentLanguage = langSelector.value
	updateLanguageTexts()
}
