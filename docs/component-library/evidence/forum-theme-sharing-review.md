# Custom theme sharing

Reviewed on 2026-09-24 with Flutter 3.47.4.

The compact card uses the existing Native Card, Button, Toggle Group and Alert,
and the existing theme thumbnail and palette strip. No UI kit API changed.
The clipboard format carries both appearance variants; the preview toggle does
not choose which variant is installed or change the forum's appearance mode.

Verification:

- `flutter analyze --no-pub`: no issues.
- 61 focused tests passed across `forum_theme_share_test.dart`,
  `forum_theme_clipboard_test.dart`, `oneboxes/forum_theme_onebox_test.dart`,
  `forum_theme_test.dart`, `forum_theme_editor_test.dart`,
  `oneboxes/onebox_test.dart`, and `styleguide/onebox_examples_test.dart`.
  These exercise editor/library copying, paired effects, real offline post/chat
  cooking, destination forum settings, deduplication, preservation of existing
  libraries, simultaneous imports, persistence failure/retry, preview switching,
  apply/undo, and 240–410px layouts with 1×/2× text in both directions.
- UI kit button adoption passes. The separate control-style guard fails on an
  existing `backgroundColor` override in `composer_block_surface.dart`; the same
  failure reproduces against source from unchanged HEAD `f6b8cef44`.
- Built the offline macOS fixture at `tool/theme_onebox_review_main.dart`.
  Native app inspection timed out; a later desktop lease check found another
  reviewer using the desktop, so native visual verification remains uncompleted.
- Inspected Flutter widget-renderer PNG exports of the production card at 410px,
  macOS target, 1× text, with the local SFNS font. Checked Light, Dark and applied
  states on a light host. The exports came from `OneboxThemeSample`, the same
  production widget used by the styleguide, with in-memory settings.

No authenticated posts or chat messages were sent. Other Discourse clients show
the portable code block until they support this renderer. Physical mobile device
testing and the full application test suite were not run.

The preview toggle now uses sun/moon icons with tooltips and accessible labels.
All 12 onebox and gallery widget tests passed after this adjustment, including
activation by accessible label; `dart analyze` remained clean. Re-rendered and
inspected the light/dark widget previews with SFNS and Material Icons loaded.
