import { useMemo, useRef } from 'react'
import CodeMirror from '@uiw/react-codemirror'
import { EditorView, keymap, lineNumbers as lineNumbersExtension } from '@codemirror/view'
import { createNumlexLanguage, numlexHighlighting, numlexTheme } from '../lib/numlexMode'
import { declaredVariables } from '../lib/evaluate'

// Legacy operator auto-spacing: typing + - * / ^ inserts " op " when the
// character before the cursor is not a space.
function autoSpace(key) {
	return (view) => {
		const head = view.state.selection.main.head
		const line = view.state.doc.lineAt(head)
		const before = line.text.slice(0, head - line.from)
		if (before.endsWith(' ')) return false
		view.dispatch({
			changes: { from: head, to: head, insert: ` ${key} ` },
			selection: { anchor: head + 3 },
			scrollIntoView: true,
		})
		return true
	}
}

const autoSpaceKeymap = keymap.of(
	['+', '-', '*', '/', '^'].map((key) => ({ key, preventDefault: true, run: autoSpace(key) }))
)

export function EditorPane({ value, onChange, placeholder, lineNumbers, onCreateView }) {
	const declaredRef = useRef({})
	// The language extension reads declaredRef live, so one instance suffices.
	const language = useMemo(() => createNumlexLanguage(() => declaredRef.current), [])

	const extensions = useMemo(() => {
		const exts = [
			language,
			numlexHighlighting,
			numlexTheme,
			EditorView.lineWrapping,
			autoSpaceKeymap,
			EditorView.theme({
				'&': { color: '#f8f8f2' },
				'.cm-content': { padding: '10px 4px' },
				'.cm-line': { padding: '0 10px' },
			}),
		]
		if (lineNumbers) exts.push(lineNumbersExtension())
		return exts
	}, [language, lineNumbers])

	return (
		<div className="relative h-full">
			<CodeMirror
				value={value}
				height="100%"
				theme="none"
				placeholder={placeholder}
				extensions={extensions}
				basicSetup={{
					lineNumbers: false,
					foldGutter: false,
					autocompletion: false,
					highlightActiveLine: false,
					tooltip: false,
				}}
				onChange={(next) => {
					declaredRef.current = declaredVariables(next)
					onChange(next)
				}}
				onCreateEditor={(view) => {
					onCreateView?.(view)
				}}
			/>
		</div>
	)
}
