# Composer and quote delta audit, 9 October 2026

Reference: `discourse-native-mockups` at `c39ad5079e36ccd40a2604c43b513195d5c125a2`,
following the already-ported `54ba01c` baseline. App audit starts at
`84262ec969196fdc567746882fec46b0b375798b`.

| Source commit | Final contract and Native audit |
| --- | --- |
| `584ad71` | Brings the mockup editor to the app's established rich Markdown editor behavior. Native already has real block editing/reordering, selection formatting, code languages, slash and mention/hashtag/emoji suggestions, plugin-owned date/poll/table workflows, uploads, media resizing, undo/redo, draft storage, title/body navigation, and account-scoped retained draft tabs/placement. Preserve these implementations. |
| `614b4d2` | Introduces the deleted-draft grain dissolve. Superseded in full by `9559219`; it is not the final design. |
| `9559219` | Removes preparation, grain rendering, timers, and the delete callback wrapper. Final `Composer.onDelete` calls `onDiscard()` directly. Keep Native's discard operation/revision/account guards and failed-delete retry behavior. |
| `d3d9e66` | Joins the attributed composer quote header, body, and footer into a single surface. Native's atomic quote preview already has one continuous box. |
| `7308ec3` | Changes attributed post/composer quote boxes to 12px rounded corners, a 3px accent mark inset 11px from the box edges, 25px leading content inset, and a muted decorative quote-right icon. User-card targets belong to the user-card group. |

Final source checked in `src/App.tsx` (`PostBlock`, `projectMarkup`, `Composer`)
and `src/app.css` (`cm-bquote-headbox`, `cm-bquote-body`, `cm-bquote-end`). Plain
Markdown `>` quote rules remain a separate final-mockup treatment. Do not change
the editable line projection or nesting geometry merely to restyle attributed
quotes.

The mockup's replay of typing on opening a draft and undo/redo remains a visual
simulation; Native retains its source-owned transactional editing history.

A separate saved-draft UX was **newly introduced in `584ad71`**, and remains at
`c39ad50`: `ComposerCloseChoice` gains a saved/changed distinction, a
"Discard changes" action restoring the saved title/body separately from
"Delete draft", an in-place hover/focus diff via `previewDiscard`, and animated
restoration via `revertTo` before closing. The baseline `54ba01c` has only
save/discard/cancel. This is an actual remaining draft UX gap, not fixture data.
Native's autosave and close safety do not currently maintain a separate immutable
saved snapshot. Implementing this needs a Native diff-preview capability and a
safe savepoint/rollback lifecycle preserving real autosave, upload, account,
revision and failed-write retry guards. Explicit direction for that additional
capability has been requested; this quote change does not claim draft UX parity.

No fixture forums, conversations, pictures, or avatars were added to production.

## Validation

Before changes, the directly related quote, quote editor/parser, close-safety and
draft-failure suites pass 66 checks. The render fixture covers light/dark themes,
320px/640px content widths, 100%/200% text, multiple paragraphs, long attribution,
and an unattributed composer quote. All eight before/after render cases pass
with bundled Lato/Open Sans fonts loaded. Phone and desktop captures in light
and dark at both scales were visually inspected. Captures:
`/private/tmp/composer-quotes-before` and `/private/tmp/composer-quotes-after`.
These are rendered widget fixtures, not a physical-device run.

Focused suites: `test/ui/d_quote_test.dart`, `test/quote_test.dart`,
`test/quote_mockup_parity_test.dart`, `test/composer_quotes_test.dart`,
`test/composer_quote_panel_test.dart`, `test/composer_blockquote_decoration_test.dart`,
`test/composer_component_registry_test.dart`, `test/composer_close_safety_test.dart`,
and `test/composer_draft_failure_test.dart`. Checks cover inset/rounded pixels,
RTL, keyboard actions, exact visible hit bounds, 200% text, existing quote source
links, cached body rendering, atomic removal/undo/redo and stale-source safety.
Targeted analysis covers every changed Dart file. The integration check repeats
these suites under the shared main lock after rebasing to current main.

## Implemented quote delta

With explicit user approval, `DQuote` now owns the shared rounded surface,
directional inset mark, header/body spacing, and decorative quote sign. It is
exported through `discourse_ui.dart` and documented in the Native catalogue and
styleguide. Post rendering and composer quote previews use the same component.
A post without attribution omits the header. The editable plain-Markdown quote
line projection remains unchanged.

Composer removal uses `DButton.iconOnly`, with its rendered bounds supplying the
existing editor hit test. It calls the existing source-validated removal path;
whole-quote protection, cached Markdown rendering, undo/redo and caret placement
remain intact. The component registry owns its separate removal command, so its
read-only preview no longer paints a nonfunctional removal glyph. Post source
links and user-card routing remain app-owned.
