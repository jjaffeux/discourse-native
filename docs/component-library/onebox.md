# Onebox gallery

The Native styleguide's **Onebox** section searches 16 supported preview
types with `DCombobox`. Each selection mounts its production renderer. The
`DToggle` state buttons wrap onto additional lines and retain a required
selection. Switching providers resets to the first state and disposes the old
preview, including any activated video. The styleguide's theme, viewport,
text-scale, direction and reset controls continue to work.

Samples live in `lib/src/styleguide/examples/onebox_samples.dart`. Core and
GitHub/lazy-video markup goes through `CookedHtml`; hydrated event oneboxes use
the production `EventCard` with local attendance callbacks. No accounts or API
writes are needed. Reddit embeds, public images and media require network access,
and links open their sample destinations. Generic link covers providers that share the
standard envelope without a dedicated native renderer. Twitter/X and GitHub
file samples demonstrate its avatar and numbered-code variations.

The gallery includes all six GitHub PR statuses, comment/commit/discussion
links, issue open/closed dates, profile and category variations, local topic
quotes, inline resolved/loading/unavailable links, YouTube and uploaded-video
markup, Reddit posts and comments, and event attendance/saving/error states.
Reddit uses the Native `DEmbed` through its production cooked-content renderer;
switching states retires the previous web view. The gallery uses a 680px
styleguide viewport with scrolling for longer previews. It aligns to the top
so the picker and state controls stay in place when preview heights change.

The 320px / 200% text checks exposed unbounded metadata rows in Discourse topic
and category oneboxes. Their labels now wrap within the available width; the
gallery exercises this production behavior along with every sample state.

Verification on 2026-09-22, Flutter 3.47.4:

- Root `flutter analyze --no-pub`: no issues.
- 235 focused tests passed with the command below, including the integrated
  Reddit embed, cooked-content and YouTube regressions.
- After the top-alignment adjustment, all 27 gallery/styleguide tests passed,
  root analysis remained clean, and the macOS styleguide rebuilt successfully.
- Gallery checks cover provider search, empty results, keyboard selection,
  PR status rendering, selection reset, wrapping controls, local event RSVP
  and retry, Reddit post/comment switching and web-view retirement, and every
  state in light/640px and dark/320px/200% text, including preview insets.
- Built `lib/styleguide_main.dart` for macOS. An isolated ad-hoc review bundle
  was launched through CUA with only the permitted debug entitlements.
  Inspected the actual Onebox page, search results, keyboard selection,
  draft/merged PR cards, dark/light palettes and 360px viewport wrapping.
- The integrated gallery loaded the live Reddit post and switched to its
  comment preview on macOS. The Mac locked before comment loading and the
  final top-alignment change could be visually rechecked. Widget coverage
  verifies the picker stays in place when content height changes.

These are macOS native and Flutter widget checks. Physical mobile devices and
the full application test suite were not run.

```sh
flutter test --no-pub test/styleguide/onebox_examples_test.dart \
  test/ui/d_embed_test.dart test/oneboxes test/cooked_html_test.dart \
  test/cooked_markup_totality_test.dart test/markup_contract_test.dart \
  test/styleguide/styleguide_page_test.dart test/youtube_player_surface_test.dart \
  test/youtube_video_test.dart --reporter expanded
```
