function formatNumber(value) {
	return String(value)
}

function OutputRow({ row }) {
	switch (row.kind) {
		case 'skip':
			return null
		case 'blank':
			return <div className="h-4" />
		case 'title':
			return <div className="mb-1 font-semibold text-foreground">{row.text}</div>
		case 'number':
			return (
				<div className="text-accent">
					{formatNumber(row.value)}
					{row.unit ? ` ${row.unit}` : ''}
				</div>
			)
		case 'variable':
			return (
				<div className="text-success">
					{row.name} = {formatNumber(row.value)}
				</div>
			)
		case 'error':
			return <div className="text-danger">Error</div>
		default:
			return null
	}
}

export function OutputPanel({ rows, innerRef }) {
	return (
		<div
			ref={innerRef}
			className="numlex-output h-full w-48 shrink-0 overflow-auto border-l border-border bg-background px-3 py-2 text-sm"
		>
			{rows.length === 0 ? null : rows.map((row, index) => (
				<OutputRow key={index} row={row} />
			))}
		</div>
	)
}
