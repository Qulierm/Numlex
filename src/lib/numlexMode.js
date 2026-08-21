// CodeMirror 6 stream language mirroring the legacy CodeMirror 5 "custom" mode:
// # comments, "to" keyword, numbers, operators, declared variables.
import { StreamLanguage, HighlightStyle, syntaxHighlighting } from '@codemirror/language'
import { tags as t } from '@lezer/highlight'
import { EditorView } from '@codemirror/view'

const toTag = t.keyword
const declaredTag = t.definition(t.variableName)
const usedTag = t.variableName

// getDeclared returns the current {name: true} map of declared variables
// (recomputed on every editor change), so highlighting stays in sync.
export function createNumlexLanguage(getDeclared) {
	return StreamLanguage.define({
		name: 'numlex',
		token(stream) {
			if (stream.match(/^#.*$/)) return 'comment'
			if (stream.match(/^\/\/.*$/)) return 'comment'
			if (stream.match(/\bto\b/)) return 'numlexTo'
			if (stream.match(/^\d+(?:\.\d+)?/)) return 'number'
			if (stream.match(/^[+\-*/^%]/)) return 'operator'
			if (stream.match(/^[a-zA-Z_]\w*/)) {
				const declared = getDeclared()
				if (declared && declared[stream.current()]) return 'numlexDeclared'
				return null
			}
			stream.next()
			return null
		},
		blankLine() {},
		tokenTable: {
			comment: t.comment,
			numlexTo: toTag,
			number: t.number,
			operator: t.operator,
			numlexDeclared: [declaredTag, usedTag],
		},
	})
}

// Token styles on the HeroUI semantic tokens, with a soft pink for the
// "to" conversion keyword (kept from the legacy palette).
export const numlexHighlighting = syntaxHighlighting(
	HighlightStyle.define([
		{ tag: t.comment, color: 'var(--muted)' },
		{ tag: toTag, color: '#e56da2' },
		{ tag: t.number, color: 'var(--accent)' },
		{ tag: t.operator, color: 'var(--foreground)' },
		{ tag: declaredTag, color: 'var(--success)' },
		{ tag: usedTag, color: 'var(--success)' },
	])
)

export const numlexTheme = EditorView.baseTheme({
	'&.cm-editor': { backgroundColor: 'transparent' },
	'&': { color: 'var(--foreground)' },
	'.cm-content': {
		/* Top padding matches the answer column (pt-4 = 16px) for row alignment. */
		padding: '16px 0 96px',
		caretColor: 'var(--accent)',
	},
	'.cm-line': { padding: '0 32px 0 40px' },
	'.cm-placeholder': { color: 'var(--muted)' },
	'.cm-gutters': {
		backgroundColor: 'transparent',
		border: 'none',
		color: 'var(--muted)',
		font: '11px/normal ui-monospace, SFMono-Regular, Menlo, monospace',
		paddingLeft: '12px',
	},
	'.cm-activeLine': { backgroundColor: 'transparent' },
	'.cm-activeLineGutter': { backgroundColor: 'transparent' },
	'.cm-selectionBackground, ::selection': {
		backgroundColor: 'color-mix(in oklab, var(--accent) 22%, transparent) !important',
	},
	'&.cm-focused': { outline: 'none' },
})
