import { Card } from '@heroui/react'

function formatNumber(value) {
	return String(value)
}

function OutputRow({ row }) {
	const base = 'flex min-h-[var(--numlex-line-height)] items-center justify-end gap-1.5 px-4 sm:px-5'
	switch (row.kind) {
		case 'skip':
		case 'blank':
			return <div className={base} aria-hidden="true" />
		case 'title':
			return (
				<div className={base}>
					<span className="truncate text-sm font-semibold tracking-tight text-foreground">
						{row.text}
					</span>
				</div>
			)
		case 'number':
			return (
				<div className={base}>
					<span className="text-[15px] font-medium leading-none tabular-nums text-foreground">
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
					<span className="text-[15px] font-medium leading-none tabular-nums text-success">
						{formatNumber(row.value)}
					</span>
				</div>
			)
		case 'error':
			return (
				<div className={base}>
					<span className="text-xs font-medium text-danger" title={row.message || 'Error'}>
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
		<div className="flex h-40 shrink-0 flex-col overflow-hidden border-t border-border bg-surface sm:h-auto sm:w-[280px] sm:border-l sm:border-t-0">
			<div
				ref={innerRef}
				className="numlex-output flex-1 overflow-auto pt-6"
				aria-label="Results"
			>
				{rows.map((row, index) => (
					<OutputRow key={index} row={row} />
				))}
			</div>
			{summary && (
				<div className="border-t border-border/60 bg-surface p-3">
					<Card className="border border-border/50 bg-surface-secondary/70 px-4 py-3 shadow-sm">
						<div className="flex items-baseline justify-between gap-2">
							<span className="text-xs font-medium uppercase tracking-wider text-muted">
								{summary.label}
							</span>
							<span className="text-sm font-semibold tabular-nums text-foreground">
								{summary.value}
								{summary.unit && <span className="ml-1 text-xs font-normal text-muted">{summary.unit}</span>}
							</span>
						</div>
						{summary.detail && <div className="mt-1 text-xs text-muted">{summary.detail}</div>}
					</Card>
				</div>
			)}
		</div>
	)
}
