# Native Boards

Boards is a bundled plugin. Its module owns its schema, API paths, navigation,
snapshots, live subscriptions, controls, and topic memberships. Core sees opaque
extension routes and plugin data. The module declares the generic host ports it
uses, including account-bound requests, topic refresh, and native topic creation.

Every entry point and asynchronous publication requires the site's
`boards_enabled` setting. A missing or false setting disables native navigation,
reads, writes, menus, and topic contributions. Setting changes and account
retirement remove retained private state and subscriptions.

The supported server contract is Discourse's current `plugins/boards`, studied at
`568a006ad8f5d8ae59af64edbd33a151d36fdbde`. The former standalone Kanban plugin and
the older Kanban theme component are not separate supported protocols.

Each account and board has one immutable authoritative snapshot. Views share the
snapshot and keep their own selected column and scroll positions. Live messages
invalidate that snapshot. When its last view leaves, a board keeps its snapshot
without live updates, so returning draws it at once and refreshes it in the
background. The eight most recently left boards are kept; an account change
clears them. Local writes use one lane and always refresh afterward.
There is no optimistic rollback or automatic retry of uncertain creates. Cards
use card IDs because the same topic can occupy several columns.

The directory is read once per account. Returning to it shows the boards
already read; pulling it down or a shell refresh reads it again. Board and
directory reads share one server serializer, so each board read replaces that
board's directory entry and a change made on a board is on its card on return.

Topic moves and additions call Boards' server endpoints. Core topic data is
refreshed through a generic lease-bearing host API after successful changes.
Partial topic projections from board JSON never enter the core topic store.

New topics and standalone-card conversion use an invocation-scoped native
composer completion. Queued or cancelled submissions do not attach a topic.
If attachment fails after confirmed creation, the plugin retains the topic ID
for attachment retry during the current app session. That recovery receipt is
cleared on account retirement and is not persisted across app restart.

On phones and tablets a board opens in the shared mobile page sheet, as a topic
does, and pulling it down returns to the previous page. When that page is the
boards directory, the shell draws it live behind the sheet rather than from a
history snapshot, so it is still there after the app has been in the
background. The sheet drops the
directory back link and the mobile tab bar; the board's categories, tags and
menu follow its title and wrap below a long one. Below 600 points a column fills
the sheet with 10 points of the next one showing, and each swipe settles on one
column. Dots below the column area mark the column in view, and tapping one
scrolls to its column. They stay at the bottom of the board however short the
columns are. The sheet hides the horizontal scrollbar under the columns; a
partly visible column already shows that the board continues. Elsewhere the
header follows the topic reader: a back link above the title and the controls
below it. Columns scroll individually, so the board stops above the home
indicator and a minimized composer instead of continuing under them.
When the header leaves less room than a column needs for its heading, a card
and its footer (200 points, scaled with the text size), as on a landscape phone
or with large text, the page scrolls as a whole instead of squeezing columns.

Column title, icon, sorting, ordering, clear, and delete controls are native.
The column editor preserves existing tag and move rules. Board-level
configuration remains available through the browser link. Inline assignment
editing remains in the ordinary native topic reader. The board renders
assignment metadata only when the server supplies it.

Run the focused checks with explicit paths:

```sh
flutter test test/plugins/boards/boards_controller_test.dart \
  test/plugins/boards/boards_widget_test.dart \
  test/plugins/boards/boards_plugin_test.dart \
  test/plugins/boards/boards_data_test.dart \
  test/plugins/boards/boards_directory_test.dart \
  test/plugins/boards/boards_column_actions_test.dart \
  test/plugins/boards/boards_reader_test.dart \
  test/plugins/boards/boards_sheet_test.dart
```

The native integration entry point is `integration_test/boards_test.dart`.
Use `integration_test/boards_driver.dart` and set `BOARDS_REVIEW_DIR` to collect
native-renderer screenshots. The same fixture also runs as widget tests, where
`NATIVE_UI_EVIDENCE_DIR` enables PNG output.
