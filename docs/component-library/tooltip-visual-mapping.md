# Tooltip visual and behavioral mapping

The frozen 2026-09-08 [Tooltip page](https://ui.shadcn.com/docs/components/base/tooltip)
defines the scope. Its archived [Markdown](reference/tooltip.md) has SHA256
`d800517217309297330af467d7521ee5fdbc407468bde79fb7945000d1db4b1b`.
The official [base-nova registry](https://ui.shadcn.com/r/styles/base-nova/tooltip.json)
is archived as [tooltip.json](reference/tooltip.json), SHA256
`2f55867faecee2d3616cfd8c6a80b538909a21e62fdfa2788b1ead56093e5395`.
Supporting [Base UI behavior/API documentation](https://base-ui.com/react/components/tooltip)
was inspected, including controlled state, shared handles, hoverable content,
cursor tracking, disabled triggers, placement and timing.

## Reference measurements

The official page was inspected in a hidden in-app browser at 1280×720 CSS px,
device pixel ratio 2, 100% text, first in Light and then Dark. Keyboard traversal
opened the actual “Add to library” example. Settled computed DOM measurements
confirmed the following values. CSS pixels map to Flutter logical pixels at
100% text scale; the configured app font, palette and radius replace the
corresponding web theme variables.

| Property | base-nova render/source | Flutter mapping |
| --- | --- | --- |
| Default side/alignment | Top, center | `DTooltipSide.top`, `DTooltipAlign.center` |
| Body gap from trigger | 4px | `sideOffset: 4` |
| Alignment offset | 0px | `alignOffset: 0` |
| Body text | Geist, 12px, 16px leading, regular | Host sans family, `DiscourseTypography.xs`, 16/12 leading, weight 400, zero letter/word spacing |
| Body padding | 6px vertical, 12px horizontal | Same logical insets |
| Text/keycap gap | 6px | 6px Wrap gap; large content may wrap |
| With keycaps | 6px trailing padding | `shortcut` or `containsKeycaps` changes trailing inset to 6 |
| Width | Intrinsic, at most 320px | `maxWidth: 320`, bounded by the nearest overlay |
| One-line body | 97.492×28px for “Add to library” | 28px height; width follows the configured native font metrics |
| Radius | 8px, `rounded-md` with a 10px theme radius | Host `DTokens.radius × 0.8` |
| Colors, Light | Black surface, white text | `DTokens.foreground` surface / `DTokens.background` text |
| Colors, Dark | Near-white surface (`lab(98.26 0 0)`), dark text | Same inverted token roles, updated while open |
| Border/shadow | None | None |
| Arrow | 10×10px rounded square rotated 45°, 2px radius | Same painted geometry and surface color |
| Arrow attachment | Top body center at h−2; bottom at y=2; side center at w−1 / x=1 | Same offsets; anchor follows trigger and clamps away from corners |
| Enter | 150ms ease, fade 0→1, scale .95→1, 8px slide from trigger side | Same values; side-aware paint transform |
| Transform origin | Trigger-facing edge plus side gap; measured top shortcut origin 61.5px 36px in a 32px-high body | Same side-aware origin; distinct from the arrow center |
| Exit | 150ms ease, fade 1→0, scale 1→.95 | Same values, no exit slide |
| Reduced motion | Native accessibility requirement | Instant transition and removal |
| Provider delay | shadcn default 0ms | 0ms; optional group delay, close delay and 400ms warm period |
| Save artwork | 16px Lucide Save, 2-unit rounded SVG strokes in a 24px viewBox | Same SVG paths in the keyboard example, with [ISC notice](reference/LICENSE.tooltip-lucide.md) |

Arrow geometry was checked against the registry and the rendered DOM (its rotated
bounding box is approximately 14.142px). The body has no extra Material minimum
height or shadow. Pointer-safe travel between trigger and popup is independent
of the visible 4px gap.

## Composition and native behavior

`DTooltip(message, child)` combines root, trigger and content. Optional `content`
supports rich information with a separate concise accessible description.
`DTooltipProvider` coordinates neighboring delays; the public component does
not require a provider to work. The nearest Flutter `OverlayPortal` replaces
web portal ownership and preserves local theme/direction updates.

All four physical sides, two logical sides, start/center/end alignment, side and
alignment offsets, collision padding, flipping/shifting and optional arrow are
exposed. `open`/`defaultOpen`, change reason/completion callbacks, borrowed
controller and trigger IDs cover controlled and imperative composition. Shared
controllers borrow independently composed triggers instead of web payload/render
callbacks. `trackCursorAxis` supports x, y and both. Disabled hints do not disable
their children.

The component observes native focus and pointer/gesture owners. Focus does not
add an extra traversal stop unless the disabled-trigger wrapper explicitly
requests `focusable`. Escape closes the hint without dismissing a parent route;
Enter/Space may dismiss it but still activate the original control. Long press
is an explicit native app extension to Base UI's touch-disabled behavior and
does not invoke the child action. Tap-trigger mode likewise preserves the
child's own callback. A popup is hoverable and scrollable, cannot acquire focus,
and does not duplicate its trigger's accessibility announcement.

The popup may escape a small clipped button/avatar/rail. Ancestor clip rectangles
determine whether the anchor is still visible; only the nearest overlay bounds
constrain the popup. This distinction fixes the zero-width tooltip reproduced
with a clipped avatar inside a nested preview Navigator. Scrolling out of view,
removal, hidden panes, lifecycle changes and window deactivation clear stale
popups and timers. Pressing inside the popup preserves scrolling; outside press
and Escape dismiss it. Native IconButton/PopupMenuButton migrations retain the
original control owner and merge its name/action/state semantics.

## Examples and verification

The first five examples reproduce Usage/Composition, Side, With Keyboard
Shortcut, Disabled Button and RTL before six additional API/edge-case examples.
Arabic trigger labels and tooltip text match the reference composition. The
existing DButton is still marked baseline: its outline/icon-sm visual treatment
belongs to the separate Button task and is not a Tooltip variant.

Automated tests cover exact component geometry/tokens, native focus/activation,
long press, semantics, shared timing, pointer bridge, cursor tracking, controller
and lifecycle races, nested overlays and clipped ancestors, scrollable rich
content, narrow layouts and 200% text. The styleguide matrix exercises all
eleven examples at 240/360/900px, both directions and four representative
palettes. Migration details are in [tooltip-migrations.md](tooltip-migrations.md).

The focused 22-file migration command was:

```sh
flutter test --no-pub \
  test/composer_upload_panel_test.dart test/composer_upload_submission_test.dart \
  test/composer_image_gallery_test.dart test/user_menu_button_accessibility_test.dart \
  test/forum_search_clear_accessibility_test.dart test/voice_room_view_test.dart \
  test/voice_diagnostics_view_test.dart test/gif_picker_test.dart \
  test/reaction_picker_accessibility_test.dart test/alert_tables_test.dart \
  test/prometheus_alert_receiver_plugin_test.dart test/event_card_lifecycle_test.dart \
  test/event_export_boundary_test.dart test/event_composer_test.dart \
  test/event_participants_test.dart test/event_directory_test.dart \
  test/topic_progress_test.dart test/lightbox_test.dart test/inline_video_test.dart \
  test/aggregate_view_test.dart test/plugins/poll/poll_composer_sheet_test.dart \
  test/plugins/local_dates/local_date_composer_sheet_lifecycle_test.dart \
  --test-randomize-ordering-seed=random
```

It passed 333 tests with three accessible-name expectations to correct. The
affected gallery/search/lightbox files subsequently passed all 82 tests. Further
owner regressions passed 226, the shared component/styleguide set passed 185,
and the final controller/example set passed 42. The Tooltip progress row records
their exact commands, random seeds and logs. Root and full-profile analysis and
locked dependency resolution passed; no pin or lockfile changed.

## Native comparison

Native macOS inspection completed in the coordinator's exclusive desktop slot.
The isolated `Tooltip Fidelity Review` app used bundle
`org.discourse.native.styleguide.tooltip.review`, ad-hoc signing and a temporary
local-data entry point under `/private/tmp/discourse-tooltip-review/app`.
No runner/fixture/signing changes are included in this branch. The component,
examples and actual migrated widget source bytes were verified against the
worktree before each observed correction was inspected.

The fixture used 900px and 360px logical preview widths, 100% and 200% text,
LTR/RTL, motion/reduced motion, and Light/Dark/Forest/Plum. Native window resizing
also exercised the app's actual compact account breakpoint. The comparison used
the settled official 100% renders above and the corresponding native examples;
font-dependent width differences follow the host font rather than a fixed web
glyph width. Intrinsic logical measurements are asserted by the widget tests.

- Usage hover and keyboard focus showed the compact inverted surface and arrow.
  Pointer activation and Return each incremented the existing action counter;
  Escape dismissed the hint and retained the surrounding page.
- All four physical sides showed the correct arrow attachment and gap. Start
  alignment showed the specified 8px side gap and 4px alignment offset. Arabic
  physical/logical triggers wrapped at 360px/200%; the left-side popup remained
  within the preview and used the correct reading direction.
- The S action incremented its counter, with the exact Save SVG and a readable
  shared keycap at 200%/RTL. A disabled button's focusable wrapper was reached by
  native Tab traversal and showed its explanation without enabling the action.
- The first shared-delay hint opened after its wait; moving to its neighbor
  showed that hint. The imperative action opened the second trigger and closed
  the active hint. Cursor tracking moved the popup between two points on its
  trigger; disabling another hint preserved its working action.
- A pinned popup retained state through live Light, Dark, Forest and Plum
  changes. At 360px/200% it wrapped, flipped below the trigger and stayed inside
  the preview; RTL and reduced-motion changes also applied while open. Escape
  cleared the pin. Native testing exposed a demo-only hover/click pinning race;
  the button now owns pinning, with a mouse regression and native recheck.
- Rich text and keycaps wrapped at 360px/200% near an edge. Moving the pointer
  into the popup with wheel input kept it open; Escape dismissed it. Long,
  actually overflowing popup-content scrolling is covered by the focused widget
  test rather than a native fixture with artificial excess content.
- Actual InstanceRail, UserMenuButton, TopicProgressButton and VoiceCallWidget
  were mounted with in-memory services. Account sign-in, topic progress and
  Voice mute hints rendered from the retained native controls; the topic action
  incremented the local counter. No account action or real call was started.
  Voice action wiring is verified by its existing widget tests; the fake port
  does not expose a native mute-state indicator.
- The clipped rail trigger displayed its real avatar/title and existing Command
  shortcut outside the narrow rail. The fallback monogram initially clipped at
  200%; restoring its FittedBox preserved both letters. The final 360px/200%
  native recheck showed `TR` fully in Light and Dark. An early boxed-fixture
  width/MediaQuery mismatch was corrected in the temporary harness; both the
  resized real window and corrected fixture showed the compact account icons.
- The actual rail opened the actual ComponentStyleguidePage. Its Tooltip preview
  and usage code were inspected; Escape closed the scoped tooltip, outer
  scrolling removed an offscreen hint, and closing the route preserved the
  fixture's accepted-action counter.

The isolated app was quit through its own app menu. A subsequent global CUA
inventory confirmed `org.discourse.native.styleguide.tooltip.review` was no
longer running; no app-specific query reopened it. The slot was released before
final documentation and commit work.

iOS/Linux devices and VoiceOver speech have not been tested. Automated platform
overrides are not device testing. The configured native font and palette may
change glyph widths and color values from the official Geist/neutral examples;
their semantic roles and relative radius scale remain the same.

CUA's accessibility snapshot transiently classified the styleguide preview's
Hover/Added nodes as checkboxes after outer scrolling, although the visible UI
remained correct and component semantics assertions pass. The cause of that
native/CUA classification was not diagnosed; no forced-semantics instrumentation
or SDK/system accessibility change was made. Native control labels were readable
in the other inspected states. This is recorded for coordinator review rather
than claimed as verified VoiceOver behavior.
