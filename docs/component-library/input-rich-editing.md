# Borderless document editing

`DInput(borderless: true, maxLines: null)` grows with rich multiline content.
Use `expands: true` with those options when the parent supplies a bounded editing
viewport. Ordinary bordered inputs remain single-line; multiline form fields use
`DTextarea`.

The composer borrows its Markdown controller, focus node and scroll controller.
`strutStyle` lets projected widgets contribute their full height; `showCursor`,
`mouseCursor` and `onTapAlwaysCalled` retain the rich editor's caret and hit-testing
behavior. These options delegate to the existing input's native editing engine.
The surrounding composer continues to own syntax, selection mapping and undo.

The Input styleguide includes a growing inline example. Regression tests verify
content growth, preserved IME composition and focus, and scrolling inside a
bounded expanding viewport. The production composer fixture also exercises
multiline tasks in light/narrow and dark/wide macOS layouts.
