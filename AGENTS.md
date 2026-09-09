# Project agent instructions

## UI kit usage

- For all application UI work, always use the project's Native component library (the UI kit) through `package:discourse_native/discourse_ui.dart`. Follow the component-library guidance in `docs/component-library/conventions.md` and consult the styleguide and catalogue before choosing or implementing UI.
- Do not create a bespoke widget, use a raw Material or Cupertino control, or introduce another component library when the Native component library already provides the required component or behavior.
- If the UI kit does not contain a component needed for the requested work, or an existing component lacks a required option or behavior, stop and ask the user how they want to proceed. Do not add, extend, substitute, or work around the component without the user's direction.

## Git worktree conventions

- When the user says "merge in main from a worktree," merge the worktree's branch into the repository's `main` branch from the repository's main checkout. Do not perform the final merge inside the worktree and do not merge `main` into the worktree.
