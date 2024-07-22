const translations = {
	en: {
		sheet: 'Sheet',
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
		sheetname: 'Sheet title:',
		language: 'Interface language:',
		linenumber: 'Line numbers:',
	},
	ru: {
		sheet: 'Лист',
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
		sheetname: 'Заголовок листов:',
		language: 'Язык интерфейса:',
		linenumber: 'Номера строк',
	},
	de: {
		sheet: 'Blatt',
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
		sheetname: 'Titel der Blätter:',
		language: 'Sprache der Schnittstelle:',
		linenumber: 'Zeilennummern:',
	},
	fr: {
		sheet: 'Feuille',
		newSheet: 'Nouvelle feuille',
		enter: 'Entrez une expression pour commencer',
		settings: 'Paramètres',
		round: 'Arrondir les nombres:',
		fontcolor: 'Couleur de la police:',
		blue: 'Bleu',
		purple: 'Violet',
		red: 'Rouge',
		green: 'Vert',
		white: 'Blanc',
		fontsize: 'Taille de la police:',
		sheetname: 'Titre de la feuille:',
		language: "Langue de l'interface:",
		linenumber: 'Numéros de ligne:',
	},
	it: {
		sheet: 'Foglio',
		newSheet: 'Nuovo foglio',
		enter: "Inserisci un'espressione per iniziare",
		settings: 'Impostazioni',
		round: 'Arrotondamento numeri:',
		fontcolor: 'Colore del carattere:',
		blue: 'Blu',
		purple: 'Viola',
		red: 'Rosso',
		green: 'Verde',
		white: 'Bianco',
		fontsize: 'Dimensione del carattere:',
		sheetname: 'Titolo del foglio:',
		language: "Lingua dell'interfaccia:",
		linenumber: 'Numeri di riga:',
	},
	ch: {
		sheet: '工作表',
		newSheet: '新工作表',
		enter: '输入表达式开始',
		settings: '设置',
		round: '四舍五入的数字：',
		fontcolor: '字体颜色：',
		blue: '蓝色',
		purple: '紫色',
		red: '红色',
		green: '绿色',
		white: '白色',
		fontsize: '字体大小：',
		sheetname: '工作表标题：',
		language: '界面语言：',
		linenumber: '行号：',
	},
}

function updateLanguageTexts() {
	const lang = translations[currentLanguage]
	document.getElementById('new-sheet').textContent = lang.newSheet
	placehold = lang.enter
	editor.setOption('placeholder', placehold) // Обновление placeholder в CodeMirror
	document.getElementById('settings-title').textContent = lang.settings
	document.getElementById('round-label').textContent = lang.round
	document.getElementById('font-label').textContent = lang.fontsize
	document.getElementById('lang-label').textContent = lang.language
	document.getElementById('sheet-label').textContent = lang.sheetname
	document.getElementById('line-label').textContent = lang.linenumber
}

function changeLanguage() {
	const langSelector = document.getElementById('langSelector')
	currentLanguage = langSelector.value
	updateLanguageTexts()
}
