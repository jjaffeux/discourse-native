# Avatar adoption follow-up

Verified on 2026-09-10. Implementation: `2e9b862c`. Integration candidate:
`39f5a684`, based on main `75b95e4d`.
Merged into main from the main checkout as `eba2dfa2`.

Generic onebox avatars, inline HTML avatars, rail site icons, and the message
scroller and custom toast examples now compose `DAvatar` through the public
UI library. HTML avatars retain their declared dimensions, authenticated image
loading, and accessible labels. Loading and failed images use `DAvatarFallback`.
The source audit found no remaining `CircleAvatar` constructions in `lib/`.

## Automated verification

- `dart analyze --fatal-infos`: no issues.
- Formatting and `git diff --check`: passed.
- The focused command below passed all **145 tests**:

```sh
flutter test --no-pub \
  test/oneboxes/onebox_test.dart \
  test/cooked_html_test.dart \
  test/site_image_test.dart \
  test/cooked_markup_totality_test.dart \
  test/styleguide/toast_examples_test.dart \
  test/styleguide/message_scroller_examples_test.dart \
  test/site_theme_app_test.dart \
  test/instance_reordering_test.dart
```

## Native verification

Built a temporary macOS fixture mounting the production `InstanceRail`,
`CookedHtml`, and `OneboxCard`, plus the actual avatar, message scroller, and
toast examples. Images and forum data came from local fixtures. The isolated
app used `org.discourse.davatar.review.c41d`; its ad-hoc signature passed strict
verification with the existing permitted debug entitlements.

Inspected ready and failed HTML avatars, an embedded avatar, a generic onebox
avatar, and rail artwork alongside the accepted avatar example. Checked the
light and forest palettes at 580px/LTR/100% and 300px/RTL/200%. The failed-image
fallback retained its bounds and displayed the user icon without clipped alt
text. Native accessibility exposed the supplied image labels. Also inspected
message initials at 200% and opened and dismissed a custom toast containing the
Native avatar. No avatar clipping or layout overflow was observed.

The native checks ran on macOS; no iOS or Linux device pass was performed.
