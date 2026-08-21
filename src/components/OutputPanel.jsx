function formatNumber(value) {
	return String(value)
}

// One answer row. Every row occupies exactly the notebook line height so the
// column stays vertically aligned with the editor even for lines that have
// no result (skip/blank/title rows reserve the same space).
function OutputRow({ row }) {
	const base = 'flex h-[var(--numlex-line-height)] items-center justify-end gap-1.5 px-4 sm:px-5'
	switch (row.kind) {
		case 'skip':
		case 'blank':
			return <div className={base} aria-hidden="true" />
		case 'title':
			return (
				<div className={base}>
					<span className="truncate text-sm font-semibold tracking-wide text-foreground">
						{row.text}
					</span>
				</div>
			)
		case 'number':
			return (
				<div className={base}>
					<span className="text-[15px] font-medium leading-none tabular-nums text-accent">
						{formatNumber(row.value)}
					</span>
					{row.unit && <span className="text-xs text-muted">{row.unit}</span>}
				</div>
			)
		case 'variable':
			return (
				<div className={base}>
					<span className="text-sm text-foreground">{row.name}</span>
					<span className="text-sm text-muted">=</span>
					<span className="text-[15px] font-medium leading-none tabular-nums text-success">
						{formatNumber(row.value)}
					</span>
				</div>
			)
		case 'error':
			return (
				<div className={base}>
					<span className="text-xs font-medium text-danger">Error</span>
				</div>
			)
		default:
			return <div className={base} aria-hidden="true" />
	}
}

export function OutputPanel({ rows, innerRef }) {
	return (
		<div
			ref={innerRef}
			className="numlex-output h-40 shrink-0 overflow-auto border-t border-border bg-surface pt-4 sm:h-auto sm:w-64 sm:border-l sm:border-t-0"
			aria-label="Results"
		>
			{rows.map((row, index) => (
				<OutputRow key={index} row={row} />
			))}
		</div>
	)
}
