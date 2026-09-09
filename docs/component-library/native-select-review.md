# Native Select browser and font-loaded render review

Reviewed 2026-09-09 against the actual [official Base UI page](https://ui.shadcn.com/docs/components/base/native-select).
The frozen registry/example URLs and hashes in `native-select.md` remain authoritative.
Primary DOM measurements, captured select markup, asset URLs and hashes are in
`reference/native-select-review/`. Its manifest records the original screenshot
paths and SHA-256 hashes, plus the exact Dart file hashes used for the renders.
Coordinator evidence was copied with a `coordinator-` prefix from
`/private/tmp/native-select-coordinator-evidence`; it is separately attributed.

## Findings fixed

- Type-ahead previously retained its last match after the 700ms prefix expired.
  After typing `b` selected Banana, an external accepted change to Blueberry
  incorrectly made the next session propose Blueberry again. It now proposes
  Broccoli. Blur, Form reset and opening/closing the menu clear the session.
  Repeated letters still cycle within a session, including proposals declined
  by a controlled parent. The regression dispatches explicit timestamped key
  messages through the pinned framework handler because `sendKeyEvent` assigns
  every event `Duration.zero`; deprecated API suppression is restricted to those
  dispatch lines.
- CSS padding is inside the 1px border. The former 10px outer text inset was
  corrected to 11px; trailing text allowance is 33px. Chevron artwork remains
  16px square, 10px from the outer trailing edge and vertically centered.
  This mirrors in RTL. Default width now includes 44px, rather than 42px,
  around the widest option/placeholder text.
- Grouped options contribute one scaled em to intrinsic width. The official
  department example was 188px while the first corrected Flutter render was
  173.794px. Including that native optgroup allowance gives 187.794px.
- Added the exact official status, department, disabled, invalid and Arabic
  compositions to the registered examples. Supplemental food/disabled-group,
  sizes, Form and controlled examples remain available.

## Closed-control measurements

All values are logical/CSS pixels at 100% text scale. Browser fonts are the
observed Geist Latin and Noto Sans Arabic subsets. They were exported via the
page asset inventory, converted from WOFF2 to TTF without altering outlines,
and explicitly loaded into the widget renderer. Their URLs, original/converted
hashes and captured stylesheet hashes are recorded in the manifest.

| Official composition | Chrome width | Flutter with reference font | Flutter with loaded macOS font |
| --- | ---: | ---: | ---: |
| Status | 128.5 | 128.336 | 130.105 |
| Departments | 188 | 187.794 | 192.367 |
| Disabled | 106 | 105.726 | 107.978 |
| Invalid | 111 | 110.962 | 113.528 |
| Arabic RTL | 103.5 | 103.164 | 103.145 |

Both light and dark produce the same widths. The remaining reference-font
width differences are under 0.34px; browser intrinsic text sizing rounds
fractional metrics differently. No fixed per-string width correction is applied.
Standard height is 32px, text box 20px with 6px above/below, and artwork 16px.
The small supplemental example is 28px with proportional radius. Browser radius
is 10px; reference-theme renders use 10px, while app renders retain the app's
configured 4px radius. Reference text weight is 400, size14/leading20, tracking0.

Rendered light/dark/default/disabled/invalid/focus and RTL treatment were checked.
The official page uses a whole-wrapper opacity of0.5 for disabled controls.
Dark input has effective alpha0.045 (input alpha0.15 ×0.3); the invalid border
uses destructive/50 and exterior ring destructive/40. Light invalid ring is/20.
Reference-theme captures use normalized sRGB equivalents of those CSS colors;
8-bit alpha quantization and browser/Skia antialiasing prevent a byte-for-byte
pixel claim. Production renders use the existing app palette and focus color.
The exterior focus ring does not tint the transparent field interior.

The browser was inspected at its normal1403×962 viewport and at390×844, including
Arabic RTL. Widget renders use390×500 with342px available content at100%, then
240px at200%. At200% inherited text scale, standard controls grow to50px (small46)
and retain mirrored padding. This is an accessibility adaptation; the browser
reference's fixed32px height is not copied at the expense of large-text access.

## Production and popup boundary

`tool/native_select_render_test.dart` renders all11 registered examples in both
reference and host themes at100%/200%, plus focused and open-department states.
`tool/native_select_fixture_render_test.dart` captures actual Status, Preferences,
Group management, Bookmark, Invites, Poll, Local Dates, Event, Assignment,
Assigned topics, Chat browse/notifications/move dialog, and simulated Voice media
settings in both app themes at1200×1000. Contact sheets and individual images
are in `/private/tmp/native-select-browser-review` and covered by the manifest.
The closed selectors retain the intended compact geometry within these screens.
These initial fixture pages do not replace checking every nested preference,
permission state or actual device during the pending native review.

Host captures explicitly load the local SFNS font under the inherited
`.AppleSystemUIFont` family; Arabic widget captures explicitly provide SFArabic
as a fallback. Material icon font is loaded from the pinned Flutter SDK.
No production font is replaced. Widget font loading models the native font
choice but is not CoreText/physical-display evidence. Remote emoji on the
`.invalid` fixture can show the existing production fallback.

The open popup is deliberately owned by Flutter MenuAnchor/MenuItemButton;
its wrapping44px rows, scrolling, focus and shadow are not an OS/browser popup
reproduction. Manual render tests enable real shadows (the default test binding
otherwise paints shadow debugging outlines). No OS-popup parity claim is made.

## Verification and handoff

155 impact-focused component, styleguide, launcher, Voice and migrated-owner tests
passed after correction. Both manual font-loaded render tests passed. Root and
full-profile analysis passed. Existing pins and lockfiles are unchanged.
The prior323-test migration run remains recorded in implementation history.

Browser control was explicitly **RELEASED** before final checks/build: original
dark theme restored, temporary viewport reset to1403×962, and only this task's
created tab closed. Native Mac stayed locked: no native CUA or app launch.
Progress remains **in_progress / awaiting_slot** until native visual/device and
VoiceOver review. The refreshed unique signed bundle and compiled-source evidence
are recorded in `native-select-build.md`. No merge or push was performed.
