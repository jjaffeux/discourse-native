# Linear control styling — 18 September 2026

This update replaces the earlier contextual-tint control styling across the
Native kit. It changes the shared components, so existing application buttons,
selectors, menus and items inherit the design without local replacements.

## Reference inspection

Inspected the live, signed-in pages in Chrome, including rendered geometry,
computed styles, matching CSS rules and pseudo-element borders. Opened selector
menus and dismissed them without changing account preferences or integrations.
Disabled and active rules were inspected in CSS where activating a real action
would change account state.

| Reference | Measured details |
| --- | --- |
| [GitHub integration](https://linear.app/jonytudor/settings/integrations/github?source=try), Enable | 32px high, pill radius, 12px horizontal padding, 13px/500 label, solid accent, brighter hover/active fill, no press translation. |
| Same page, Connect organization | 24px high, pill radius, 8px horizontal padding, 12px/500 label, raised neutral fill, 0.5px pseudo-element border. |
| Same page, disabled branch selector | 30px high, 8px radius, 13px/400 label, muted content and 0.5 opacity; retains its neutral fill and outline. |
| [Preferences](https://linear.app/jonytudor/settings/account/preferences), default home view and rich theme selectors | 30px high, 8px radius, 10px leading inset, 13px/400 label, reserved chevron space. Rich content uses the same trigger and option layout. |
| Same page, switch | 30×20px track, 14px white thumb, 3px inset, 10px travel, 150ms transition, neutral off / accent on, brighter hover, 0.5 disabled opacity. |
| Same page, selector menu | 12px popup radius, 4px content inset, 32px rows, 8px highlight radius, 13px/400 text, neutral hover/focus fill and independent selected checkmark. |
| [Connections](https://linear.app/jonytudor/settings/account/connections), connected account item | 16px padding, 12px media/content gap, 10px radius, 13px/500 title, 12px description, 4px title/description gap, fine neutral outline. |
| [Profile](https://linear.app/jonytudor/settings/account/profile), email icon action | 24×24px circular neutral button, fine border and subtle shadow. |
| Same page, Back to app | 28px high, pill radius, 13px/500 label; transparent and subdued at rest, neutral fill and normal foreground on hover/active. |

The dark reference's neutral outline uses white at approximately 0.167 opacity
at rest and 0.278 on interaction. Its control shadow is black at 0.30 opacity,
offset (0, 0.5), blur 1px, spread 1px. The popup has three black 0.125-opacity
shadows: (0, 3)/8px blur, (0, 2)/5px, and (0, 1)/1px. Keyboard focus has a 1px
accent outline with 2px separation. Buttons use 0.6 disabled opacity. Hover and
active fills match; CSS applies them immediately and fades the exit over 150ms.

## Native mapping

- Native presets retain 24/28/32px heights and 12/13/14px small/regular/large
  labels. The large preset preserves the sidebar's established 14px text;
  Linear's 13px action label does not flatten the native size hierarchy.
- `DControlTheme.linear` derives solid actions, raised neutral surfaces and
  hover borders from the current forum palette. It also supplies the fallback
  for ordinary Material themes. Accent hover avoids reducing label contrast
  below 4.5:1 for the tested forum palettes.
- `DButton` and `DButton.iconOnly` use the theme's configured corner radius,
  as do selectors and popup triggers. `hasPopup` never changes the shape.
  Outline/secondary actions share the neutral surface. `transparentBackground`
  gains the observed hover fill; `inline` stays clear for text-row compositions.
  Disabled/loading buttons block activation and presses do not move artwork.
- Enabled ghost, transparent-background and inline actions blend their resting
  foreground 35% toward the theme's normal foreground in light palettes. This
  separates interactive icons and labels from pale forum metadata. Dark resting
  colors and disabled metadata colors remain unchanged. Hover, focus and open
  states still use the normal foreground. The post/chat hover toolbar inherits
  this paint from DButton, retaining explicit semantic action tints.
- `DSelect`, `DCombobox`, `DDropdownMenu`, `DContextMenu`, `DCommand`,
  `DMenubar` and `DNavigationMenu` share neutral row highlights and compact
  typography. Popups use the measured border, radius and layered shadow.
  Pointer highlight, keyboard focus and persistent selection remain separate.
- `DNotificationLevelMenu` uses the chosen `DButton` variant without overlaying
  the old Tracking/Watching accent tint. Labeled and explicitly outlined
  triggers share the neutral surface, including in joined bookmark groups.
- `DSwitch` uses the measured standard geometry and a 24×16px small variant
  with a 10px thumb. `DToggle` and groups inherit neutral surfaces, fine borders
  and the shared focus ring. `DItem` uses the measured spacing and typography,
  with pointer/pressed feedback and a separate selection indicator.
- Input and textarea surfaces inherit the updated neutral palette and border
  colors. Their existing editing, validation and focus behavior stays
  under their own components.

Native adaptations retain the shared 24/28/32px size presets: regular selectors
remain 28px rather than the web reference's 30px. Text scaling grows controls,
48px touch targets remain intact, and layout follows RTL. Application fonts and
forum/category colors and the configured control radius remain authoritative.
Hover exits clear immediately to
avoid simultaneous highlights on adjacent rows; switch motion remains 150ms
and honors reduced motion. Joined controls retain shared seams and suppress
individual shadows.

The Button styleguide includes **Linear settings controls**, a working
composition of all requested examples. `tool/control_consistency_review_main.dart`
provides this composition, the existing family comparison, palette/width/text/
direction controls, and actual production taxonomy triggers with local data.

## Verification

- 492 focused tests passed across 32 files: control states and painting,
  pointer/keyboard selection, disabled/loading behavior, focus restoration,
  joined groups, input editing, contrast, live palettes, styleguide compositions,
  production styling adoption and narrow/large-text/RTL layouts.
- `dart analyze --fatal-infos` reported no issues. Formatting and
  `git diff --check` passed.
- Reviewed all 12 updated control-family goldens (rest, hover and open in
  Light, Dark, Forest and Plum), then reran their comparisons successfully.
  They use bundled JetBrains Mono and Material Icons at 720×480; they do not
  assert pixel equality with Linear's web font or the native system font.
- The final macOS debug build launched as the isolated
  `/tmp/LinearControlsReview96c5Final.app`. Inspected dark/light settings,
  rich selector and action popups, selected/check/disabled states, activation
  feedback, the switch, Plum at 320px/200%/RTL, and the control-family comparison.
  Enable changed to Enabled; the switch changed on to off; keyboard activation
  of Copy link updated the fixture result. The earlier build also covered Forest
  at 320px/200%/RTL and keyboard selection of a rich theme option.
- Automated native clicks did not reliably open selector/action popups;
  keyboard opening and selection worked. The earlier
  [subtle-control review](subtle-control-theme.md) records the same selector
  limitation. Pointer opening/selection and hover behavior pass widget tests;
  no successful native pointer-opening result is claimed here. No mobile
  device or spoken screen-reader run was performed.

The copied bundle and build kernel both had SHA-256
`cef7cdd003db7645e2011fbf4e7869bcf7b78bf8e9290c7cf51676cab51cd5ac`.
Read back its sandbox, JIT, selected-file, network, camera and audio debug
entitlements; strict signature verification passed. The final post-build source
edits only corrected comments, tests and this evidence. Application provisioning
was unchanged. Review apps and the reference tab were closed, and the desktop
lease was released.

## Theme radius correction

The follow-up keeps the forum's configured `borderRadius` authoritative for
buttons and selection controls. Display and Collapse topic both already used
`DButton.iconOnly`; the initial Linear update made ordinary buttons pills but
forced `hasPopup` buttons to an 8px radius, producing the mismatch.

Both constructors now default to `DButtonShape.rounded`, and `hasPopup` only
affects popup semantics. `AppTheme` passes the site radius into `DControlTheme`;
fallback tokens also retain their radius. Removed obsolete pill overrides from
the message inbox and assignment filter. The application styling guard now
tracks shape overrides as well as explicit radii.

Regression coverage checks the actual Display/Collapse buttons at rest and on
hover, all three button sizes, square and rounded themes, live palette changes,
and shared selector/filter geometry. All 470 focused tests pass, including the
toolbar regression and four palette golden tests. The tab geometry assertions
also reflect the 13px labels introduced by the initial styling update.
All 12 replacement goldens were visually reviewed.
`dart analyze --fatal-infos` and formatting passed.

The isolated `/tmp/ThemeControlRadius96c5.app` launched successfully. Native
inspection covered Dark settings and the Light/Forest/Plum control family;
live theme changes changed action, icon, selector and trigger corners together
to 4px, 6px and 12px. The actual topic-toolbar comparison is covered by the
widget regression. The copied and built kernels matched SHA-256
`8f0bc0900706cf10bf985c93de778c8d63ecff2fb93fbb0ab5fa0acc27110f35`.
The permitted debug entitlements were read back and strict signature validation
passed. Later edits only changed comments, tests and evidence.

### Light-theme action contrast follow-up — 2026-09-18

The reported forum used pale metadata ink for enabled toolbar/post actions.
The shared DButton adjustment preserves palette hues and metadata text while
strengthening enabled controls. The post hover adapter no longer supplies a
metadata override; the shared post/chat toolbar only overrides explicit action
tints such as an existing bookmark or like.

Verification:

- 124 focused tests covering Button states/reference/adoption, control-style
  guard, all twelve unchanged control-family golden images, post-action
  accessibility, navigation, Button examples and Linear settings passed.
- The production Display/Collapse regression verifies actual rendered icon
  colors at rest and on hover. The post hover regression likewise inspects the
  icon's inherited color, so a nested IconTheme cannot silently undo the kit.
- After removing the hover toolbar override, all seven post-action tests and
  seven chat hover tests passed, including reply, reaction, bookmark and pending
  bookmark states. The adoption guard and 31 chat message model tests passed.
- `dart analyze --fatal-infos` passed. `flutter build macos --debug --no-pub -t
  tool/control_consistency_review_main.dart` passed.
- Native macOS review inspected the enabled/disabled action comparison in a
  light forum with `#999999` metadata, default light/dark and Forest palettes,
  copy-link activation, and the control-family comparison. The final fixture
  also mounts the production post/chat hover toolbar: its resting, pointer and
  live dark-theme states were inspected. Topic-reader and chat-message
  integration was exercised in widget tests; native review used local fixtures.
- Final isolated bundle: `/tmp/LightControlIconsAdoption96c5.app`, identifier
  `org.discourse.light-control-icons-adoption96c5`. Build and review-copy kernel
  SHA-256: `49f04200a642f7fb2e456d1adfb41f6d30e189d21e13c51d0471bbb979c28cab`.
  Strict ad-hoc signature verification passed and the permitted debug
  entitlements were read back. No production provisioning changes were made.

### Restore large control typography — 2026-09-18

The first Linear update inadvertently changed the large preset from 14px to
13px alongside the intended regular change from 12px to 13px. Production sidebar
identity, navigation and section buttons use large, so they inherited the
reduction. Large is restored to 14px through the shared preset; heights remain
24/28/32px and the app-wide DiscourseTypography roles are unchanged.

Verification: 108 focused tests passed across shared size/typography at 100%
and 200%, Sidebar/layout/styleguide, Button reference, Tabs, adoption and control
consistency. All twelve candidate control-family images were visually reviewed
before replacing the golden baselines; the baseline tests then passed. Static
analysis passed. Built the existing production sidebar fixture and inspected
light at 100%/200% and dark at 100% in native macOS, including the forum identity,
selected navigation, section labels and custom destinations.

Native review bundle: `/tmp/LargeControlType96c5.app`, identifier
`org.discourse.large-control-type96c5`. Build and review-copy kernel SHA-256:
`643de63c71fec2e6a409579670fcb79f50ab1a530dc0560511b9837e27077b81`.
Strict signature verification and debug entitlement readback passed.

### Notification trigger styling correction — 2026-09-18

The joined Tracking control already rendered DButton, but its notification
wrapper overrode the requested outline variant with the previous contextual
accent fill, border and foreground. Removed that implicit override. DButton
now owns rest, hover, focus, open and disabled paint; explicit caller colors
remain supported. Emphasized icon-only controls without an explicit variant
still default to primary. Saved bookmarks retain their independent selected fill.

After integration with main `bd4d0999`, 96 focused tests passed: notification
menus and adapters, selection/session ownership, live palettes, trigger variants,
joined topic-footer actions, control consistency, style adoption and button
groups. All twelve candidate goldens were visually reviewed before adoption.
Integration also included main's themed popup radius; its three changed open
images were reviewed and the golden comparisons passed. Formatting,
`git diff --check`, and `dart analyze --fatal-infos` passed.

The native macOS fixture mounted the actual topic footer and inspected dark and
light Tracking, the saved bookmark, compact icon-only layout, the open menu and
keyboard selection between Watching and Tracking. Automated pointer opening
remained inconsistent as recorded in the original review; pointer interaction
passes widget tests. The integrated build was inspected again in dark and light,
wide and compact layouts, and confirmed the Watching selection update.

Final bundle: `/tmp/NotificationControlStyle96c5Final.app`, identifier
`org.discourse.notification-control-style96c5-final`. Build and copy kernel
SHA-256: `6703272a858bdc7a84e3602906469503a1bd69e972d79765a14f88d54e2be271`.
The bundle launched successfully; strict signature verification and permitted
debug entitlement readback passed. Both isolated review apps were quit and
the desktop lease was released. No mobile device or screen-reader run was made.
