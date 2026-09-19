# Forum themes — 2026-09-19

The forum Settings dialog combines the gallery study's section sidebar with the
studio study's side-by-side theme controls and preview. General displays the
forum identity; Appearance owns color mode, forum default, presets, and custom
palettes. Narrow layouts use the existing Select for section navigation and
stack the preview beneath the editor. Copy is limited to control labels,
sample topic content, and validation/error messages.

## Implementation

- Uses existing Native Dialog, Sidebar, Select, Toggle, Tabs, Input, Textarea,
  Card, Button and Alert components. No UI kit APIs or styles were extended.
- The preview mounts the production `TopicListRow`, including title, excerpt,
  author, unread marker, and bookmark/pin treatments, with two fictional topics.
  Preview actions are excluded from focus and ignore pointer input.
- All 13 reference palettes are included. Opposite brightness swaps text and
  background, matching the supplied HTML reference. Clover Dark's missing
  status colors use Neutral's values, as in the studies.
- Forum geometry is retained when resolving personal colors. Font and layout
  settings remain owned by the forum/application.
- Theme overrides and custom libraries are saved per canonical forum URL.
  Restoring the forum default retains the custom library and resumes the
  current server palette rather than a copied snapshot. Existing mode migration
  is unchanged.
- Presets apply immediately. Custom edits preview locally until Save theme.
  Save errors retain the previously applied palette. Custom themes can be
  updated, deleted, copied as versioned JSON, and imported with validation.
- Draft text, including temporarily invalid colors, survives switching between
  the wide and narrow layouts. The editor uses hex inputs with passive swatches;
  there is no new color-picker component.

## Verification

- Focused static analysis of all changed Dart files: no issues.
- Full analysis: one pre-existing informational lint in
  `test/content_route_test.dart` (`prefer_const_literals_to_create_immutables`),
  outside this change.
- 62 focused tests passed across forum settings, palette persistence, custom
  editor, site-theme integration, AppTheme and the control-style adoption guard.
  Import and draft-resize coverage are included.
- Model coverage includes all preset identities, JSON validation/round trips,
  brightness/geometry resolution, per-forum restart persistence, default
  restoration, damaged entries, write failure, and hydration/save ordering.
- Widget checks include real preview components, custom edits and save, invalid
  hex values, malformed/valid imports, and preserving partial input during a
  1400px → 390px resize. Existing 360×640, 200% text, RTL checks pass in both
  brightnesses. These are widget checks, not mobile-device tests.
- `flutter build macos --debug --no-pub --target tool/forum_settings_review_main.dart`
  passed. Native review used that existing in-memory fixture in an isolated
  `org.discourse.native.review.forumthemes` bundle. Ad-hoc debug signing retained
  sandbox/JIT/network and omitted restricted push identity; strict verification
  and actual launch succeeded.
- Native macOS inspection: sidebar sections; preset selection and app recoloring;
  dark/light mode; live accent editing; custom save; forum-default restoration;
  scrolling; Escape dismissal; and the final selection checkmarks and editor
  swatches. Both the original application renderer and shared controls appear
  in the preview. The isolated app was closed and desktop leases released.
- Installed Flutter 3.47.4 / Dart 3.13.3 were used. The repository SDK pin and
  lockfiles are unchanged. No external forum account changes were made.
