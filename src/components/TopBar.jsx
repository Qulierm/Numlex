import { Button, Tooltip } from '@heroui/react'
import { PanelLeft, Plus, Settings, Download, Upload, Sigma } from 'lucide-react'

function IconButton({ label, icon: Icon, onPress }) {
	return (
		<Tooltip.Root>
			<Tooltip.Trigger>
				<Button isIconOnly variant="flat" aria-label={label} onClick={onPress}>
					<Icon className="size-4" />
				</Button>
			</Tooltip.Trigger>
			<Tooltip.Content>{label}</Tooltip.Content>
		</Tooltip.Root>
	)
}

export function TopBar({
	sheetTitle,
	sheetMeta,
	sidebarOpen,
	toggleLabel,
	newSheetLabel,
	importLabel,
	exportLabel,
	settingsLabel,
	onToggleSidebar,
	onNewSheet,
	onImport,
	onExport,
	onSettings,
}) {
	return (
		<header className="flex h-12 shrink-0 items-center gap-1 border-b border-border bg-background px-2">
			<IconButton label={toggleLabel} icon={PanelLeft} onPress={onToggleSidebar} />
			<span className="flex items-center gap-2 pl-1 pr-1">
				<span className="flex size-6 items-center justify-center rounded-md bg-accent/15 text-accent">
					<Sigma className="size-3.5" />
				</span>
				<span className="hidden text-sm font-semibold tracking-tight min-[420px]:inline">Numlex</span>
			</span>
			<span className="mx-1 h-5 w-px shrink-0 bg-border" aria-hidden="true" />
			<div className="flex min-w-0 items-baseline gap-2 px-2">
				<span className="truncate text-sm font-medium">{sheetTitle}</span>
				{sheetMeta && <span className="shrink-0 text-xs text-muted">{sheetMeta}</span>}
			</div>
			<div className="ml-auto flex items-center gap-1">
				<Button variant="flat" size="sm" onClick={onNewSheet} aria-label={newSheetLabel}>
					<Plus className="size-4" />
					<span className="hidden md:inline">{newSheetLabel}</span>
				</Button>
				<IconButton label={importLabel} icon={Upload} onPress={onImport} />
				<IconButton label={exportLabel} icon={Download} onPress={onExport} />
				<IconButton label={settingsLabel} icon={Settings} onPress={onSettings} />
			</div>
		</header>
	)
}
