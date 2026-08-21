import { Button, ListBox, ScrollShadow, Tooltip } from '@heroui/react'
import { Plus, Trash2, X } from 'lucide-react'

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
			className="fixed top-12 bottom-0 left-0 z-40 flex w-72 shrink-0 flex-col border-r border-border bg-surface lg:static lg:top-auto"
			aria-label={sheetsLabel}
		>
			<div className="flex items-center gap-2 px-4 pb-1 pt-3">
				<span className="text-[11px] font-medium uppercase tracking-wider text-muted">
					{sheetsLabel}
				</span>
				<span className="text-[11px] text-muted">{sheets.length}</span>
				<Button
					isIconOnly
					variant="ghost"
					aria-label={closeLabel}
					onClick={onClose}
					className="ml-auto lg:hidden"
				>
					<X className="size-4" />
				</Button>
			</div>

			<div className="min-h-0 flex-1 px-2 pt-1">
				<ScrollShadow className="h-full">
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
						{sheets.map((sheet, index) => (
							<ListBox.Item
								key={`${sheet.title}-${index}`}
								id={String(index)}
								textValue={sheet.title}
								className={`group rounded-lg py-2 ${index === activeIndex ? 'bg-surface-secondary' : ''}`}
							>
								<span className="flex items-center gap-1 pr-1">
									<span className="min-w-0 flex-1 truncate text-sm font-medium">
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
										className="rounded p-0.5 text-muted opacity-0 transition-opacity hover:text-danger group-hover:opacity-100 focus:opacity-100"
									>
										<Tooltip.Root>
											<Tooltip.Trigger as="span">
												<Trash2 className="size-3.5" />
											</Tooltip.Trigger>
											<Tooltip.Content>{deleteLabel}</Tooltip.Content>
										</Tooltip.Root>
									</span>
								</span>
								{sheet.createdAt && (
									<span className="mt-0.5 block truncate px-0.5 text-xs text-muted">
										{sheet.createdAt}
									</span>
								)}
							</ListBox.Item>
						))}
					</ListBox>
				</ScrollShadow>
			</div>

			<div className="p-3">
				<Button fullWidth variant="flat" onClick={onAdd} className="rounded-lg">
					<Plus className="size-4" />
					{newSheetLabel}
				</Button>
			</div>
		</aside>
	)
}
