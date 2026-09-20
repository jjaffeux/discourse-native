# Mobile composer

The touch composer fills the page's available safe area above the keyboard.
The reader stays mounted offstage, and the existing editor survives keyboard
resizes and minimize/restore. Desktop docking and sizing are unchanged.

The header contains save-and-close, draft status, a compact actions menu, and
an icon-only + submission button. The button retains the mode-specific accessible
label, validation, loading state and retry behavior. Minimize, discard and return
to topic remain available through the actions menu; whisper and plugin controls
remain available in the header.

Categories, subcategories and tags occupy a horizontally scrollable row above
the writing toolbar. Individual selectors are constrained to the viewport width.
Writing actions use Native transparent buttons on touch. Plugin footer controls
and validation/draft warnings retain their existing behavior.

Design reference: `mockups/mobile-composer.html`.

Validation: 126 focused widget checks passed covering docking, keyboard insets,
large text, draft/editor preservation, submission, close/discard safety, taxonomy
pickers, toolbar actions and shared control styling. Static analysis passed.
A production-widget render was inspected at 390 × 800 with a 330px simulated
keyboard inset, in dark mode with Arial loaded for the render. This was a Flutter
widget-test render, not an iOS simulator or physical-device run.
