import { Modal, Select, ListBox, Label, TextField, Input, Switch } from '@heroui/react'
import { LANGUAGES } from '../lib/translations'

const ROUNDING_OPTIONS = [1, 2, 3, 4, 5, 6, 7].map((n) => ({ id: String(n), value: String(n), label: String(n) }))
const FONT_SIZE_OPTIONS = ['ttt', 'tt', 'tf', 'tff', 'ts', 'tss', 'te', 'tn', 'tth'].map((value, i) => ({
	id: value,
	value,
	label: `${22 + i} px`,
}))

function SectionLabel({ children }) {
	return (
		<span className="text-[11px] font-medium uppercase tracking-wider text-muted">{children}</span>
	)
}

function SettingSelect({ label, value, options, onValueChange }) {
	return (
		<Select.Root
			fullWidth
			selectedKey={value}
			onSelectionChange={(key) => onValueChange(String(key))}
		>
			<Label>{label}</Label>
			<Select.Trigger className="bg-surface-tertiary">
				<Select.Value />
				<Select.Indicator />
			</Select.Trigger>
			<Select.Popover className="z-50">
				<ListBox aria-label={label}>
					{options.map((option) => (
						<ListBox.Item key={option.id} id={option.value}>
							{option.label}
						</ListBox.Item>
					))}
				</ListBox>
			</Select.Popover>
		</Select.Root>
	)
}

export function SettingsModal({ open, onOpenChange, settings, onChange, translations: t }) {
	const set = (patch) => onChange({ ...settings, ...patch })

	return (
		<Modal.Root isOpen={open} onOpenChange={onOpenChange}>
			{/* DialogTrigger needs a pressable first child; the top bar gear button is the visual trigger. */}
			<Modal.Trigger className="sr-only" aria-label="Open settings">Open settings</Modal.Trigger>
			<Modal.Backdrop>
				<Modal.Container className="max-w-md">
					<Modal.Dialog>
						<Modal.Header>
							<Modal.Heading>{t.settings}</Modal.Heading>
							<Modal.CloseTrigger />
						</Modal.Header>
						<Modal.Body className="flex flex-col gap-5">
							<section className="flex flex-col gap-3">
								<SectionLabel>Results</SectionLabel>
								<SettingSelect
									label={t.round}
									value={String(settings.decimalPlaces)}
									options={ROUNDING_OPTIONS}
									onValueChange={(v) => set({ decimalPlaces: Number(v) })}
								/>
							</section>
							<section className="flex flex-col gap-3">
								<SectionLabel>Editor</SectionLabel>
								<SettingSelect
									label={t.fontsize}
									value={settings.fontSize}
									options={FONT_SIZE_OPTIONS}
									onValueChange={(v) => set({ fontSize: v })}
								/>
								<Switch.Root isSelected={settings.lineNumbers} onChange={(v) => set({ lineNumbers: v })}>
									<Switch.Content>
										<Switch.Control>
											<Switch.Thumb />
										</Switch.Control>
										<Label className="text-sm">{t.linenumber}</Label>
									</Switch.Content>
								</Switch.Root>
							</section>
							<section className="flex flex-col gap-3">
								<SectionLabel>General</SectionLabel>
								<SettingSelect
									label={t.language}
									value={settings.language}
									options={LANGUAGES}
									onValueChange={(v) => set({ language: v })}
								/>
								<TextField fullWidth>
									<Label>{t.sheetname}</Label>
									<Input
										className="bg-surface-tertiary"
										value={settings.sheetName}
										onChange={(e) => set({ sheetName: e.target.value })}
									/>
								</TextField>
							</section>
						</Modal.Body>
					</Modal.Dialog>
				</Modal.Container>
			</Modal.Backdrop>
		</Modal.Root>
	)
}
