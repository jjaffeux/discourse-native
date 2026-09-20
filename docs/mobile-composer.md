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

## Long drafts

On touch, the title, reply context and growing body share one scroll viewport.
The close, draft and publish controls stay pinned above that content, with no
visible scrollbar. Taxonomy and writing tools stay above the keyboard. Moving
the caret to either end of a long draft scrolls the outer viewport to reveal it.
The editor continues to refresh media and slash-menu anchors during outer scroll.

Follow-up validation: 115 focused checks passed, including fixed header/footer
bounds while scrolling, hidden scrollbars, zero inner editor scroll extent, and
caret visibility at both ends of a long draft. Static analysis passed. Inspected
a dark-mode widget render of the scrolled draft with the same viewport and font
configuration described above.

## Quiet autosave

Routine saving/saved indicators are hidden on mobile and desktop. Autosave
continues unchanged; local and remote save failures remain visible.

## Capsule toolbar and keyboard backing

The mobile writing toolbar uses the approved `DCardVariant.capsule` surface:
a continuous rounded outline, subtly tinted fill, and kit-owned insets. Existing
actions keep their Native controls and scroll horizontally when needed. Desktop
cards and the desktop composer retain their previous appearance.

The mobile shell Scaffold and outer composer footer use `shell.content`, matching
the composer behind the keyboard's rounded upper corners. Light/dark widget
checks cover that backing color. A separate native macOS fixture with the iOS
control theme was inspected at 390px width in light/dark modes, including toolbar
overflow, the Insert menu, and the capsule Card styleguide example. The iOS system
keyboard itself was not inspected on a physical device.
