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

## Acceptance fixtures

The independent reviewer must compare the actual default form, all four sides,
No Close Button and Arabic RTL examples with the official rendered page. It must
also inspect the migrated fast-edit surface. Required states are light, dark and
a real custom palette; 320px/200% text; RTL; reduced motion; keyboard focus,
Escape, outside dismissal and restoration; typed close results; live theme
changes; safe-area and keyboard-inset behavior. Browser and macOS checks must
record exact inspected source. No iOS, Linux or spoken VoiceOver claim is made
without execution.
