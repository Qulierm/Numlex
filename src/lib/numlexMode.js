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

// Token styles matching the legacy palette.
export const numlexHighlighting = syntaxHighlighting(
	HighlightStyle.define([
		{ tag: t.comment, color: 'grey' },
		{ tag: toTag, color: '#F75F8F' },
		{ tag: t.number, color: '#52A8FF' },
		{ tag: t.operator, color: 'white' },
		{ tag: declaredTag, color: '#4FBF63' },
		{ tag: usedTag, color: '#4FBF63' },
	])
)

export const numlexTheme = EditorView.baseTheme({
	'&.cm-editor': { backgroundColor: 'transparent' },
	'.cm-gutters': { backgroundColor: 'transparent', border: 'none' },
	'.cm-activeLine': { backgroundColor: 'transparent' },
	'.cm-selectionBackground, ::selection': { backgroundColor: '#3d3d3e !important' },
})
