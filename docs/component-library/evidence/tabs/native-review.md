# Tabs independent rendered and native review

Review date: 2026-09-09

Reviewer task: `01a08581-d666-7f81-b039-f9caae6c45c2`

## Review inputs

- Official rendered reference: <https://ui.shadcn.com/docs/components/base/tabs>
- Frozen source and source-to-Flutter measurements: `docs/component-library/tabs-reference.md`
- Production-fixture bundle: `/private/tmp/DiscourseTabsReview-01a08581-v5.app`
  (`org.discourse.native.tabs.review01a08581.v5`)
- Styleguide bundle: `/private/tmp/DiscourseTabsStyleguide-01a08581-v5.app`
  (`org.discourse.native.tabs.styleguide01a08581.v5`)
- Production-fixture embedded kernel SHA256:
  `a90c0ff4da70725921f96733fd1d30b55f402762bd07670bba32f55847b591dd`
- Styleguide embedded kernel SHA256:
  `1013bfd392c4eea5bd0352c017fb0dbd0e1f37657d7abcb36de8afe6762b64be`

Both copied bundles matched their built kernels byte-for-byte and passed a deep,
strict ad-hoc signature check before launch. The temporary production harness
mounts the real `GroupPage`, `ChatChannelInfoView`, `DiagnosticsPanel`, and a
generic Tabs fixture against repository fake/local data; it does not substitute
screenshots or reimplement their tab rows.

## Official browser inspection

The live Base UI page was inspected in its dark theme. Its leading Card example
showed the muted rounded list above a four-panel card, with a selected inset
surface and quieter inactive labels. Selecting Analytics replaced the Overview
panel and moved selected state to Analytics.

Read-only rendered measurements on the official page confirmed:

- the primary/default, disabled, icon, and RTL lists were 32 pixels high;
- their trigger artwork was 25 pixels high with 3 pixels of list inset;
- the selected trigger used foreground text, a subtle translucent surface, and
  a one-pixel border while inactive labels used muted foreground;
- the disabled trigger applied `opacity: 0.5` to the complete trigger;
- the line example had a transparent list and a two-pixel selected underline;
- the vertical example stacked three equal-width, 26-pixel trigger artworks;
- the Arabic RTL example placed the first logical item at the right edge and
  proceeded leftward.

The Card, line, vertical, disabled, icon, and RTL examples all exposed a single
selected tab and one corresponding panel where the example included content.

## Native macOS inspection

The signed styleguide bundle rendered all seven registered Tabs examples. The
dark Card composition closely matched the official surface, inset selected
state, spacing, hierarchy, and content width. Pointer selection changed the
Card from Overview to Analytics and replaced the panel copy. The line example
showed the expected transparent row and selected underline; vertical rendered
as a narrow left rail beside its panel; disabled activation produced no state
change; and icon triggers retained their compact icon/label composition.

The Arabic example reversed logical trigger order and right-aligned the card
content. The controlled/dynamic example rendered its controller actions,
status, three triggers, and retained field. Switching the preview to the light
palette preserved contrast and selected-state hierarchy. At 200% text, then at
200% plus RTL, controls and the tab row reflowed without clipped labels or an
overflow. The native accessibility tree exposed each trigger as one bounded
button and exposed only the active panel's content.

The production harness mounted the actual migrated widgets. `GroupPage`
exposed Members, Activity, Messages, Manage, and Permissions; selecting Activity
revealed the Group activity surface. `ChatChannelInfoView` exposed Settings and
Members (24); selecting Members changed the routed surface, whose deliberately
unauthenticated fetch reported its network failure. `DiagnosticsPanel` exposed
General and Topic scroll; selecting Topic scroll revealed the capture
instructions and Start capture action. The generic harness also confirmed that
its RTL control reversed the logical horizontal trigger order and its 200%
control preserved the three tab groups in the accessibility tree.

## Corrections made during independent review

- Kept one roving tab stop when the controlled value is null, missing, or
  disabled, and preserved manually roved focus across parent rebuilds.
- Made an explicitly cleared `DTabController` authoritative instead of silently
  restoring stale internal selection.
- Moved the 48 by 48 touch minimum onto each actual trigger while retaining the
  32-pixel list surface and 25-pixel compact artwork.
- Deferred duplicate-trigger validation until structural replacement has
  settled, while retaining the assertion for genuine duplicate values.
- Applied disabled opacity to the complete trigger artwork, including selected
  surface, border, and shadow.
- Replaced Collapsible File Tree's temporary Explorer/Outline buttons with a
  controlled `DTabs` composition and retained disclosure/selection state.

## Scope and limitations

- Native inspection is a macOS debug/JIT build with local fixture data. No
  authenticated production account is used; the Chat Members fixture reached
  its expected unauthenticated network-error state after the route switched.
- Touch size, iOS/macOS target behavior, semantics, RTL, 200% text, focus,
  keyboard interaction, lifecycle, and reduced-motion behavior also have widget
  coverage; target-platform widget tests are not device tests.
- No iOS or Linux device was run and no spoken VoiceOver claim is made.
- Browser Geist and native host font rasterization differ, so this review does
  not claim pixel equality. It compares geometry, palette/state mapping,
  direction, interaction, and semantic ownership.
- The production harness's macOS launch image remained painted over its window
  in captured frames even though the live accessibility tree and route actions
  updated underneath it. Production-widget verification there is therefore an
  interaction/semantics claim, not a production-surface raster claim; the
  separately signed styleguide bundle supplied the native raster inspection.
