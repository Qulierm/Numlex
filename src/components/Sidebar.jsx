import { Button, ListBox, ScrollShadow, Tooltip } from '@heroui/react'
import { Download, Plus, Settings, Upload, X } from 'lucide-react'

export function Sidebar({
	sheets,
	activeIndex,
	newSheetLabel,
	deleteLabel,
	closeLabel,
	sheetsLabel,
	importLabel,
	exportLabel,
	settingsLabel,
	onAdd,
	onSwitch,
	onDelete,
	onImport,
	onExport,
	onSettings,
	onClose,
}) {
	return (
		<aside
			className="flex h-full w-[200px] shrink-0 flex-col border-r border-border bg-surface"
			aria-label={sheetsLabel}
		>
			<div className="flex items-center justify-between px-3 pt-3 pb-2">
				<span className="text-sm font-semibold tracking-tight">Numlex</span>
				<Tooltip.Root>
					<Tooltip.Trigger className="min-[720px]:hidden">
						<Button isIconOnly variant="ghost" size="sm" aria-label={closeLabel} onPress={onClose}>
							<X className="size-4" />
						</Button>
					</Tooltip.Trigger>
					<Tooltip.Content>{closeLabel}</Tooltip.Content>
				</Tooltip.Root>
			</div>
			<div className="px-2 pb-3">
				<Button
					fullWidth
					size="sm"
					variant="solid"
					onPress={onAdd}
					className="h-8 justify-center gap-1.5 rounded-lg bg-accent text-accent-foreground font-medium"
				>
					<Plus className="size-4" />
					{newSheetLabel}
				</Button>
			</div>

			<div className="min-h-0 flex-1 px-2">
				<ScrollShadow className="h-full" hideScrollBar>
					<ListBox
						className="numlex-sheets max-h-full overflow-y-auto p-1"
						aria-label={sheetsLabel}
						selectionMode="single"
						selectionBehavior="replace"
						selectedKeys={new Set([String(activeIndex)])}
						onSelectionChange={(keys) => {
							const key = keys instanceof Set ? [...keys][0] : null
							if (key != null) onSwitch(Number(key))
						}}
					>
						{sheets.map((sheet, index) => {
							const rawLines = sheet.content ? sheet.content.split('\n') : []
							const lineCount = rawLines.length === 0 || (rawLines.length === 1 && rawLines[0] === '') ? 0 : rawLines.length
							const isActive = index === activeIndex
							return (
								<ListBox.Item
									key={`${sheet.title}-${index}`}
									id={String(index)}
									textValue={sheet.title}
									className={`group mb-1 rounded-lg border px-2.5 py-2 text-left ${isActive ? 'border-border bg-surface-secondary shadow-sm' : 'border-transparent bg-transparent hover:bg-surface-secondary/70'}`}
								>
									<div className="flex items-center justify-between gap-2">
										<span className="min-w-0 flex-1 truncate text-sm font-medium leading-tight">
											{sheet.title}
										</span>
										<Button
											isIconOnly
											variant="ghost"
											size="sm"
											aria-label={deleteLabel}
											onPress={() => onDelete(index)}
											className={`size-6 shrink-0 rounded-md p-0 text-muted hover:text-danger ${isActive ? 'opacity-40 group-hover:opacity-100' : 'opacity-0 group-hover:opacity-100 focus:opacity-100'}`}
										>
											<X className="size-3.5" />
										</Button>
									</div>
									<div className="mt-1 flex items-center gap-1 text-[11px] text-muted">
										<span className="whitespace-nowrap">{sheet.createdAt}</span>
										<span className="text-muted/60">·</span>
										<span className="whitespace-nowrap">{lineCount === 0 ? 'No lines' : `${lineCount} ${lineCount === 1 ? 'line' : 'lines'}`}</span>
									</div>
								</ListBox.Item>
							)
						})}
					</ListBox>
				</ScrollShadow>
			</div>

			<div className="flex items-center gap-1 border-t border-border/60 p-2">
				<Tooltip.Root>
					<Tooltip.Trigger>
						<Button isIconOnly variant="ghost" size="sm" aria-label={importLabel} onPress={onImport}>
							<Upload className="size-4" />
						</Button>
					</Tooltip.Trigger>
					<Tooltip.Content>{importLabel}</Tooltip.Content>
				</Tooltip.Root>
				<Tooltip.Root>
					<Tooltip.Trigger>
						<Button isIconOnly variant="ghost" size="sm" aria-label={exportLabel} onPress={onExport}>
							<Download className="size-4" />
						</Button>
					</Tooltip.Trigger>
					<Tooltip.Content>{exportLabel}</Tooltip.Content>
				</Tooltip.Root>
				<Tooltip.Root>
					<Tooltip.Trigger className="ml-auto">
						<Button isIconOnly variant="ghost" size="sm" aria-label={settingsLabel} onPress={onSettings}>
							<Settings className="size-4" />
						</Button>
					</Tooltip.Trigger>
					<Tooltip.Content>{settingsLabel}</Tooltip.Content>
				</Tooltip.Root>
			</div>
		</aside>
	)
}
