import { Button, ListBox, ScrollShadow, Tooltip } from '@heroui/react'
import { Download, Layers, Plus, Settings, Trash2, Upload, X } from 'lucide-react'

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
			className="flex h-full w-[190px] shrink-0 flex-col border-r border-border bg-surface"
			aria-label={sheetsLabel}
		>
			<div className="flex items-center gap-1.5 px-3 pt-3 pb-2">
				<span className="size-3 rounded-full bg-[#ff5f57]" aria-hidden="true" />
				<span className="size-3 rounded-full bg-[#ffbd2e]" aria-hidden="true" />
				<span className="size-3 rounded-full bg-[#28c840]" aria-hidden="true" />
				<Tooltip.Root>
					<Tooltip.Trigger className="ml-auto min-[720px]:hidden">
						<Button isIconOnly variant="ghost" size="sm" aria-label={closeLabel} onPress={onClose}>
							<X className="size-4" />
						</Button>
					</Tooltip.Trigger>
					<Tooltip.Content>{closeLabel}</Tooltip.Content>
				</Tooltip.Root>
			</div>
			<div className="px-2 pb-2">
				<Button
					fullWidth
					size="sm"
					variant="ghost"
					onPress={onAdd}
					className="h-7 justify-start gap-2 rounded-md px-3 font-normal text-muted hover:bg-surface-secondary/60 hover:text-foreground"
				>
					<span className="flex size-5 items-center justify-center rounded-full border border-border bg-surface-secondary/50">
						<Plus className="size-3" />
					</span>
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
									<div className="flex items-start justify-between gap-2">
										<span className="min-w-0 flex-1 truncate text-sm font-medium leading-tight">
											{sheet.title}
										</span>
										<Tooltip.Root>
											<Tooltip.Trigger>
												<Button
													isIconOnly
													variant="ghost"
													size="sm"
													aria-label={deleteLabel}
													onPress={() => onDelete(index)}
													className={`size-6 shrink-0 rounded-md p-0 text-muted hover:text-danger ${isActive ? 'opacity-60 group-hover:opacity-100' : 'opacity-0 group-hover:opacity-100 focus:opacity-100'}`}
												>
													<Trash2 className="size-3.5" />
												</Button>
											</Tooltip.Trigger>
											<Tooltip.Content>{deleteLabel}</Tooltip.Content>
										</Tooltip.Root>
									</div>
									<div className="mt-1 flex items-center justify-between gap-1 text-xs text-muted">
										<span className="whitespace-nowrap">{sheet.createdAt}</span>
										<span className="whitespace-nowrap">{lineCount === 0 ? 'No lines' : `${lineCount} ${lineCount === 1 ? 'line' : 'lines'}`}</span>
									</div>
								</ListBox.Item>
							)
						})}
					</ListBox>
				</ScrollShadow>
			</div>

			<div className="flex flex-col gap-1.5 border-t border-border/60 p-2">
				<div className="flex items-center gap-1">
					<Tooltip.Root>
						<Tooltip.Trigger>
							<Button
								isIconOnly
								variant="ghost"
								size="sm"
								aria-label={importLabel}
								onPress={onImport}
							>
								<Upload className="size-4" />
							</Button>
						</Tooltip.Trigger>
						<Tooltip.Content>{importLabel}</Tooltip.Content>
					</Tooltip.Root>
					<Tooltip.Root>
						<Tooltip.Trigger>
							<Button
								isIconOnly
								variant="ghost"
								size="sm"
								aria-label={exportLabel}
								onPress={onExport}
							>
								<Download className="size-4" />
							</Button>
						</Tooltip.Trigger>
						<Tooltip.Content>{exportLabel}</Tooltip.Content>
					</Tooltip.Root>
					<Tooltip.Root>
						<Tooltip.Trigger className="ml-auto">
							<Button
								isIconOnly
								variant="ghost"
								size="sm"
								aria-label={settingsLabel}
								onPress={onSettings}
							>
								<Settings className="size-4" />
							</Button>
						</Tooltip.Trigger>
						<Tooltip.Content>{settingsLabel}</Tooltip.Content>
					</Tooltip.Root>
				</div>
				<div className="flex items-center gap-2 rounded-lg border border-border/40 bg-surface-secondary/40 px-2.5 py-2">
					<span className="flex size-7 items-center justify-center rounded-md bg-surface-tertiary text-muted">
						<Layers className="size-3.5" />
					</span>
					<div className="min-w-0">
						<div className="truncate text-sm font-medium">General</div>
						<div className="text-xs text-muted">Workspace</div>
					</div>
					<span className="ml-auto size-2 rounded-full bg-success/60" aria-hidden="true" />
				</div>
			</div>
		</aside>
	)
}
