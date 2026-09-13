# Selected profile implementation

Direction 03 is implemented in `lib/src/shell/user_summary.dart`. It omits
“Your summary”, “A little perspective on your participation.”,
“Your activity in this community.”, “All time, in one place.” and
“Ideas you started”, as requested.

The follow-up copy edit also removes “The conversations you keep returning to”,
“People who appreciate your contributions”, “People whose ideas you appreciate”,
“Where you start and join conversations” and “Resources you shared” from the
production page and the profile HTML preview.

The identity card stays alongside independently scrolling content in wide
layouts. Narrow layouts and enlarged text place it above the content. Highlights
contains contribution totals, topics, replies and badges; Connections contains
the three people lists; Reading contains reading totals, categories and links.
Tab selection survives refresh, resizing and returning from a topic.

The page composes DCard, DText, DTabs, DItem, DAvatar, DTable, DBadge, DTooltip,
DSeparator, DScrollArea, DEmpty, DSkeleton, DAlert and DButton from the public
Native library. Category identity, avatar loading, topic titles, profile cards
and routing remain application adapters. No new shared component was needed.
All appearance comes from the current kit and forum theme.

Account lifecycle and fetching remain intact. Existing topic/post targets,
source-topic links, profile actions, category search filters and pull-to-refresh
are retained. Stats permission, badge enablement, optional bookmarks/recent
reading and partial/empty data continue to govern visibility.

## Verification

On 13 September 2026:

- `flutter test --no-pub test/user_summary_test.dart test/user_summary_model_test.dart test/user_summary_controller_test.dart`: 23 passed. Coverage includes routing, account lifecycle, refresh, selected-tab restoration, permissions, empty/error/loading states, value/action semantics, and 320/768px layouts at 200% text. A regression assertion checks that category names remain readable at enlarged text.
- `flutter analyze --no-pub`: no issues.
- `flutter build macos --debug --no-pub -t tool/user_summary_review_main.dart --dart-define-from-file=/tmp/native-summary-palette.json`: passed.
- `dart format` on the touched Dart files and `git diff --check`: clean.

`tool/user_summary_review_main.dart` mounts the actual production page with
fictional, in-memory data and theme/viewport/text/direction/state controls.
The optional `SUMMARY_PALETTE` define accepts a SiteAppearance JSON string;
without it the fixture uses theme defaults. The fixture also opens the actual
component styleguide. It performs no account requests.

Native review uses an isolated, ad hoc signed macOS bundle. Its permitted debug
entitlements were read back and its strict signature verified before actual
launch. The real app's provisioning and entitlements remain unchanged.

Native inspection covered the wide profile/Highlights layout in light, wide
Connections and Reading in dark, the stationary identity column during content
scrolling, and the 320px Reading layout. At 320px with 200% text and RTL,
the profile totals stack cleanly and category names retain their natural
width instead of wrapping one character per line. The table uses the kit's
horizontal scroll container when columns exceed the viewport.

Also inspected the Highlights and Reading empty states, cached refresh error
with its separate Retry control, skeleton loading announcement, and the
stats-unavailable state. Native AX output exposes separate topic/profile
actions, category count buttons, source-topic buttons, totals and badge labels.
The actual Card styleguide was inspected with the same dark forum theme.

This is macOS fixture review, not iOS/Android device testing or a full VoiceOver
audit. Exact navigation destinations and recovery behavior were verified by
the focused widget/controller tests; external links were not launched.

Native review source SHA-256, before the follow-up description removals:

- `lib/src/shell/user_summary.dart`: `f63f652735cfc747a1ea896cb4a7177afda915cd5643b34afd684f2c5ceb6a18`
- `tool/user_summary_review_main.dart`: `7ac7419861ef26354d8fb01fefe383c26b71492b7bbc33f272dba264edad6f0b`
- macOS fixture `kernel_blob.bin`: `a72671a3440cbfbe577aaffaf4b4dc20d6eaff9a13858829e6675c43ae03f220`

## Main integration

Prepared from main `4e39ad0a6cb31f4265635731f6c874237e839822`, preserving the
implementation commit `49d8d2c0`. The merge required no conflict resolution.
The final copy removals are included. On the combined source, all 23 focused
summary tests passed again, full `flutter analyze --no-pub` reported no issues,
and formatting, JavaScript syntax and patch whitespace checks were clean.
