# Sheet reference mapping

Frozen reference date: 2026-09-08.

## Primary sources

- Official Markdown: `https://ui.shadcn.com/docs/components/base/sheet.md`, SHA-256 `d5b0e4ef28a6fa9de830479fab61e6c8d6b8b05698dc6c109b710c4a0112d9d3`.
- Official base-nova registry: `https://ui.shadcn.com/r/styles/base-nova/sheet.json`, captured 2026-09-09 at SHA-256 `72b36d92af7fcbc9bd2d1d4ef0cbc65f4fc8178f7bb2bedaf657460f15011cf4`.
- Behavior owner linked by the frozen page: Base UI Dialog API.

The catalogue hash matches the downloaded Markdown exactly. CSS pixels map to
Flutter logical pixels at 100% scale.

## Reference to Flutter

| Reference source | Flutter mapping |
| --- | --- |
| `fixed inset-0`, `bg-black/10`, `backdrop-blur-xs`, 150ms opacity | A full-route modal barrier using black at 10% alpha, 4px image blur and a fade completing in the first 150ms of the route. |
| Popup `flex flex-col gap-4`, `bg-popover`, `text-sm`, `shadow-lg` | `DSheetContent` is a column with 16px section gaps, live `DTokens.surface`/foreground, 14px body metrics and the two-layer large shadow. |
| Top/bottom `inset-x-0`, auto height, one edge border | Full-width content pinned to the requested physical edge with an interior one-pixel border. The examples cap long top/bottom content to 50% viewport height. |
| Left/right `inset-y-0`, `w-3/4`, `sm:max-w-sm`, one edge border | Full-height panel at 75% viewport width; from 640px it is capped at 384px. |
| 200ms `ease-in-out`, opacity and `translate` by 2.5rem | The popup fades and travels 40 logical pixels from its edge. Reduced motion makes the route duration zero. |
| Header `gap-0.5 p-4`; footer `mt-auto flex-col gap-2 p-4` | Header children have a 2px gap and 16px padding. Footer is pushed to the edge on full-height sides and uses 8px gaps with 16px padding. |
| Title `text-base font-medium`; description `text-sm text-muted-foreground` | Host heading font family with 16px/24px, weight 500; description is 14px/20px and uses the live muted foreground. |
| Ghost `icon-sm` close at physical `top-3 right-3` | A compact 28px `DButton` with 16px X artwork at physical top/right 12px and an invisible native touch expansion. It is not directionally mirrored by ambient RTL. |

## Behavior and API decisions

`DSheet<T>` delegates open/controller/result/focus/dismissal ownership to the
accepted Dialog route machinery. Sheet supplies only edge presentation. The
helper uses the nearest Navigator unless explicitly requested otherwise and
keeps caller theme, text scale, direction and accessibility settings live while
open. Borrowed controllers and focus nodes are never disposed.

`DSheetSide` includes the four documented physical sides and the native
conveniences `start` and `end`. Logical values resolve from the current
`Directionality`; explicit `left` and `right` remain physical, matching the
reference RTL example that selects the opposite side itself. The close control
also remains physically right because the registry uses `right-3`, not an
inline-end class.

Sheet has no swipe, snap point, detent or drag-handle API. Those behaviors are
owned by Drawer. The consulted Silk D-Sheet sources implement a travel-driven
scroll container, detent markers and swipeable backdrop; importing those into
this Dialog-backed component would contradict the frozen shadcn source.

## Application ownership

`showShellSheet` remains the application adapter. Non-draggable presentations
can adopt `showDSheet`; existing drag-enabled Material bottom sheets are retained
until a Drawer migration can preserve their gesture behavior. Persistent Chat
drawer navigation remains a resizable/session-owned workspace rather than a
transient Sheet. Specialized anchored popovers, destructive alerts, media and
full-screen routes keep their corresponding owners.

## Approved inset extension (2026-09-14)

Desktop topic navigation adopts design C from the topic-sheet study. The user
approved extending Native Sheet for this presentation. `DSheetContent.inset`
adds a `DSpacing.md` margin on every side, a complete border, rounded corners
and clipping. `animateSize` animates width changes with the shared 180ms change
duration and respects reduced motion. Both options default to false, preserving
the reference presentation. `showDSheet` exposes the same options.

Widths clamp to the owning Navigator's actual layout bounds, including the
inset margins. The sheet keeps its existing route and descendants while its
width changes. The **Inset and expanding** styleguide example demonstrates
this with retained input.

`DesktopTopicSheetHost` keeps the source page mounted and opens topics in a
right inset sheet below the window toolbar. Following the user's revision,
`ComposerDock` now owns the outer desktop layout. Physical left/right docking
reduces the whole workspace width, including navigation; bottom docking reduces
its height. The sheet adapts to the remaining workspace rather than widening for
the editor. Its ideal width is 1000px: it covers more of the retained background
to reach that width, shrinking only when the workspace minus its insets is
narrower. Closing the sheet leaves the composer available; minimizing or
closing the composer restores workspace space. Narrow windows keep the existing
bottom fallback and restore the preferred side when space permits. Mobile keeps
its page-level composer.

The topic sheet uses the reading background across its header, body and footer,
following the active app or forum palette. The text keeps the existing 825px
reading lane inside the wider sheet.

Desktop forum tabs sit above the sheet Navigator, so tab switching, creation,
closing and the tab switcher remain available while reading or composing. Each selected tab
supplies its own topic and background route; switching restores its reading
position and app-level composer draft. Closing a sheet returns only that tab to
its underlying page.

The workspace is a separate semantics container so nested modal surfaces cannot
hide the left-docked composer from accessibility. On macOS the left composer reserves
the window-control strip. `ReaderContentBounds` reports the actual topic surface
through docking and route animations, keeping chat overlays anchored correctly.

Initial inset verification: sheet and keyboard suites (72 tests), composer/navigation/chat
regressions, and static analysis of the root and full profile. macOS inspection
used `tool/topic_sheet_review_main.dart` with local fixture data: reading,
all three docks with retained text, minimize, light/dark, narrow desktop, and
the new Native styleguide example. One existing topic-inbox popover dismissal
test fails identically at unchanged commit `93c76012`; it was verified separately
and excluded from the remaining regression run. No Linux or spoken VoiceOver
execution is claimed.

The app-level revision is covered by desktop layout tests for all physical docks
in LTR/RTL, independent sheet/composer dismissal, retained editor state, new-topic
composition, narrow-window fallback, and reader bounds. The macOS fixture also
exercises the composer outside the sheet using its real controls and editor,
including light/dark and narrow layouts. The revision passed 118 relevant tests
and static analysis of the root and full profile.

## Approved non-modal extension (2026-09-14)

The user approved a trial of `modal: false` for desktop topic sheets, then
preferred the original blurred background. Desktop topic sheets again use the
default modal presentation: the background is blurred, background scrolling is
blocked, and an outside click dismisses the sheet without activating the
underlying control. The wider 1000px sheet and app-level composer docking remain.

The optional non-modal API remains available in the Native library for surfaces
that need a clear, interactive background. `DSheet` and `showDSheet` forward this
option to Dialog's shared route owner. It removes both the visual backdrop and
the Navigator's pointer barrier. Clicking outside does not dismiss the sheet;
background buttons, inputs and scrolling remain available.

Initial focus still enters the sheet. Close restores the supplied final focus
node or previous focus only if focus still belongs to the sheet; a programmatic
close after using a background input leaves that input focused. Escape from the
sheet and explicit close actions retain their existing behavior. Nested dialogs
remain modal, and their Escape closes only the top dialog. `modal` defaults to
true, preserving existing sheets and dialogs. The **Non-modal** styleguide
example demonstrates background clicks and independent retained inputs.

Verification: 163 focused tests cover Sheet/Dialog/Drawer route behavior,
background interaction, all physical composer docks, forum tabs, shortcuts, and
the styleguide's narrow RTL examples. Root and full-profile static analysis passed. The local
macOS fixture verified light/dark backgrounds, topic selection and list scrolling
behind the sheet, sidebar navigation with a retained composer draft, and the
non-modal example's background action, independent inputs and Escape dismissal.

## Acceptance fixtures

The independent reviewer must compare the actual default form, all four sides,
No Close Button and Arabic RTL examples with the official rendered page. It must
also inspect the migrated fast-edit surface. Required states are light, dark and
a real custom palette; 320px/200% text; RTL; reduced motion; keyboard focus,
Escape, outside dismissal and restoration; typed close results; live theme
changes; safe-area and keyboard-inset behavior. Browser and macOS checks must
record exact inspected source. No iOS, Linux or spoken VoiceOver claim is made
without execution.
