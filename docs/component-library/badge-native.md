# Badge native review

Status: **review_ready for coordinator review**. The exclusive native/browser
slot was granted on 2026-09-09 and explicitly released after the checks below.
The isolated app was quit through its menu; the sole task browser tab was
closed. No shared OS preferences, viewport overrides, provisioning, real account
state, App Store Connect, pushes or merges were changed.

Implementation and native evidence commit: `8631acd9042cb562cd1ad98cec4db9f0a81fc3c0`.

## Reviewed app identity

- Source task `01a083ac-c98c-7fe0-878d-54ee3bcbebb9`, branch `codex/ui-badge`.
- Temporary source `/private/tmp/discourse-badge-review-bebb9`.
- App `/private/tmp/discourse-badge-review-bebb9/build/macos/Build/Products/Debug/Badge Review BEBB9.app`.
- Bundle ID `org.discourse.native.badge.bebb9`, display name `Badge Review BEBB9`,
  URL scheme `badge-review-bebb9`; target `tool/component_review/badge_main.dart`.
- Flutter 3.47.2 / Dart 3.13.2; debug build succeeds. Explicit ad-hoc signing and
  `codesign --verify --deep --strict` pass. Signed entitlement read-back exactly
  equals the temporary signing plist, with `aps-environment` and
  `com.apple.developer.*` absent. Repository runner entitlements are unchanged.
- All `lib/**/*.dart`, `tool/component_review/*.dart`, `test/support/*.dart`
  bytes match the final isolated checkout. Sorted path + NUL + content manifest:
  `9e7f5ecfb0b95d9cd469d0bb0f274775f50f8506a2d6cc063d6c14bc87dfc4a8`.
- Reviewed final kernel: `2b970ca82bac65b866bf7dc06211a9e1014eb170c58476e0df4ae169b4ff861e`.
- Full signed entitlement read-back and identity: `evidence/badge/native/build-identity.json`.

## Observations

The real native styleguide preserves compact variants and icon/spinner geometry
in the host font/palette. Complete/restart works; pointer, Enter and Space advance
the action counter to 3; disabled activation leaves it unchanged. A Badge link
opens its local detail and returns. Forest/Plum switching preserves example
state. At 360px/200%, English and Arabic labels wrap, directional artwork stays
on its logical side, and custom colors remain distinct with reduced motion on.

Native ghost/outline/destructive fixtures confirm idle invalid borders and
keyboard-visible exterior rings. After clearing hover, the focused ghost
interior stays the canvas color; destructive interiors retain their translucent
fill. Native colors use host tokens, so the blue focus ring intentionally differs
from the reference gray. Browser evidence contains a fresh official page capture
and a local fixture using frozen Badge classes, merged conflicting border
classes, and the complete official compiled stylesheet. That fixture exposes
invalid states absent from the public example page: idle computed shadow is
none; settled focus is 3px with 50% normal / 20% light-invalid / 40% dark-invalid
color. It is clearly identified as a source-matched fixture, not the public page.

Actual migrations inspected: exact 1/123 topic counts, Groups Member/Owner,
Chat 99+ numeric count and its narrow large-text lower metadata placement, and
the real staff profile with 123 earned badges. The profile review mode sets
MediaQuery above the root Navigator, so the actual popup receives 200% text;
a test checks both badge contexts at 24px scaled text. The native popup shows
both badges at that scale. Its pre-existing name/action ellipsis remains visible
at 200%; this Badge task does not redesign profile headers or actions.

The initial native narrow Groups inspection exposed a 4px footer overflow.
The member-count Text now has flexible width and wraps beside the trailing
membership badge. The final rebuilt native kernel was re-inspected: full Member
and Owner footers wrap without overflow. The before and corrected screenshots
are preserved. Only Badge-owned migrations and review fixtures changed.

## Verification and limits

- 59 affected permanent tests pass, seed 792030; `/private/tmp/badge-native-final-tests.log`.
  Command: `flutter test --no-pub test/groups_page_test.dart test/badge_migrations_test.dart test/d_badge_ring_test.dart test/d_badge_test.dart test/styleguide/badge_examples_test.dart test/styleguide/spinner_examples_test.dart --test-randomize-ordering-seed=792030 --reporter expanded`.
- Updated renderer export harness passes (`/private/tmp/badge-native-export.log`),
  including an actual root-scaled profile export. Earlier 254 migration checks,
  46 ring followup checks and six before-fix pixel reproductions remain recorded.
- Root and full-profile analysis clean; formatting and `git diff --check` pass.
  Logs `/private/tmp/badge-native-analysis.log` and `/private/tmp/badge-native-full-analysis.log`.
- Browser-rendered and native screenshots are in `evidence/badge/native/`;
  top-level `flutter-*` remain widget-renderer exports. Native accessibility tree
  confirms staff/count text, but spoken VoiceOver was not tested.
- No iOS/Linux device or authenticated production-flow testing. Tailwind
  wide-gamut color clipping, Geist/SF glyph metrics and underline offset remain
  documented platform differences. These limits do not hide an unperformed
  macOS review; the assigned representative native scenarios are complete.
