# Movable composer blocks

Implemented September 21, 2026 in the existing topic/post composer.

Chat composers disable block reordering, including the leading gutter handles
and Alt+Shift+Up/Down shortcuts, in both channels and threads.

## Using it

On desktop, hover a paragraph, heading or component to reveal its leading
gutter handle. The handle shows an open-hand cursor on hover and a closed hand from
press through dragging. The closed hand follows the pointer across the editor,
including when scrolling moves the original handle out of view.
Drag the handle to an insertion line, or click it for **Move up**, **Move down**
and **Move to…**. Alt+Shift+Up/Down moves the block at the caret.
The source block retains a subtle themed background during the drag, with its
handle anchored in place. The handle stays transparent in hover, pressed and drag
states so it shares the block's background without an additional button fill.
The insertion line is centered between the preceding
block's bottom and following block's top, spans the text area beside the gutter,
and does not shift the text. At the beginning or end it marks the outer block edge.
The original position also shows an insertion line; dropping there leaves the
source and undo history unchanged.
Runs of empty lines expose individual insertion boundaries, including before the
first content block and after the last. A block can move within these lines
without changing the order of the content blocks. The move preserves the other
empty lines and adds only the separators needed to keep Markdown blocks distinct.
The handle's action label stays in its hover tooltip rather than following the
pointer in a card.

Dragging an existing image or dropping a file into the editor uses the same
insertion line and block boundaries. The line follows the destination without
shifting content and clears when the drag leaves or completes. File drops into
expanded details use the inner editor's boundaries; drops onto galleries retain
their gallery target instead of showing a document insertion line.

The toolbar's **Arrange blocks** button opens an outline on desktop or mobile.
On touch devices this dismisses the keyboard, while keeping the original editor
mounted. Select a row and use the arrows, drag its handle, or choose **Move to…**
and tap a destination. **Done** returns to the editor with its mapped selection.
Undo and Redo are available in the arrangement controls. Escape cancels an active
drag, then destination selection, then arrangement.

Text remains one continuous editor. A wrapped visual line is not a block. Normal
text selection, scrolling, typing, existing slash commands and insertion controls
keep their existing behavior. Topic titles remain outside the movable body.

## Supported boundaries

- Paragraphs (including soft line breaks), ATX/setext headings and dividers.
- Complete fenced or indented code blocks.
- Complete lists, including nested items and continuation paragraphs.
- Individual standalone to-do rows, including checked and empty items.
- Blockquotes and registered quote, table, poll, details, image, gallery, upload
  and diagram components. Existing component parsers supply their complete ranges.
- Unsupported or ambiguous containers remain source blocks without a move handle.
  Raw HTML conservatively protects the remainder of the body. BBCode spanning
  paragraphs is protected against separating its opening and closing tags.

A whole Markdown list is the movement unit; standalone to-dos move row by row.
Individual nested list-item/subtree moves, multi-block selection,
heading-with-section moves, duplication, type conversion, and changing
Enter/Shift+Enter semantics are separate future work.

## Source and history

`ComposerBlockIndex` indexes exact UTF-16 source ranges. It moves raw payloads,
preserves outer whitespace and unchanged boundaries, and supplies safe paragraph
separators at new boundaries. CRLF, plugin attributes, upload identifiers and
trailing spaces inside payloads survive. It reparses each proposed move and
rejects joins that would change the number or kind of blocks, including merging
lists or putting content inside an unfinished fence. It never serializes the
whole document through a Markdown renderer.

`ComposerBlockController` owns local block selection, arrangement state and a
monotonically increasing source revision. A drag captures its block identity and
revision. Typing, Undo, an upload completing, or another source edit invalidates
the gesture. Composition, loading and submission prevent structural edits.
Only a completed valid move writes source; previews do not dirty or autosave drafts.
Upload completion continues to find its marker after movement. Block identities
are session metadata; existing stored drafts/posts require no migration.

`ComposerEditHistory` owns undo for the production editor, including typing and
structural transactions. Each move establishes an explicit boundary, so two rapid
moves undo separately and do not absorb adjacent typing. `ComposerHistoryScope`
routes Flutter's overridable undo/redo actions and iOS UndoManager to that same
history. Keyboard shortcuts also use it. Embedded editors retain their own scope.
History survives docking, minimization and arrangement, and resets when the
controller replaces a sent/restored document.

`ComposerBlockSurface` adds a desktop gutter and a touch outline around the
continuously mounted field. It measures editor/component bounds after layout,
scrolls near viewport edges during a drag, cancels on app interruption, validates
again at drop, and exposes button/menu alternatives to precise dragging. Outline
rows announce type, position and selection; the current position is a live region.

## Native components

The user approved adding reusable drag components to the Native kit:

- `DDragHandle<T>` composes Native button focus, tooltip, disabled state and touch
  targets with a handle-only drag and open/closed hand cursors. Its tap action
  provides a non-drag alternative.
- `DDragHighlight` paints a passive, theme-derived tint over the original block
  bounds without intercepting editing, scrolling, or drop targets.
- `DDragRegion<T>` receives typed payloads and global positions; the caller validates
  its document revision and commits the drop.
- `DDropIndicator` paints the shared themed insertion boundary.

They are exported from `discourse_ui.dart` and demonstrated in the application
component catalogue's **Drag** entry. The frozen upstream catalogue is unchanged.
Menus, outline rows, buttons and scrolling use existing Native components.

## Validation

Source/history tests cover exact payloads, CRLF, Unicode, duplicate paragraphs,
list and quote boundaries, plugin blocks, unsafe joins, caret mapping, rapid
moves, typing around moves, IME guards, and stale gestures after an edit/Undo.

Widget tests cover real desktop dragging, mobile arrangement at 320px with larger
text, preserving EditableTextState, handle menus, tap-to-place, keyboard/native
undo routes, Escape, source edits during dragging, edge scrolling on both layouts,
RTL and accessible touch targets. An upload integration test moves an in-flight
upload before its successful completion. Existing composer history, docking,
embedded-editor, draft and selection tests are also exercised.

Light/dark desktop and mobile editor layouts were rendered for visual inspection.
Physical-device IME, VoiceOver/TalkBack, and OS three-finger undo gestures still
need device smoke testing; headless widget tests cannot certify those integrations.

The September 22 drag polish adds regression coverage for the leading gutter in LTR
and RTL, exact insertion-line centering, the source highlight's bounds and
cancellation, and cursor transitions over text even after the source unmounts.
Root `dart analyze` and 151 focused tests passed, covering drag controls, buttons,
composer movement, selection, uploads and viewport overlays. The local macOS
composer fixture was inspected in light/dark themes and at narrow RTL width;
an embedded table was moved using the gutter handles. The Native Drag styleguide
was also inspected in light/dark themes and completed a drop. The right-hand
handle and its reserved gutter were subsequently removed at the user's request.

A follow-up cursor regression checks every pointer move before and after the
next frame, including the cursor updates sent to the platform. A stationary,
non-blocking window overlay retains the fist throughout a drag and is removed
on drop or cancellation, even when scrolling has unmounted the source handle.

## Notion reference

The original HTML concept used Notion's block model as an interaction reference.
Notion documents [blocks and their handles](https://www.notion.com/help/what-is-a-block),
[a toolbar above the mobile keyboard](https://www.notion.com/help/workspaces-on-mobile),
and [mobile limitations](https://www.notion.com/help/notion-for-mobile), including
lack of hover and desktop-style multi-block selection. Our explicit Arrange view
is an adaptation for this composer, not a claim about Notion's exact mobile drag
gesture. Sources were checked during the original exploration on September 21,
2026.
