import { Button, ListBox, ScrollShadow, Tooltip } from '@heroui/react'
import { Plus, Settings, Download, Upload, X } from 'lucide-react'

function ActionButton({ label, icon: Icon, onPress }) {
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

export function Sidebar({
	sheets,
	activeIndex,
	newSheetLabel,
	deleteLabel,
	onAdd,
	onSwitch,
	onDelete,
	onSettings,
	onExport,
	onImport,
}) {
	return (
		<aside className="flex h-full w-56 shrink-0 flex-col border-r border-border bg-surface p-3">
			<Button
				fullWidth
				variant="flat"
				onClick={onAdd}
				className="mb-3"
			>
				<Plus className="size-4" />
				{newSheetLabel}
			</Button>

			<ScrollShadow className="min-h-0 flex-1">
				<ListBox
					className="numlex-sheets max-h-full gap-1 overflow-y-auto"
					aria-label="Sheets"
					selectionMode="single"
					selectionBehavior="replace"
					selectedKey={String(activeIndex)}
					onSelectionChange={(sel) => {
						const key = sel instanceof Set ? [...sel][0] : sel
						if (key != null) onSwitch(Number(key))
					}}
				>
					{sheets.map((sheet, index) => (
						<ListBox.Item
							key={`${sheet.title}-${index}`}
							id={String(index)}
							textValue={sheet.title}
							className={`group ${index === activeIndex ? 'bg-surface-secondary' : ''}`}
						>
							<span className="flex items-center gap-1">
								<span className="min-w-0 flex-1 truncate font-medium">{sheet.title}</span>
								{index === activeIndex && (
									<span
										role="button"
										tabIndex={0}
										aria-label={deleteLabel}
										onPointerDown={(e) => e.stopPropagation()}
										onClick={(e) => {
											e.stopPropagation()
											onDelete(index)
										}}
										onKeyDown={(e) => {
											if (e.key === 'Enter' || e.key === ' ') {
												e.stopPropagation()
												onDelete(index)
											}
										}}
										className="rounded p-0.5 text-muted opacity-0 transition-opacity hover:text-danger group-hover:opacity-100 focus:opacity-100"
									>
										<X className="size-3.5" />
									</span>
								)}
							</span>
							{sheet.createdAt && (
								<span className="block truncate text-xs text-muted">{sheet.createdAt}</span>
							)}
						</ListBox.Item>
					))}
				</ListBox>
			</ScrollShadow>

			<div className="mt-3 flex gap-1">
				<ActionButton label="Settings" icon={Settings} onPress={onSettings} />
				<ActionButton label="Export sheet (.nlx)" icon={Download} onPress={onExport} />
				<ActionButton label="Import sheet (.nlx)" icon={Upload} onPress={onImport} />
			</div>
		</aside>
	)
}
