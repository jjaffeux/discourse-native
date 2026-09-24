# Project agent instructions

## UI kit usage

- All application UI components must use the project's Native component library (the UI kit), imported through `package:discourse_native/discourse_ui.dart`. This is mandatory for every screen, plugin, toolbar, dialog, picker, menu, and styleguide example. Follow `docs/component-library/conventions.md` and consult the styleguide and catalogue before choosing or implementing UI.
- Use `DButton`/`DButton.iconOnly` for actions, `DToggle`/`DToggleGroup` for toggle controls, `DSelect`/`DCombobox` for selections, and `DDropdownMenu`/`DContextMenu` for menus. Other controls and visual components must use their corresponding Native components.
- Do not use raw Material or Cupertino controls, introduce another component library, or build bespoke replacements. Existing code and old migration exceptions are not permission to bypass the UI kit. Raw framework controls belong only inside the UI kit's implementation.
- Flutter layout, text, focus, and semantics primitives may compose Native components; they must not recreate a control's appearance or interaction. The kit owns control sizes, states, hover/focus styling, loading indicators, and accessible targets. Use its existing variants and size presets instead of local control geometry.
- If the UI kit does not contain a component needed for the requested work, or an existing component lacks a required option or behavior, stop and ask the user how they want to proceed. Do not add, extend, substitute, or work around the component without the user's direction.

## Running tests

- Only run the tests added for the task and the tests directly related to the code it changes (typically the `foo_test.dart` beside a changed `foo.dart`, plus any suite that pins the touched behavior). Run them by file path, e.g. `flutter test test/foo_test.dart`.
- Do not run the full test suite (`flutter test` with no paths). CI runs the full suite; locally it is slow and not required to finish a task.

## Git worktree conventions

- When the user says "merge in main from a worktree," merge the worktree's branch into the repository's `main` branch from the repository's main checkout. Do not perform the final merge inside the worktree and do not merge `main` into the worktree.
