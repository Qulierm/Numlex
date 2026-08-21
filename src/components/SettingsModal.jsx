import { Modal, Select, TextField, Switch, IconChevronDown } from '@heroui/react'
import { ListBox, ListBoxItem } from 'react-aria-components/Select'
import { LANGUAGES } from '../lib/translations'

const selectItemClass =
	'cursor-pointer rounded-md px-3 py-1.5 text-sm text-zinc-200 outline-none data-[selected=true]:bg-zinc-700 hover:bg-zinc-700/60'

function SettingSelect({ label, value, options, onValueChange }) {
	return (
		<div className="flex flex-col gap-1">
			<span className="text-xs text-zinc-400">{label}</span>
			<Select.Root
				selectedKey={value}
				onSelectionChange={(key) => onValueChange(String(key))}
			>
				<Select.Trigger className="w-full" aria-label={label}>
					<Select.Value className="text-left text-sm" />
					<Select.Indicator>
						<IconChevronDown className="size-4" />
					</Select.Indicator>
				</Select.Trigger>
				<Select.Popover className="z-50 min-w-full rounded-md bg-zinc-800 p-1 shadow-lg">
					<ListBox>
						{options.map((option) => (
							<ListBoxItem key={option.id} id={option.value} className={selectItemClass}>
								{option.label}
							</ListBoxItem>
						))}
					</ListBox>
				</Select.Popover>
			</Select.Root>
		</div>
	)
}

const ROUNDING_OPTIONS = [1, 2, 3, 4, 5, 6, 7].map((n) => ({ id: String(n), value: String(n), label: String(n) }))
const FONT_SIZE_OPTIONS = ['ttt', 'tt', 'tf', 'tff', 'ts', 'tss', 'te', 'tn', 'tth'].map((value, i) => ({
	id: value,
	value,
	label: `${22 + i} px`,
}))

export function SettingsModal({ open, onOpenChange, settings, onChange, translations: t }) {
	const set = (patch) => onChange({ ...settings, ...patch })

	return (
		<Modal.Root isOpen={open} onOpenChange={onOpenChange}>
			<Modal.Backdrop />
			<Modal.Container className="max-w-sm">
				<Modal.Dialog>
				<Modal.Header className="flex items-center justify-between">
					<Modal.Heading className="text-lg">{t.settings}</Modal.Heading>
					<Modal.CloseTrigger aria-label="Close settings" className="text-zinc-400" />
				</Modal.Header>
				<Modal.Body className="flex flex-col gap-4">
					<SettingSelect
						label={t.round}
						value={String(settings.decimalPlaces)}
						options={ROUNDING_OPTIONS}
						onValueChange={(v) => set({ decimalPlaces: Number(v) })}
					/>
					<SettingSelect
						label={t.fontsize}
						value={settings.fontSize}
						options={FONT_SIZE_OPTIONS}
						onValueChange={(v) => set({ fontSize: v })}
					/>
					<SettingSelect
						label={t.language}
						value={settings.language}
						options={LANGUAGES}
						onValueChange={(v) => set({ language: v })}
					/>
					<TextField
						label={t.sheetname}
						value={settings.sheetName}
						onChange={(v) => set({ sheetName: v })}
					/>
					<Switch.Root
						isSelected={settings.lineNumbers}
						onChange={(v) => set({ lineNumbers: v })}
						className="flex w-full items-center justify-between"
					>
						<span className="text-sm text-zinc-300">{t.linenumber}</span>
						<Switch.Content>
							<Switch.Control>
								<Switch.Thumb />
							</Switch.Control>
						</Switch.Content>
					</Switch.Root>
				</Modal.Body>
				</Modal.Dialog>
			</Modal.Container>
		</Modal.Root>
	)
}
