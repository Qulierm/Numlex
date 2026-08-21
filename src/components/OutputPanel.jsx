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
			return <div className="mb-1 font-semibold text-zinc-100">{row.text}</div>
		case 'number':
			return (
				<div className="text-sky-300">
					{formatNumber(row.value)}
					{row.unit ? ` ${row.unit}` : ''}
				</div>
			)
		case 'variable':
			return (
				<div className="text-emerald-400">
					{row.name} = {formatNumber(row.value)}
				</div>
			)
		case 'error':
			return <div className="text-red-400">Error</div>
		default:
			return null
	}
}

export function OutputPanel({ rows, innerRef }) {
	return (
		<div
			ref={innerRef}
			className="numlex-output h-full w-44 shrink-0 overflow-auto border-l border-zinc-700 bg-zinc-900 px-3 py-2 text-sm"
		>
			{rows.map((row, index) => (
				<OutputRow key={index} row={row} />
			))}
		</div>
	)
}
