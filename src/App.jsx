import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Sidebar } from './components/Sidebar'
import { EditorPane } from './components/EditorPane'
import { OutputPanel } from './components/OutputPanel'
import { SettingsModal } from './components/SettingsModal'
import { Button, Modal, Tooltip } from '@heroui/react'
import { PanelLeft } from 'lucide-react'
import { useTheme } from '@heroui/react'
import { evaluateSheet } from './engine'
import { createRates, RATES_INTERVAL_MS } from './lib/rates'
import { translations } from './lib/translations'

const FONT_SIZES = {
	ttt: 12,
	tt: 13,
	tf: 14,
	tff: 15,
	ts: 16,
	tss: 18,
	te: 20,
	tn: 22,
	tth: 24,
}

function nowTime() {
	const d = new Date()
	return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

export default function App() {
	useTheme('dark')

	const referenceContent = `236,287 + 87,459 + 11,020 + 25,000 + 6,000 + 5,000
82,688 + 41,856 + 131,000
85,520 + 43,124 + 138,488
##Самолет##
85,516 + 43,773 + 138,488
Отель
51,778 + 32,302
Еда+Такси
85,000
267.777k + 84,080 + 85,000
115 + 120 + 120 + 121 + 118 + 121 + 115 + 115 + 118 + 117 + 120
1,300 / 11
50 + 100 + 250 + 500`

	const [sheets, setSheets] = useState(() => [
		{ title: 'Empty', content: '', createdAt: '18:11' },
		{ title: '236,287 + 87,459 + 1...', content: referenceContent, createdAt: 'Jul 7 at 13:12' },
	])
	const [activeIndex, setActiveIndex] = useState(1)
	const [settingsOpen, setSettingsOpen] = useState(false)
	const [settings, setSettings] = useState({
		decimalPlaces: 7,
		fontSize: 'tf',
		language: 'en',
		sheetName: 'Sheet',
		lineNumbers: true,
	})
	const [rates, setRates] = useState({ USD: null, EUR: null, EURUSD: null })
	const [sidebarOpen, setSidebarOpen] = useState(() =>
		typeof window !== 'undefined' ? window.matchMedia('(min-width: 720px)').matches : true
	)
	const [isMobile, setIsMobile] = useState(() =>
		typeof window !== 'undefined' ? window.matchMedia('(max-width: 719px)').matches : false
	)
	useEffect(() => {
		const mq = window.matchMedia('(max-width: 719px)')
		const handler = (e) => setIsMobile(e.matches)
		mq.addEventListener('change', handler)
		return () => mq.removeEventListener('change', handler)
	}, [])
	const variablesRef = useRef({})
	const ratesRef = useRef(createRates())
	const fileInputRef = useRef(null)
	const cmViewRef = useRef(null)
	const outputRef = useRef(null)

	const fontSize = FONT_SIZES[settings.fontSize] ?? 24
	const lineHeight = Math.round(fontSize * 1.6)

	useEffect(() => {
		const view = cmViewRef.current
		const out = outputRef.current
		if (!view || !out) return
		const sideBySide = () => window.matchMedia('(min-width: 640px)').matches
		const onEditorScroll = () => {
			if (!sideBySide()) return
			out.scrollTop = view.scrollDOM.scrollTop
			out.scrollLeft = view.scrollDOM.scrollLeft
		}
		const onOutputScroll = () => {
			if (!sideBySide()) return
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
		const ratesObj = ratesRef.current
		ratesObj.load().then(() => setRates({ ...ratesObj.value }))
		const id = setInterval(() => {
			ratesObj.load().then(() => setRates({ ...ratesObj.value }))
		}, RATES_INTERVAL_MS)
		return () => clearInterval(id)
	}, [])

	const activeSheet = sheets[activeIndex] || sheets[0]

	const rows = useMemo(
		() => evaluateSheet(activeSheet.content, { variables: variablesRef.current, rates, decimalPlaces: settings.decimalPlaces }),
		[activeSheet.content, rates, settings.decimalPlaces]
	)

	const summary = useMemo(() => {
		const numeric = rows.filter((r) => r.kind === 'number' && typeof r.value === 'number' && !r.unit)
		if (numeric.length === 0) return null
		let sum = numeric.reduce((acc, r) => acc + Number(r.value), 0)
		if (sum % 1 !== 0) sum = parseFloat(sum.toFixed(settings.decimalPlaces))
		const abs = Math.abs(sum)
		let formatted
		if (abs >= 1_000_000) formatted = (sum / 1_000_000).toFixed(10).replace(/\.?0+$/, '') + 'M'
		else if (abs >= 100_000) formatted = (sum / 1000).toFixed(3) + 'k'
		else if (Number.isInteger(sum)) formatted = sum.toLocaleString('en-US')
		else formatted = String(sum)
		return {
			label: 'Total',
			value: formatted,
			detail: '',
		}
	}, [rows, settings.decimalPlaces])

	useEffect(() => {
		const syncHeights = () => {
			const view = cmViewRef.current
			const out = outputRef.current
			if (!view || !out) return
			const editorLines = view.contentDOM.querySelectorAll('.cm-line')
			const outputRows = out.querySelectorAll(':scope > div')
			const n = Math.min(editorLines.length, outputRows.length)
			for (let i = 0; i < n; i++) {
				const h = editorLines[i].getBoundingClientRect().height
				if (h > 0) {
					outputRows[i].style.height = h + 'px'
					outputRows[i].style.minHeight = h + 'px'
				}
			}
		}
		let ro
		let id
		const tryObserve = () => {
			const view = cmViewRef.current
			const out = outputRef.current
			if (!view || !out) {
				setTimeout(tryObserve, 200)
				return
			}
			try {
				ro = new ResizeObserver(syncHeights)
				ro.observe(view.contentDOM)
				ro.observe(view.scrollDOM)
			} catch {}
			id = setInterval(syncHeights, 150)
			syncHeights()
			window.addEventListener('resize', syncHeights)
		}
		tryObserve()
		return () => {
			if (ro) ro.disconnect()
			if (id) clearInterval(id)
			window.removeEventListener('resize', syncHeights)
		}
	}, [rows])

	const updateActiveContent = useCallback(
		(content) => setSheets((prev) => prev.map((s, i) => (i === activeIndex ? { ...s, content } : s))),
		[activeIndex]
	)

	const addSheet = useCallback(() => {
		setSheets((prev) => {
			const sheet = { title: `${settings.sheetName} ${prev.length + 1}`, content: '', createdAt: nowTime() }
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
			setActiveIndex((cur) => {
				if (index < cur) return cur - 1
				if (index === cur) return Math.min(cur, next.length - 1)
				return cur
			})
		},
		[sheets, settings.sheetName]
	)

	const switchSheet = useCallback((index) => setActiveIndex(index), [])

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
					setSheets((prev) => {
						const next = [...prev, { title: imported.title, content: imported.content, createdAt: nowTime() }]
						setActiveIndex(next.length - 1)
						return next
					})
				}
			} catch {}
		}
		reader.readAsText(file)
	}, [])

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
			style={{
				'--numlex-editor-font-size': `${fontSize}px`,
				'--numlex-line-height': `${lineHeight}px`,
			}}
		>
			{!isMobile && sidebarOpen && (
				<div className="flex">
					<Sidebar
						sheets={sheets}
						activeIndex={activeIndex}
						newSheetLabel={t.newSheet}
						deleteLabel={t.deleteSheet}
						closeLabel={t.hideSheets}
						sheetsLabel={t.sheets}
						importLabel={t.importSheet}
						exportLabel={t.exportSheet}
						settingsLabel={t.settings}
						onAdd={addSheet}
						onSwitch={switchSheet}
						onDelete={deleteSheet}
						onImport={() => fileInputRef.current?.click()}
						onExport={exportCurrentSheet}
						onSettings={() => setSettingsOpen(true)}
						onClose={() => setSidebarOpen(false)}
					/>
				</div>
			)}
			{isMobile && (
				<Modal.Root isOpen={sidebarOpen} onOpenChange={setSidebarOpen}>
					<Modal.Trigger className="sr-only" aria-label="Sheets">Sheets</Modal.Trigger>
					<Modal.Backdrop className="bg-black/60 backdrop-blur-none">
						<Modal.Container className="m-0 flex h-dvh max-h-dvh w-full max-w-none justify-start p-0">
							<Modal.Dialog className="flex h-full w-[190px] max-w-[80vw] flex-col rounded-none border-r bg-surface p-0 shadow-xl">
								<Sidebar
									sheets={sheets}
									activeIndex={activeIndex}
									newSheetLabel={t.newSheet}
									deleteLabel={t.deleteSheet}
									closeLabel={t.hideSheets}
									sheetsLabel={t.sheets}
									importLabel={t.importSheet}
									exportLabel={t.exportSheet}
									settingsLabel={t.settings}
									onAdd={addSheet}
									onSwitch={switchSheet}
									onDelete={deleteSheet}
									onImport={() => fileInputRef.current?.click()}
									onExport={exportCurrentSheet}
									onSettings={() => setSettingsOpen(true)}
									onClose={() => setSidebarOpen(false)}
								/>
							</Modal.Dialog>
						</Modal.Container>
					</Modal.Backdrop>
				</Modal.Root>
			)}

			<main className="relative flex min-w-0 flex-1 flex-col bg-surface">
				<div className="pointer-events-none absolute left-1/2 top-0 z-10 hidden -translate-x-1/2 sm:block">
					<div className="rounded-b-md bg-[#3a3a3c] px-4 py-1.5 text-xs font-medium text-muted">Redeem your hardship discount</div>
				</div>
				{!sidebarOpen && (
					<div className="absolute left-2 top-2 z-20">
						<Tooltip.Root>
							<Tooltip.Trigger>
								<Button isIconOnly variant="ghost" size="sm" aria-label={t.showSheets} onPress={() => setSidebarOpen(true)}>
									<PanelLeft className="size-4" />
								</Button>
							</Tooltip.Trigger>
							<Tooltip.Content>{t.showSheets}</Tooltip.Content>
						</Tooltip.Root>
					</div>
				)}
				<div className="flex min-h-0 flex-1 flex-col pt-2 sm:flex-row sm:pt-0">
					<div className={`min-h-40 min-w-0 flex-1 ${!sidebarOpen ? 'pt-8 sm:pt-0' : ''}`}>
						<EditorPane
							value={activeSheet.content}
							onChange={updateActiveContent}
							placeholder={t.enter}
							lineNumbers={settings.lineNumbers}
							onCreateView={(view) => (cmViewRef.current = view)}
						/>
					</div>
					<OutputPanel rows={rows} innerRef={outputRef} summary={summary} />
				</div>
			</main>

			<SettingsModal open={settingsOpen} onOpenChange={setSettingsOpen} settings={settings} onChange={setSettings} translations={t} />
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
