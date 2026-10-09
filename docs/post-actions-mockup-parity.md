# Post actions and status cards parity

Source: `discourse-native-mockups`, final snapshot
`c39ad5079e36ccd40a2604c43b513195d5c125a2` on `test-mobile-layout`.
The reviewed source commits are `9559219`, `137a41f`, `47fcc20`, and `c39ad50`.
This record covers the post/action/bookmark group; reading-end scrolling,
quote rendering, user cards, and search have separate owners.

## Implemented contracts

- Post menus group sharing, editing/bookmark/plugin actions, reporting/deletion,
  and staff actions. Bookmark follows edit history and reopens the same quick
  reminder menu for an existing bookmark. First-post deletion/recovery is named
  for the topic; solution and assignment actions exclude the opening post.
- Topic sharing, flagging, and Mark unread use the ellipsis menu. The wrench
  keeps close, pin, archive, visibility, selection, and deletion controls in
  source order. Mark unread uses Discourse's `DELETE /t/{id}/timings.json?last=1`.
  It drains pending read receipts and suppresses new receipts during the reset.
- Staff notices precede the author. Hidden, deleted, locked, bookmarked, assigned,
  and solved posts get a tinted Native card; whispers get the approved dashed
  outline and retain the author's own emphasis. Core status headings show only
  server-provided facts and permission-checked actions. Actor names are not
  invented when the server has not supplied them.
- Existing `PostDecorationPlugin` content stays after cooked content and before
  the footer. Assign and Prometheus preserve that contract. `PostHeaderPlugin`
  is an explicit, separate contribution used by Solved; `PostCardTonePlugin`
  allows Solved and Assign to opt into a surrounding status card. An ordinary
  decoration alone does not create a card.
- Desktop reaction/like controls use the existing 24px Native preset and remain
  available with zero reactions. Persistent menus do not duplicate those
  footer controls. Existing write/permission/account guards remain in place.
- The reminder editor's selected option includes its readable timestamp.
  Custom dates and times use existing Native inputs with the existing account
  timezone, DST, range, cancellation, preference, and persistence behavior.
- Selection remains owned by each post's existing `PostTextSelection` region.
  Post spacing increases and adjacent status-card separators are suppressed;
  day separators retain their independent boundary.

Native changes explicitly approved by the user: optional `DCard.borderColor`
and `DCard.dashedBorder`. Their default behavior is unchanged, and dashed
outlines paint inside the visible bounds. The styleguide includes an example.
Solved uses the real accept/unaccept endpoints and server-authored permission
bits, refreshing the changed and previously accepted posts after success.

## Evidence and boundaries

Rendered production widgets were inspected in light and dark themes, including
notices, whispers, hidden/locked/deleted/bookmarked/solved cards, post and bookmark
menus, a selected reminder timestamp, and status actions at 320px / 200% text.
These are Flutter widget-test renders, not a live account or physical-device run.
Generate them with:

```sh
POST_PARITY_RENDER_DIR=/private/tmp/post-actions-parity-evidence flutter test test/post_actions_parity_test.dart
```

Focused checks cover Native card pixels and bounds, menu ordering and ownership,
post-local selection, moderation, repeated reaction clicks, Solved guardian and
session checks, bookmark persistence/timezones/DST, explicit unread resets, and
plugin decoration placement. In particular:

- `test/post_plugin_decoration_placement_test.dart` checks actual Assign and
  Prometheus decorations below the body, the Solved header above it, and no
  automatic news card around Prometheus content.
- `test/topic_actions_integration_test.dart`: 48 passing tests after updating
  first-post labels and the Native sheet assertions.
- The eight changed reading integration cases pass in isolation after updating
  the two-menu and whisper expectations.

The larger `topic_reading_integration_test.dart` run exposed 28 unrelated failing
cases that also fail on unchanged main (`98126d1cf`). Main has one additional
failure in `C leaves focused forum form controls alone`. The Prometheus test
`topic tables use site emoji and the installed Local Dates renderer` also fails
on unchanged main because its expected `Device` text is absent. These failures
are not represented as passing or repaired by this port.

Final integration validation after rebasing on `61a6cd226`:
450 tests across the 25 directly related component/integration files passed,
plus all eight changed reading integration cases. Scoped `dart analyze` over
all changed Dart files reported no issues. Light/dark rendered evidence was
regenerated and inspected from that combined revision.
