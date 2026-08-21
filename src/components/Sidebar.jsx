import { Button, Tooltip, IconPlus } from '@heroui/react'

function ActionButton({ label, onPress, children }) {
	return (
		<Tooltip.Root>
			<Tooltip.Trigger>
				<Button isIconOnly variant="flat" aria-label={label} onClick={onPress} className="text-base">
					{children}
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
	onAdd,
	onSwitch,
	onDelete,
	onSettings,
	onExport,
	onImport,
}) {
	return (
		<aside className="flex h-full w-48 shrink-0 flex-col border-r border-zinc-700 bg-zinc-950/60 p-2">
			<Button
				isFullWidth
				variant="flat"
				onClick={onAdd}
				startContent={<IconPlus className="size-4" />}
				className="mb-2"
			>
				{newSheetLabel}
			</Button>

			<nav className="numlex-sheets flex min-h-0 flex-1 flex-col gap-1 overflow-y-auto">
				{sheets.map((sheet, index) => (
					<div
						key={`${sheet.title}-${index}`}
						role="button"
						tabIndex={0}
						onClick={() => onSwitch(index)}
						onKeyDown={(e) => {
							if (e.key === 'Enter' || e.key === ' ') onSwitch(index)
						}}
						className={`group relative flex cursor-pointer flex-col rounded-md px-3 py-1.5 text-sm outline-none transition-colors ${
							index === activeIndex
								? 'bg-zinc-700/70 text-zinc-50'
								: 'text-zinc-400 hover:bg-zinc-800/70'
						}`}
					>
						<span className="truncate font-medium">{sheet.title}</span>
						{sheet.createdAt && (
							<span className="truncate text-xs text-zinc-500">{sheet.createdAt}</span>
						)}
						{index === activeIndex && (
							<button
								type="button"
								aria-label="Delete sheet"
								onClick={(e) => {
									e.stopPropagation()
									onDelete(index)
								}}
								className="absolute right-1.5 top-1/2 -translate-y-1/2 rounded px-1 text-zinc-400 opacity-70 hover:text-red-400"
							>
								&times;
							</button>
						)}
					</div>
				))}
			</nav>

			<div className="mt-2 flex gap-1">
				<ActionButton label="Settings" onPress={onSettings}>
					&#9881;
				</ActionButton>
				<ActionButton label="Export sheet (.nlx)" onPress={onExport}>
					&#8681;
				</ActionButton>
				<ActionButton label="Import sheet (.nlx)" onPress={onImport}>
					&#8679;
				</ActionButton>
			</div>
		</aside>
	)
}
