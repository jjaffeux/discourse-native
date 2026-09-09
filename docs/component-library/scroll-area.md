# Scroll Area port — native review pending

Frozen scope: 2026-09-08 Base UI/base-nova Scroll Area. Current official registry,
Markdown examples, and Base UI Thumb/Scrollbar/Viewport/constants sources were
retrieved 2026-09-09. Exact URLs and SHA256 values are in
[reference/scroll-area/sources.json](reference/scroll-area/sources.json).
The fetched Markdown hash can be compared directly with the frozen catalogue;
no catalogue entry or dependency was resnapshotted. Base UI master source is
supporting behavior evidence, not an assertion of the frozen dependency version.

## CSS mapping

At a 16px rem root, `w-2.5` / `h-2.5` is a 10px track. The transparent 1px
leading border and `p-px` leave a 7px thumb, 1px from the trailing viewport edge.
`bg-border` reads live DTokens.border; `rounded-full` uses a capsule radius.
Base UI constants impose a 16px minimum thumb. RawScrollbar supplies the same
proportional geometry, dragging and track paging, with 1px main-axis margins.
The default transparent corner reserves 10px only when both axes overflow.
Viewport focus paints a 1px token outline and 3px token ring at 50% opacity.
The viewport inherits the host radius. No default border or padding is invented.

Tags: 192×288 border-box, 1px border, 16px content padding; heading 14px/14px,
weight 500, 16px following gap; tags 14px/20px with 1px separators and 8px above
and below. RTL uses the same tags and Arabic heading. Horizontal: 384px area,
16px padding and gaps, 300×400 photos with cover fit, host radius, 8px caption
gap, 12px/16px caption and weight 600 artist. Exact reference photographs are
bundled with attribution, without runtime network requests. Host font family,
palette and radius stay live; the reference determines explicit text metrics.

These are source measurements, not a rendered-parity claim. Reference/browser
and native visual inspection remain blocked on the serialized desktop slot.

## API and native adaptations

DScrollArea owns one Flutter scroll position per enabled axis. Omitted
controllers are local and disposed; supplied controllers remain borrowed.
Replacing a controller transfers the mounted viewport's existing position, as
Flutter normally does; its initialScrollOffset only applies on first attachment
to a newly created position. Set/jump the controller to control position. No
separate scroll state, physics, restoration or application persistence owner is
introduced. DScrollViewport is the composable single-axis native viewport.
DScrollBar can decorate a caller's existing ListView/CustomScrollView. It requires
a single attached controller or unambiguous PrimaryScrollController and filters
notifications by axis and viewport depth, so nested content cannot corrupt its
thumb metrics. Default depth zero; combined area's horizontal viewport uses one.
DScrollThumb configures the native painter, avoiding a duplicate drag recognizer.
DScrollCorner composes the default transparent intersection; the area clips and
places a custom corner in the same 10px bounds only for actual two-axis overflow.

RawScrollbar retains native wheel, trackpad, thumb dragging, track clicking,
touch hit tolerance and scrolling semantics. Native touch scrolling and
platform overscroll physics are unchanged. The reference is always visible when
it overflows; thumbVisibility=false opts into native fade/hover behavior, with
150ms fade or zero under reduced motion. Hover does not invent an accent color
or enlarge the visible artwork. The area is a Tab stop only while an enabled axis overflows, with visible keyboard
focus, arrows (physical horizontal direction in RTL), Page Up/Down, Home/End and
Space/Shift+Space (down/up); jumps replace animations under reduced motion.
Ctrl/Alt/Meta combinations and other Shift-modified keys remain available to
ancestor shortcuts. Metrics updates change only root skipTraversal, preserving
descendant control traversal, editing state and existing root focus when overflow
disappears, like the reference tabindex=-1. Child editing and button
focus keep their own keys. Native track paging intentionally uses Flutter's
proven behavior rather than replacing it with browser DOM arithmetic.

Content must be bounded in enabled scrolling axes. Large content and text remain
native layout; scrolling does not manually scale text. Editable children own
Form validation/save/reset; a scroll area itself has no editable value, disabled,
loading or validation state. No new Form or business state abstraction is added.

## Adoption audit

- Shared DSidebarContent now uses DScrollArea and keeps borrowed controller
  support. The shell's specialized sliver sidebar remains virtualized.
- The styleguide's explicit wide-preview scrollbar is DScrollBar. Its existing
  controller, horizontal viewport, clip, 360/768/1024 widths and preview Navigator
  remain. Existing regression tests actually drag the mouse thumb and preserve
  example state through width/theme changes. Scroll Area gets a 500px preview
  height for the 400px reference photos and captions.
- CodeBlock, DiagnosticsPanel, VoiceDiagnosticsView, Assign's people rail,
  Prometheus tables and EventCalendar's month pane change only scrollbar
  decoration. Their controllers, selection, filters, callbacks, permissions,
  async work, table sizing and native viewports are retained. The offline fixture
  mounts those actual production widgets for upcoming visual inspection.

Retained alternatives:

- Users directory has synchronized split-column vertical positions and nested
  horizontal metrics. It retains its existing scrollbar adapter for coordinated
  review; replacing it safely needs dedicated synchronization and native fixture
  coverage, not a blanket text replacement.
- Topic lists, Chat/SuperList timelines, reading lanes and shell sidebar slivers
  retain native virtualization, restoration, anchor and pagination owners.
  DScrollArea must never wrap them in another scrolling viewport.
- ChoiceMenu, CommandMenu and AnchoredPicker have bounded scroll content coupled
  to menu focus/intrinsic sizing and pending catalogue owners. Their native
  viewports are retained for those owners to compose with DScrollBar. No in-flight
  component was imported or implicitly implemented.
- Existing example-specific scroll demonstrations (Skeleton, Separator, Card)
  retain their own independently reviewed source. Their owners can adopt the
  public decorator during serialized reconciliation; they are not duplicate
  production Scroll Area implementations.

## Verification / queue

Focused checks cover touch, keyboard end/home, mouse thumb dragging on both axes,
wheel input, RTL initial edge, borrowed controller replacement/disposal,
resize/content shrink, one position per axis, preview state/width preservation,
large-text RTL examples and migrated production behavior. Root and full-profile
analysis and enforced lockfile resolution are required. See progress row and
scroll-area-native.md for final commands/build provenance.

The component stays in_progress and its styleguide status remains baseline until
actual reference-rendered comparison and native inspection pass. No iOS/Linux
device, VoiceOver or pixel-parity claim is made from widget tests.
