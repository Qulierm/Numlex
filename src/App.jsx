import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Sidebar } from './components/Sidebar'
import { EditorPane } from './components/EditorPane'
import { OutputPanel } from './components/OutputPanel'
import { SettingsModal } from './components/SettingsModal'
import { useTheme } from '@heroui/react'
import { evaluateSheet } from './lib/evaluate'
import { createRates, RATES_INTERVAL_MS } from './lib/rates'
import { translations } from './lib/translations'

const FONT_SIZES = {
	ttt: 22,
	tt: 23,
	tf: 24,
	tff: 25,
	ts: 26,
	tss: 27,
	te: 28,
	tn: 29,
	tth: 30,
}

function nowTime() {
	const d = new Date()
	return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

export default function App() {
	// Numlex is a dark app: keep the HeroUI dark theme (official plain-React pattern).
	useTheme('dark')

	const [sheets, setSheets] = useState(() => [{ title: 'Sheet', content: '' }])
	const [activeIndex, setActiveIndex] = useState(0)
	const [settingsOpen, setSettingsOpen] = useState(false)
	const [settings, setSettings] = useState({
		decimalPlaces: 7,
		fontSize: 'tf',
		language: 'en',
		sheetName: 'Sheet',
		lineNumbers: false,
	})
	const [rates, setRates] = useState({ USD: null, EUR: null, EURUSD: null })
	// Variables persist across evaluations (legacy semantics).
	const variablesRef = useRef({})
	const ratesRef = useRef(createRates())
	const fileInputRef = useRef(null)
	const cmViewRef = useRef(null)
	const outputRef = useRef(null)

	// Editor <-> output scroll sync (legacy behaviour).
	useEffect(() => {
		const view = cmViewRef.current
		const out = outputRef.current
		if (!view || !out) return
		const onEditorScroll = () => {
			out.scrollTop = view.scrollDOM.scrollTop
			out.scrollLeft = view.scrollDOM.scrollLeft
		}
		const onOutputScroll = () => {
			view.scrollDOM.scrollTop = out.scrollTop
			view.scrollDOM.scrollLeft = out.scrollLeft
		}
		view.scrollDOM.addEventListener('scroll', onEditorScroll)
		out.addEventListener('scroll', onOutputScroll)
		return () => {
			view.scrollDOM.removeEventListener('scroll', onEditorScroll)
			out.removeEventListener('scroll', onOutputScroll)
		}
	})

	const t = translations[settings.language] || translations.en

	useEffect(() => {
		const rates = ratesRef.current
		rates.load()
		setRates(rates.value)
		const id = setInterval(() => {
			rates.load()
			setRates(rates.value)
		}, RATES_INTERVAL_MS)
		return () => clearInterval(id)
	}, [])

	const activeSheet = sheets[activeIndex] || sheets[0]


	const rows = useMemo(
		() =>
			evaluateSheet(activeSheet.content, {
				variables: variablesRef.current,
				rates,
				decimalPlaces: settings.decimalPlaces,
			}),
		[activeSheet.content, rates, settings.decimalPlaces]
	)


	const updateActiveContent = useCallback(
		(content) => {
			setSheets(prev => prev.map((s, i) => (i === activeIndex ? { ...s, content } : s)))
		},
		[activeIndex]
	)

	const addSheet = useCallback(() => {
		setSheets(prev => {
			const sheet = {
				title: `${settings.sheetName} ${prev.length + 1}`,
				content: '',
				createdAt: nowTime(),
			}
			setActiveIndex(0)
			return [sheet, ...prev]
		})
	}, [settings.sheetName])

	const deleteSheet = useCallback(
		(index) => {
			if (sheets.length === 1) {
				setSheets([{ title: `${settings.sheetName} 1`, content: '', createdAt: nowTime() }])
				setActiveIndex(0)
				return
			}
			const next = sheets.filter((_, i) => i !== index)
			setSheets(next)
			setActiveIndex(cur => {
				if (index < cur) return cur - 1
				if (index === cur) return Math.min(cur, next.length - 1)
				return cur
			})
		},
		[sheets, settings.sheetName]
	)

	const switchSheet = useCallback((index) => {
		setActiveIndex(index)
	}, [])

	const exportCurrentSheet = useCallback(() => {
		const dataToExport = JSON.stringify(activeSheet)
		const blob = new Blob([dataToExport], { type: 'application/json' })
		const url = URL.createObjectURL(blob)
		const a = document.createElement('a')
		a.href = url
		a.download = `${activeSheet.title}.nlx`
		document.body.appendChild(a)
		a.click()
		document.body.removeChild(a)
		URL.revokeObjectURL(url)
	}, [activeSheet])

	const importSheet = useCallback((file) => {
		const reader = new FileReader()
		reader.onload = (e) => {
			try {
				const imported = JSON.parse(e.target.result)
				if (imported.title && imported.content != null) {
					setSheets(prev => {
						const next = [...prev, { title: imported.title, content: imported.content, createdAt: nowTime() }]
						setActiveIndex(next.length - 1)
						return next
					})
				}
			} catch {
				// invalid .nlx file — ignored, same as legacy
			}
		}
		reader.readAsText(file)
	}, [])

	// Hotkeys: Ctrl/Cmd + N, D, E, ",", I (legacy Ctrl+N/D/E/,/I, Meta added for macOS)
	useEffect(() => {
		const onKey = (event) => {
			if (!(event.ctrlKey || event.metaKey)) return
			switch (event.key.toLowerCase()) {
				case 'n':
					event.preventDefault()
					addSheet()
					break
				case 'd':
					event.preventDefault()
					deleteSheet(activeIndex)
					break
				case 'e':
					event.preventDefault()
					exportCurrentSheet()
					break
				case ',':
					event.preventDefault()
					setSettingsOpen(true)
					break
				case 'i':
					event.preventDefault()
					fileInputRef.current?.click()
					break
			}
		}
		window.addEventListener('keydown', onKey)
		return () => window.removeEventListener('keydown', onKey)
	}, [addSheet, deleteSheet, exportCurrentSheet, activeIndex])

	return (
		<div
			className="flex h-screen overflow-hidden bg-background text-foreground"
			style={{ '--numlex-editor-font-size': `${FONT_SIZES[settings.fontSize] ?? 24}px` }}
		>
			<Sidebar
				sheets={sheets}
				activeIndex={activeIndex}
				newSheetLabel={t.newSheet}
				deleteLabel={t.deleteSheet}
				onAdd={addSheet}
				onSwitch={switchSheet}
				onDelete={deleteSheet}
				onSettings={() => setSettingsOpen(true)}
				onExport={exportCurrentSheet}
				onImport={() => fileInputRef.current?.click()}
			/>
			<main className="flex min-w-0 flex-1 flex-col">
				<div className="flex min-h-0 flex-1">
					<div className="min-w-0 flex-1 bg-surface">
						<EditorPane
							value={activeSheet.content}
							onChange={updateActiveContent}
							placeholder={t.enter}
							lineNumbers={settings.lineNumbers}
							onCreateView={(view) => {
								cmViewRef.current = view
							}}
						/>
					</div>
					<OutputPanel rows={rows} innerRef={outputRef} />
				</div>
			</main>
			<SettingsModal
				open={settingsOpen}
				onOpenChange={setSettingsOpen}
				settings={settings}
				onChange={setSettings}
				translations={t}
			/>
			<input
				ref={fileInputRef}
				type="file"
				accept=".nlx"
				className="hidden"
				onChange={(e) => {
					const file = e.target.files?.[0]
					if (file) importSheet(file)
					e.target.value = ''
				}}
			/>
		</div>
	)
}
