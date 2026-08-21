import { Button, Tooltip } from '@heroui/react'
import { Download, PanelLeft, Settings, Upload, Sigma } from 'lucide-react'

function IconButton({ label, icon: Icon, onPress }) {
	return (
		<Tooltip.Root>
			<Tooltip.Trigger>
				<Button isIconOnly variant="ghost" size="sm" aria-label={label} onClick={onPress}>
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
	toggleLabel,
	importLabel,
	exportLabel,
	settingsLabel,
	onToggleSidebar,
	onImport,
	onExport,
	onSettings,
}) {
	return (
		<header className="flex h-11 shrink-0 items-center gap-1 border-b border-border/60 bg-background px-2">
			<IconButton label={toggleLabel} icon={PanelLeft} onPress={onToggleSidebar} />
			<span className="flex items-center gap-2 pl-1">
				<span className="flex size-5 items-center justify-center rounded bg-accent/12 text-accent">
					<Sigma className="size-3" />
				</span>
				<span className="hidden text-sm font-semibold tracking-tight min-[420px]:inline">Numlex</span>
			</span>
			<span className="mx-2 h-4 w-px shrink-0 bg-border/70" aria-hidden="true" />
			<div className="flex min-w-0 items-baseline gap-2">
				<span className="truncate text-sm font-medium">{sheetTitle}</span>
				{sheetMeta && <span className="shrink-0 text-xs text-muted">{sheetMeta}</span>}
			</div>
			<div className="ml-auto flex items-center gap-0.5">
				<IconButton label={importLabel} icon={Upload} onPress={onImport} />
				<IconButton label={exportLabel} icon={Download} onPress={onExport} />
				<IconButton label={settingsLabel} icon={Settings} onPress={onSettings} />
			</div>
		</header>
	)
}
