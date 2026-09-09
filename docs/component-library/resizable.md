# Resizable — implementation and pending native review

Reference scope: frozen 2026-09-08 Base UI / Base Nova page, including its
2025-02-02 v4 API migration. The newly downloaded Markdown exactly matches the
catalogue SHA256. No catalogue changes or implementation dependencies.

## Reference measurements and native mapping

| Reference | Flutter logical geometry / behavior |
| --- | --- |
| `w-px bg-border`; vertical `h-px w-full` | One pixel of layout space; horizontal groups have vertical rules and vice versa. Live `DTokens.border`. |
| `h-6 w-1 rounded-lg bg-border` | Plain 4×24px pill, rotated to 24×4 in a vertical group. No grip icon. `rounded-lg` is **1× token radius**, not an additive offset; radii naturally clamp to pill bounds. |
| `focus-visible:ring-1 ring-ring` | One-pixel ring surrounding the divider, live focus token; no Material splash or animation. Native drag also focuses the handle; pane adapters preserve their focused 3px edge highlight. |
| CSS `after:w-1` + upstream coarse hit policy | Transparent 24px desktop group hit region; minimum 48px on iOS/Android. Overlay targets consume no panel space. At a collapsed edge the target shifts inside the group; the line and pill remain at the precise boundary. Groups smaller than 48px physically bound the target to available space. |
| Example `max-w-sm`, `h-[200px]`, `p-6`, `font-semibold` | 384px maximum outer width, 200px height, 24px inner padding; 14px/20px semibold label with host font and native text scaling. Outer 1px border and `rounded-lg` = 1× radius. |
| Nested demo | Horizontal 50/50; right side vertical 25/75; optional pill on both rules. Vertical and handle examples use 25/75. |
| `defaultSize="50%"` vs numeric v4 pixels | Explicit `DResizableSize.percent(50)` / `.pixels(50)`; never ambiguous bare numbers. Percentages use available panel space, excluding one pixel per divider. |
| CSS em/rem/vh/vw, class/style/ref | Flutter callers resolve font/viewport units through their layout/MediaQuery and pass logical pixels; normal wrappers supply decoration and padding. No CSS parser or inert style/ref properties. |

Radius evidence: official https://ui.shadcn.com/docs/theming uses
`--radius-lg: var(--radius)`; the captured registry requests `rounded-lg`.

## Public API and constraint policy

`DResizablePanelGroup`, `DResizablePanel`, `DResizableHandle`,
`DResizableController`, `DResizableSize`, and `DResizablePanelSize` are exported
from `discourse_ui.dart`. The component has one rendering/interaction owner in
`lib/src/ui/components/d_resizable.dart`, with no app services or networking.

Direct group children alternate panels and handles. Panels require unique stable
IDs; retained IDs preserve size and widget state when reordered. Removed IDs
are discarded; newly inserted IDs use defaults or remaining space. Nested groups
have independent controllers and IDs. Parent width and height must be bounded;
invalid composition produces a specific Flutter error. Resizing the parent
preserves proportions by default; `preservePixelSize` lets relative neighbours
absorb the change before pixel-sized panels are adjusted by unavoidable limits.
Infeasible minima are retained and clipped; infeasible maxima leave unused
space. The app must switch responsive modes before these limits, rather than
silently violating minimum widths.

Default/min/max, collapsed size, collapsible panels, fixed disabled panels,
disabled groups and individual handles are supported. The closest eligible
panels absorb a drag, then more distant panels on that side absorb residual
movement; disabled panels stay fixed. Collapsing snaps at the midpoint between
minimum and collapsed size, provided the opposite side can absorb the **whole
jump**. Pointer distance is not mistaken for capacity. Expansion follows the
same threshold; keyboard/semantic actions snap directly across the gap. Total
space is conserved; impossible discrete jumps keep the last valid layout.

The controller attaches to one laid-out group, exposes immutable pixel layouts
and typed pixel/percentage measurements, and supports resize/setLayout/collapse/
expand. Detached or disposed commands throw; borrowed controllers/focus nodes
are never disposed by widgets. Disabled groups/panels also reject imperative
resizing in this native API (deliberately stronger than upstream imperative
API override semantics). Controlled `layout` makes `onLayoutChange` proposals;
parents accept by supplying typed sizes, or reject by retaining their map.
`onLayoutChanged` signals completed proposals; panel `onResize` reports measured
accepted sizes (with previous pixel/percentage geometry). Initial and container
layout reports are deferred past layout. No Form integration: layout geometry
is not an editable form value.

Arrows follow physical movement, mirrored for horizontal RTL. Shift accelerates
by ten; Home/End use reachable limits, Enter collapses/restores, and double-click
restores defaults unless disabled. Semantic increase/decrease advertise the
actual reachable next size, including discrete snaps, and absent capacity
removes actions. Flutter exposes an adjustable slider role for the separator
because it has no native adjustable-separator semantics role. Focus stays on
keyboard interaction and clears after pointer release/cancel. Parent/content
focus is not recreated by ordinary layout changes. No timer, animation, overlay,
or reduced-motion special case is needed.

`DResizableHandle.standalone` shares exactly the same painting, pointer,
keyboard, focus and semantics owner for app-managed geometry. It explicitly
separates standalone callbacks/value/min/max from the group constructor; mixing
it into a group fails rather than silently ignoring features. A host-owned
edge must use `resolveHitExtent` when positioning its hit area. Standalone
updates normally accumulate between frames; the pane persistence adapter opts
into rendered-geometry anchoring to preserve its established storage policy.
Hosts flush pending persisted state on removal/controller replacement; the
handle never calls app callbacks during widget teardown.

## App audit and migrations

- `ResizablePane` remains the width-listening persistence adapter used by forum
  sidebar, diagnostics and topic inbox. `PanelWidthController` and its async
  restoration generation, dirty flush, preferred width, temporary maximum and
  content rebuild isolation are unchanged. Its duplicate gesture/focus/
  semantics renderer is removed in favor of the standalone handle. Existing
  compact-mode decisions stay in `adaptive_shell.dart`/`main_content.dart`.
- Users Matrix uses `UsersColumnResizeHandle` as its app adapter. Existing
  forum-specific width restoration, account interaction generations, per-column
  min/max, delayed writes and focus keys remain. Multiple pre-frame pointer
  updates accumulate. The custom animated green splitter is replaced by live
  border/focus tokens and the shared renderer. Column persistence stays in
  `UsersPage` and its store; no table/catalogue dependency was introduced.
- Chat thread split uses `ChatThreadPaneDivider`. The existing physical-right
  layout, 320px minimums, responsive single-pane mode, width store and commit
  callbacks remain. The adapter converts logical input into its physical
  callback convention. Both the actual split target and overlap expand to 48px
  on coarse platforms. Desktop retains its existing 9px transparent region.
- Pane desktop target widths (8/12/16px by caller) and matrix 12px edge regions
  are retained to avoid stealing adjacent controls; all expand to at least
  48px for iOS/Android. The painted rule does not widen.

Retained: `composer_panel.dart` and `chat_drawer.dart` corner handles resize
floating two-dimensional surfaces and preserve stored positions; replacing them
with a panel separator would change their domain behavior. Composer-header
movement remains window movement. Calendar dragging/resizing is disabled in
Events. No additional plugin splitters were found. Scrollbars remain Scroll
Area's scope; seeking/volume/timeline controls remain Slider/domain scope.

## Styleguide and native fixture

The styleguide registers seven real-component examples: Horizontal, Vertical,
Handle, Nested, controlled/constrained/dynamic, production Users/Chat handles,
and production pane adapter. Each includes self-contained Dart usage, not
illustrative pseudocode. The extracted four usage programs were analyzed as
Dart before final inclusion. Examples exercise live palettes, native text
scaling, RTL, keyboard, collapse, fixed/disabled panels and dynamic IDs.

`lib/resizable_review_main.dart` launches these examples and actual migrated
production adapters with local controllers, local width values and commit
counters. It also opens the actual styleguide route. It does not construct app
services, read credentials or write real preferences. No real app windows are
resized by preparation or tests.

## Verification state

Focused tests cover constraint propagation, controlled rejection, stable widget
state on reorder/removal, controller/focus ownership, collapsed midpoint snaps
with insufficient opposite capacity and disabled neighbours, vertical gestures,
keyboard/RTL, exact line/pill geometry, live colors, parent resize policy,
48px in-bounds iOS semantic/drag regions including collapsed edges, all examples
at 320px/200% in light/dark/RTL/reduced-motion, and real adapter target widths.
Existing pane/controller, Users Matrix and Chat workspace regression suites
exercise persistence, delayed restoration, responsive layout and callbacks.

Root and full-profile analysis and enforced-lockfile resolution are required;
Flutter remains 3.47.2 and lockfiles/pins unchanged. Voice compatibility code was
not changed. This task uses the user's focused verification override, not the
blanket full-suite gate in CLAUDE.md.

**Awaiting native slot.** No browser/CUA/app launch has occurred. Native reference
render comparison, actual styleguide and production-fixture inspection,
VoiceOver, and iOS/Linux device interaction remain unverified. Tests and source
measurements do not establish pixel parity. The progress row stays in_progress
and examples baseline until the coordinator grants and completes native review.

## Preserved primary sources

- [resizable.md](https://ui.shadcn.com/docs/components/base/resizable.md) — SHA256 `ddd6135362885cae60899cbcc6aa07dd9807623cf090e036c9506706d0a9bb2b`.
- [resizable.json](https://ui.shadcn.com/r/styles/base-nova/resizable.json) — SHA256 `7415e497f342485720b6c878c81604eda0aa8b479a2211e4355c324de89a1672`.
- [resizable-example.tsx](https://ui.shadcn.com/code/apps/v4/registry/bases/base/examples/resizable-example.tsx) — SHA256 `6076eabb0585591cb286be56359172dfde616e5cf3847916b422e1526a2940ab`.
- [resizable-upstream.md](https://raw.githubusercontent.com/bvaughn/react-resizable-panels/main/README.md) — SHA256 `a8b1281257f2b14903d64208a03c9e3668fbfdf554fb2ec9480872f2be421df8`.
- [resizable-adjustLayoutByDelta.ts](https://raw.githubusercontent.com/bvaughn/react-resizable-panels/main/lib/global/utils/adjustLayoutByDelta.ts) — SHA256 `31750b7ab25eced517aad73b1daf8f243846865473cc3026ea1fcb9db67ddffe`.
- [resizable-adjustLayoutForSeparator.ts](https://raw.githubusercontent.com/bvaughn/react-resizable-panels/main/lib/global/utils/adjustLayoutForSeparator.ts) — SHA256 `0c93422369e429cb5b42fb6299e0cc07f475a19362fac89377d322e25989608c`.

Upstream MIT license is preserved alongside the existing shadcn license.
