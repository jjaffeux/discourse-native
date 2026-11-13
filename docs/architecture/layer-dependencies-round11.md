# Architecture improvements, round eleven

Baseline: `c5e61e0a9`. Each count is the number of distinct application
libraries reachable through imports and exports, including the entry point.
Widget counts use the existing graph's widget classification. For code
extracted into a standalone library, the baseline is its former owning library.
The counts describe static coupling. Runtime performance was outside this
measurement.

| # | Boundary | App libraries | Widget libraries | Focused behavior tests |
| --- | --- | ---: | ---: | --- |
| 1 | Write credentials depend on their own failure types | 74 → 7 | 0 → 0 | `shell_write_credentials_test.dart`, `rate_limit_wait_test.dart` |
| 2 | Site tracking depends on lookup failures without the API aggregate | 76 → 16 | 0 → 0 | `site_tracker_test.dart`, `http_basic_auth_test.dart` |
| 3 | Sidebar icon loading receives one HTTP GET operation | 87 → 10 | 0 → 0 | `sidebar_icon_loader_test.dart` |
| 4 | Current-user reconciliation uses account identity and plugin preservation on the user model | 46 → 17 | 0 → 0 | `current_user_reconciler_test.dart`, `topic_tracking_directory_test.dart` |
| 5 | Math settings and source scanning use renderer types independently of the math widget | 320 → 169 / 321 → 170 | 134 → 2 / 134 → 2 | `math_source_test.dart`, `math_composer_test.dart`, `d_math_test.dart` |
| 6 | Gamification API, controller, and labels use the shared date type without the UI kit | 321 → 168 / 323 → 170 / 321 → 168 | 134 → 2 each | `gamification_api_test.dart`, `gamification_controller_test.dart`, `gamification_page_test.dart` |
| 7 | YouTube data and lazy markup parsing are separate from their player widgets | 525 → 3 / 746 → 5 | 153 → 0 / 302 → 0 | `youtube_video_test.dart`, `youtube_player_surface_test.dart`, `malformed_url_test.dart` |
| 8 | Mobile presentation resolves route state through explicit inputs and policies | 505 → 45 | 139 → 1 | `mobile_navigation_transitions_test.dart`, `mobile_shell_test.dart` |
| 9 | Forum access and site capabilities use standalone owners with explicit dependencies | 504 → 105 / 504 → 77 | 138 → 1 / 138 → 0 | `shell_forum_access_races_test.dart`, `site_capabilities_test.dart` |
| 10 | Composer recipient lookup uses a three-member editor interface | 338 → 99 | 136 → 0 | `composer_recipient_lookup_test.dart` |

The two failure libraries are re-exported by the existing API aggregate to
preserve imports and type identity. Its consumers that reach both gain two
libraries in their transitive closure, with the same widget counts.
The previous dependency budgets for those consumers account for the two leaves.
The YouTube player and lazy-markup widgets still compose the extracted code.
The extraction itself adds two and four reachable libraries to those widget
entry points, respectively. Their widget counts stay the same.

Run the following commands from the repository root. The budget test guards the
app and widget counts for every new boundary. The graph command can also run
from the baseline checkout, using the widget or shell owner paths for extracted
code.

```sh
flutter test test/architecture_round_eleven_contract_test.dart
dart run tool/architecture_graph.dart \
  lib/src/data/write_credential.dart \
  lib/src/data/site_tracker.dart \
  lib/src/data/sidebar_icon_loader.dart \
  lib/src/data/current_user_reconciler.dart \
  lib/src/plugins/discourse_math/math_settings.dart \
  lib/src/plugins/discourse_math/math_source.dart \
  lib/src/plugins/gamification/gamification_api.dart \
  lib/src/plugins/gamification/gamification_controller.dart \
  lib/src/plugins/gamification/gamification_labels.dart \
  lib/src/models/youtube_video_data.dart \
  lib/src/plugins/discourse_lazy_videos/lazy_youtube_parser.dart \
  lib/src/shell/mobile_presentation.dart \
  lib/src/shell/forum_access_state.dart \
  lib/src/shell/site_capabilities.dart \
  lib/src/shell/composer/recipient_lookup.dart
```
