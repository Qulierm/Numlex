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
	useTheme('dark')

	const [sheets, setSheets] = useState(() => [{ title: 'Sheet', content: '', createdAt: nowTime() }])
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
	const [sidebarOpen, setSidebarOpen] = useState(() =>
		typeof window !== 'undefined' ? window.matchMedia('(min-width: 1024px)').matches : true
	)
	const [isMobile, setIsMobile] = useState(() =>
		typeof window !== 'undefined' ? window.matchMedia('(max-width: 1023px)').matches : false
	)
	useEffect(() => {
		const mq = window.matchMedia('(max-width: 1023px)')
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
		return {
			label: t.sumOfResults || 'Sum of results',
			value: String(sum),
			detail: `${numeric.length} ${numeric.length === 1 ? 'value' : 'values'}`,
		}
	}, [rows, settings.decimalPlaces, t.sumOfResults])

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
							<Modal.Dialog className="flex h-full w-full flex-col rounded-none border-r bg-surface p-0 shadow-xl">
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

			<main className="flex min-w-0 flex-1 flex-col bg-surface">
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
