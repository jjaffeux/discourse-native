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

The saved-draft UX newly introduced in `584ad71` is also implemented with
explicit user approval of the required Native kit capability. Resumed drafts
keep a stable snapshot of the effective title, body, category, tags, recipients,
reply target and visibility as opened. Continuous autosave does not advance
that snapshot. Close distinguishes Keep draft, Save changes, Discard changes,
and Delete draft; the existing phone action menu opens the discard choices.

`DTextRevisionPreview` and `DRevisionPreviewTarget` own the source-word diff,
hover/focus intent, removed/restored colors and screen-reader labels. The title
and body editor stay mounted beneath the preview, retaining editing history.
The Native dialog uses its existing custom-presentation API with a clear
barrier so the in-place diff remains readable. Narrow layouts let the preview
grow with wrapped source text. The preview compares Markdown source; it does
not replace the rich editor or its plugin-owned interactions.

Rollback drains older writes and persists the snapshot through the existing
account/session/generation-guarded draft store before applying it to the live
editor. Failed persistence leaves current edits intact and re-stages their
local copy; the user can retry. Uploads and pending operations prevent rollback,
and stale confirmations or account changes cannot close a replacement editor.
Only a successful write starts the 700ms restoration, followed by closure of
that exact composer/revision. Reduced motion skips the animation. The removed
mockup grain dissolve remains absent.

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

## Saved-draft validation

`test/composer_saved_draft_rollback_test.dart` covers stable snapshots after
autosave, older in-flight saves, failed remote and local writes with retry,
external revision changes, account disconnects, active uploads, title/taxonomy,
reply visibility/targets and message recipients, Keep/Delete choices,
hover/keyboard preview cancellation, and successful normal/reduced-motion close.
`test/ui/d_text_revision_preview_test.dart` checks lossless Unicode/large-input
comparison, retained editor identity and accessible change labels.

Rendered fixtures in `/private/tmp/composer-draft-rollback` cover desktop
preview/restoration and phone light/dark at 100%/200% text. These are widget
renders with the bundled Lato font, not physical-device captures. Normal and
enlarged phone images were visually inspected after fixing background blur and
wrapped-diff clipping. The directly related controller, close-safety,
draft-failure, composer parity and quote-panel suites plus targeted analysis run
under the shared main integration lock. A broader run of
`test/composer_drafts_integration_test.dart` has 86 pre-existing failures on
unchanged main `2dbf047beec54ad7a20fe5f7db3c321b31b51b17` and this branch;
all 86 test descriptions and diagnostic causes match. Its other 17 checks pass
on both. Logs: `/private/tmp/composer-rollback-main-draft-baseline.log` and
`/private/tmp/composer-rollback-integration-tests.log`. This does not claim the
broader suite is green.

The close-retry regression exposed by the initial integration run is fixed:
failed saving from the dialog shows its inline error without a duplicate toast
overlapping the retry action. Both composer parity and rollback checks pass
after that fix.
