# Message Scroller reference and acceptance mapping

Source pin: frozen Base UI/base-nova Markdown SHA-256
`fc0e1a7bdc05d81c833e001292419e85e1eb7c16be3942a7468ff2d6c1d2b165`,
the base-nova registry wrapper captured on 2026-09-09, and the published
`@shadcn/react@0.3.1` behavior implementation. Exact URLs, hashes and preserved
source are in `reference/message-scroller/sources.json`.

## Reference-to-Flutter mapping

| Reference | Flutter | Mapping |
| --- | --- | --- |
| `Provider` | `DMessageScrollerProvider` | Owns typed configuration and an owned-or-borrowed `DMessageScrollerController`; default end, last anchor, edge threshold 8, scroll margin 0, and previous-row peek 64 logical pixels. |
| `Root` | `DMessageScroller` | A full-size clipped `Stack` that layers the viewport and logical start/end controls. |
| `Viewport` | `DMessageScrollerViewport` | Labelled focusable region, native wheel/touch/keyboard scrolling, variable-height `SuperListView`, restoration ID, optional borrowed scroll/list/focus controllers, and accepted `DScrollBar` artwork. |
| `Content` | `DMessageScrollerContent` | Addition-only live transcript semantics, busy deferral, directional padding, minimum viewport fill through the list, and the base-nova 24px row gap. |
| `Item` | `DMessageScrollerItem` | Stable string id, explicit turn-anchor bit, optional completed-row announcement, arbitrary composed child, and a real keyed row boundary. |
| `Button` | `DMessageScrollerButton` | Centered 16px from the logical target edge; 32px secondary icon button, real semantics, inactive focus/hit-test removal, 200ms show and 400ms hide with 0.95 scale/edge translation. Reduced motion is immediate. |
| hooks | controller state | `scrollToStart`, `scrollToEnd`, and stable-id `scrollToMessage`; start/center/end/nearest, instant/smooth and per-command margin; `canScrollStart`, `canScrollEnd`, current anchor and visible ids on a `ChangeNotifier` without rebuilding transcript rows. |

The registry's full frame is `position: relative`, flex-column, `size-full`,
`min-h-0`, and clipped. The viewport is full-size/min-size, vertical native
overflow with contained overscroll, thin stable scrollbar and pending-scroll
visibility. Content is `min-h-full`, column, gap 6 (24px). Items are min-width
zero, non-shrinking, with offscreen rendering optimization. Flutter's lazy
variable-height list supplies the equivalent retained-row performance behavior
and makes the documented virtualization composition a first-class builder API.

## Behavior ownership

The generic component owns only viewport behavior. Messages, AI/transport
status, persistence, history requests, branching, unread counts and domain
models remain with callers. A production adapter may disable initial-position
application when it already has a richer server-provided target; this is the
narrow adaptation used by Discourse Chat. Likewise, the existing reversed chat
virtualizer retains its proven physical-index identity and resize preservation,
while the generic default uses stable-id child identity and first-visible-row
restoration.

New stable anchor rows settle near the start with 64px of previous context and
a spacer when the remaining transcript is too short. End-following is opt-in,
continues across streamed height changes only while the reader remains at the
live edge, and is released by wheel, touch/pointer interaction, keyboard
scrolling or another explicit target. Prepending captures the first visible
stable row and its viewport offset, then corrects after real variable heights
are laid out. A target can queue while the transcript is empty; after non-empty
mount, unknown ids fail immediately. Smooth commands are canceled by later
reader intent, and reduced-motion commands jump.

## Documented composition accounting

- Anchoring turns, group-chat markers and previous-context peek use ordinary
  `DMessageScrollerItem` rows; the scroller never infers a role.
- Streaming and interruptions exercise live-edge following, busy semantics and
  variable-height content without announcing token mutations.
- Saved threads use `end` or `lastAnchor`; pending initial positioning keeps the
  laid-out transcript visually hidden until its first deliberate landing.
- Earlier-history loading uses stable-id prepend restoration. Loading callbacks
  stay outside the generic component.
- Entry animation wraps the item child and is reduced-motion aware without
  changing its stable row boundary.
- Command, outline and scroll-state examples use the controller. Logical ids
  and state are independent of visual message widgets.
- The builder constructor is the documented virtualization path: it keeps real
  stable ids, estimated/measured variable extents, configurable cache extent,
  and offscreen row creation.
- `styled: false` retains all behavior without the accepted scrollbar artwork;
  caller markup remains responsible for visual treatment.
- Accessibility maps the viewport to a separately labelled region and content
  to a live log; inactive edge controls are not focus stops. Descendant focus,
  text selection and actions remain independent.

The frozen demo also composes Bubble, Button, Card, Dropdown Menu, Empty, Hover
Card, Input Group, Marker, Message, Select, Slider, Tabs, Toggle Group and
Tooltip. The styleguide source accounts for each through runnable behavioral
examples or explicit final-owner composition; no networking or fake substitute
primitive is introduced into Message Scroller.

## Production adoption

`ChatMessageStream` is the one shared channel/thread transcript owner. It now
uses `DMessageScrollerProvider`, `DMessageScroller`, and the virtualized builder
viewport with stable ids for message, day, time-gap, deleted, unread and loading
rows. Existing reversed-offset paging, server target/last-read landing, read
dwell, floating days, nested code-scroll filtering, selection, highlight and
unseen-count behavior remain in the Chat adapter. Both channel and thread
surfaces therefore adopt the generic component without duplicating scroller
business logic.

Other scroll surfaces are intentionally retained: topic posts are not chat
transcripts; menus/pickers own focus-sized overlay viewports; search and inbox
results are ordinary result lists; composer text areas and attachment rails are
editable or horizontal controls rather than streaming transcripts.

## Independent review corrections

The independent review exercised state transitions that were not covered by
the implementation handoff and corrected four behavioral defects:

- End and last-anchor startup now enter the pending state before the first
  viewport paint. The maintained transcript stays hidden until the deliberate
  first landing, so reload cannot flash the logical start for one frame.
- Turn anchoring counts anchors only in the newly appended batch. A later
  single anchored turn therefore keeps the documented previous-row context
  instead of being mistaken for a multi-turn batch and forced to the end.
- A custom edge-button child is button content rather than a replacement for
  the control. It retains the standard callback, scroll command, focus target,
  disabled behavior and semantics.
- Smooth edge and message commands retain programmatic ownership until their
  animation settles. Reader-position resize correction can no longer cancel a
  command after its first animation frame; later genuine reader input still
  cancels it.

The review also locks owned-versus-borrowed controller, list-controller,
focus-node and scroll-controller disposal behavior in a permanent regression.
The offline review entry point mounts all seven catalogue examples plus actual
production channel and thread `ChatMessageStream` adapters through the bundled
chat plugin's real session and store, with an in-memory offline transport.
