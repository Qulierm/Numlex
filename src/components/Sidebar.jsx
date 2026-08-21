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
			className="flex h-full w-[214px] shrink-0 flex-col border-r border-border bg-surface"
			aria-label={sheetsLabel}
		>
			<div className="p-2 pb-2">
				<Button
					fullWidth
					size="sm"
					variant="solid"
					onPress={onAdd}
					className="h-8 rounded-lg bg-accent text-white hover:bg-accent/90 text-sm"
				>
					<Plus className="size-3.5" />
					{newSheetLabel}
				</Button>
			</div>

			<div className="flex items-center gap-2 px-4 py-2">
				<span className="text-[11px] font-medium uppercase tracking-wider text-muted">{sheetsLabel}</span>
				<span className="text-[11px] text-muted">{sheets.length}</span>
				<Tooltip.Root>
					<Tooltip.Trigger className="ml-auto min-[720px]:hidden">
						<Button
							isIconOnly
							variant="ghost"
							size="sm"
							aria-label={closeLabel}
							onPress={onClose}
						>
							<X className="size-4" />
						</Button>
					</Tooltip.Trigger>
					<Tooltip.Content>{closeLabel}</Tooltip.Content>
				</Tooltip.Root>
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
							const lineCount = sheet.content ? sheet.content.split('\n').length : 1
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
									<span className="mt-1 flex items-center gap-1.5 text-xs text-muted">
										{sheet.createdAt && <span>{sheet.createdAt}</span>}
										{sheet.createdAt && <span className="opacity-50">•</span>}
										<span>
											{lineCount} {lineCount === 1 ? 'line' : 'lines'}
										</span>
									</span>
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
