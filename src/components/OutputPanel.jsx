import { Card } from '@heroui/react'

function formatNumber(value) {
	if (value == null || Number.isNaN(value)) return ''
	if (Number.isInteger(value)) return value.toLocaleString('en-US')
	return String(value)
}

function OutputRow({ row }) {
	const base = 'flex min-h-[var(--numlex-line-height)] items-center justify-end gap-1.5 px-4 sm:px-5'
	switch (row.kind) {
		case 'skip':
		case 'blank':
			return <div className={base} aria-hidden="true" />
		case 'title':
			return <div className={base} aria-hidden="true" />
		case 'number':
			return (
				<div className={base}>
					<span className="text-[17px] font-medium leading-none tabular-nums text-foreground">
						{formatNumber(row.value)}
					</span>
					{row.unit && <span className="text-xs font-normal text-muted">{row.unit}</span>}
				</div>
			)
		case 'variable':
			return (
				<div className={base}>
					<span className="text-sm text-foreground">{row.name}</span>
					<span className="text-sm text-muted">=</span>
					<span className="text-[17px] font-medium leading-none tabular-nums text-success">
						{formatNumber(row.value)}
					</span>
				</div>
			)
		case 'error':
			return (
				<div className={base}>
					<span className="text-xs font-normal text-muted" title={row.message || 'Error'}>
						{row.message === 'Rates unavailable' ? 'Rates unavailable' : 'Error'}
					</span>
				</div>
			)
		default:
			return <div className={base} aria-hidden="true" />
	}
}

export function OutputPanel({ rows, innerRef, summary }) {
	return (
		<div className="flex h-40 shrink-0 flex-col overflow-hidden border-t border-border bg-surface sm:h-auto sm:w-[200px] sm:border-l sm:border-t-0">
			<div
				ref={innerRef}
				className="numlex-output flex-1 overflow-auto pt-5"
				aria-label="Results"
			>
				{rows.map((row, index) => (
					<OutputRow key={index} row={row} />
				))}
			</div>
			{summary && (
				<div className="border-t border-border/40 bg-surface-secondary/20 p-2.5">
					<Card className="rounded-lg border border-border/50 bg-surface-secondary/30 px-3 py-2 shadow-none">
						<div className="flex items-center justify-between gap-2">
							<span className="text-xs font-normal text-muted">{summary.label}</span>
							<span className="text-sm font-medium tabular-nums text-foreground">
								{summary.value}
								{summary.unit && <span className="ml-1 text-xs font-normal text-muted">{summary.unit}</span>}
							</span>
						</div>
						{summary.detail ? <div className="mt-1 text-xs text-muted">{summary.detail}</div> : null}
					</Card>
				</div>
			)}
		</div>
	)
}
