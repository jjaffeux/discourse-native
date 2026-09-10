# Composer docking — design A

The amended design has exactly three positions: **left, bottom, and right**.
Composers stay inside the main application window. Separate windows are out of
scope.

## Behavior

- The compact Native overflow popup shows **Dock side** followed by left,
  bottom, and right icons. Each has a tooltip, accessible name, and selected
  state. Save/close, discard, minimize, and restore remain available.
- Desktop defaults to the right at 420 logical pixels. Side docking keeps a
  360-pixel composer and 320-pixel reader minimum. If they cannot fit, the
  composer temporarily moves to the bottom and restores the preferred side
  and width when space returns.
- Docking occupies the content area and leaves the rail and sidebar available.
  A Native resizable divider replaces free dragging and corner handles. Chat
  uses the remaining reader rectangle; diagnostics resizes the shell.
- Mobile always docks at the bottom and hides placement choices. The editor
  body and cramped reader chrome scroll inside bounded areas, leaving editor
  actions above the keyboard. Minimize shows a compact bottom strip; restore
  retains the draft, selection, undo history, and previous placement and size.
- The `discourse_native.composer_layout` preference stores the desktop dock,
  side width, reply height (initially 280), and topic height (initially 380).
  Obsolete floating coordinates and unknown placement values are ignored.

## Implementation

`ComposerPresentationController` manages presentation preferences separately
from `ComposerController` draft content. `ComposerPresentationHost` retains
keyed editor surfaces through placement changes, minimization, and tab switches.
Sessions retain the application's existing forum-tab ownership and lifecycle.
The reader's scroll ancestry remains stable when the composer opens or closes.

Application controls use the Native UI kit through
`package:discourse_native/discourse_ui.dart`: `DPopover`, `DToggleGroup`,
`DButton`, `DSeparator`, `DTooltip`, `DResizablePanelGroup`, and `DScrollArea`.
No new generic Native component is needed for the amended design.

Submission and recheck actions explicitly target their composer. Closing or
explicitly discarding a composer respects pending saves, uploads, submissions,
and confirmation state. Failed preservation leaves the draft available.

The root and full compatibility profile use their original native runners and
upstream file-selector/desktop-drop dependencies. There is no new engine,
native window channel, or window compatibility patch in this feature.

## Verification

The focused regression suite covers docking, resizing, preference restoration,
minimization, retained editor state/selection/undo, RTL, narrow layouts, mobile
keyboard layout, tab navigation, uploads, safe close/discard, and draft recovery.
An explicit menu regression ensures the separate-window action is absent.

- 167 composer, navigation, upload, and preference tests passed.
- All 139 chat integration tests passed, including placement beside each dock
  and retaining edits through collapse/close. Collapsed chat keeps its usual
  width, capped by the available reader space.
- Chat service and diagnostics tests passed. The parser corpus has one existing
  failure: `DQuestionnaireAnswer` and `DQuestionnaireSavedState` are missing from
  its inventory. The same failure was reproduced in a clean checkout of
  `b9ff6ebc`; the new composer preference is accounted for.
- Root and full-profile static analysis passed. Both macOS debug application
  builds passed, as did the root macOS review-fixture build.

Integration with main `62906e34` passed 449 focused composer, chat, diagnostics,
navigation, sidebar, upload, and preference tests, plus root and full-profile
static analysis and macOS debug builds. The newer sidebar and scrolling changes
are preserved.
After main advanced to `99499c73`, the combined code passed another 260 focused
docking, chat, sidebar, and navigation tests, plus both profiles' analysis and
macOS debug builds.

The local-only `tool/composer_docking_review_main.dart` fixture mounts the real
production composer with isolated preferences, in-memory APIs and test
credentials. Earlier native checks verified desktop left/bottom/right docking
and text retention, plus the iPhone 17 / iOS 26.5 simulator with its software
keyboard visible, minimized/expanded editor, and enabled submit button. No real
account data or posts were changed. The rebuilt macOS fixture verified the
amended three-option menu, right/left/bottom placement, text retention, bottom
strip minimization/restoration, and save-and-close. The isolated review app was
closed afterward.

Linux builds and live Linux/physical mobile checks were not run on this macOS
host. Widget tests with platform overrides are not device verification. The
focused suite is used instead of the entire repository test suite.
