import { Button, ListBox, ScrollShadow, Tooltip } from '@heroui/react'
import { Layers, Plus, Trash2, X } from 'lucide-react'

export function Sidebar({
	sheets,
	activeIndex,
	newSheetLabel,
	deleteLabel,
	closeLabel,
	sheetsLabel,
	onAdd,
	onSwitch,
	onDelete,
	onClose,
}) {
	return (
		<aside
			className="fixed top-11 bottom-0 left-0 z-40 flex w-72 shrink-0 flex-col border-r border-border bg-surface lg:static lg:top-auto"
			aria-label={sheetsLabel}
		>
			<div className="p-3 pb-2">
				<Button fullWidth onClick={onAdd} className="rounded-xl bg-accent text-white hover:bg-accent/90">
					<Plus className="size-4" />
					{newSheetLabel}
				</Button>
			</div>

			<div className="flex items-center gap-2 px-4 py-2">
				<span className="text-[11px] font-medium uppercase tracking-wider text-muted">{sheetsLabel}</span>
				<span className="text-[11px] text-muted">{sheets.length}</span>
				<Button
					isIconOnly
					variant="ghost"
					size="sm"
					aria-label={closeLabel}
					onClick={onClose}
					className="ml-auto lg:hidden"
				>
					<X className="size-4" />
				</Button>
			</div>

			<div className="min-h-0 flex-1 px-2">
				<ScrollShadow className="h-full" hideScrollBar>
					<ListBox
						className="numlex-sheets max-h-full overflow-y-auto p-1"
						aria-label={sheetsLabel}
						selectionMode="single"
						selectionBehavior="replace"
						selectedKey={String(activeIndex)}
						onSelectionChange={(sel) => {
							const key = sel instanceof Set ? [...sel][0] : sel
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
									className={`group mb-1 rounded-xl border px-3 py-2.5 text-left ${isActive ? 'border-border bg-surface-secondary shadow-sm' : 'border-transparent bg-transparent hover:bg-surface-secondary/70'}`}
								>
									<div className="flex items-start justify-between gap-2">
										<span className="min-w-0 flex-1 truncate text-sm font-medium leading-tight">
											{sheet.title}
										</span>
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
											className={`rounded p-1 text-muted transition-opacity hover:text-danger ${isActive ? 'opacity-60 group-hover:opacity-100 focus:opacity-100' : 'opacity-0 group-hover:opacity-100 focus:opacity-100'}`}
										>
											<Tooltip.Root>
												<Tooltip.Trigger as="span">
													<Trash2 className="size-3.5" />
												</Tooltip.Trigger>
												<Tooltip.Content>{deleteLabel}</Tooltip.Content>
											</Tooltip.Root>
										</span>
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

			<div className="border-t border-border/60 p-3">
				<div className="flex items-center gap-2.5 rounded-lg border border-border/40 bg-surface-secondary/40 px-3 py-2.5">
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
