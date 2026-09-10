# Topic filter Combobox migration

The category, subcategory and tag controls in `TopicListFilterBar` now compose
the public Native `DCombobox`, `DComboboxTrigger`, `DComboboxInput`,
`DComboboxList`, `DComboboxStatus` and `DButton` APIs. Category rows retain
`CategoryIcon`; root and child categories share one application adapter.

Category search retains an always-available All option and clears its query
when reopened. Tags retain single-value slugs, multiple-value names, selected
counts, case-insensitive known-tag matching, the 250ms debounce, serial
latest-wins requests, known-tag fallback on errors and All tags while loading.
Multiple choices close after selection, matching the previous behavior.
Lookup work begins on open and is invalidated on dismissal or disposal.

The user also authorized the missing Combobox keyboard Done behavior. Ordinary
and chip inputs now submit the enabled, visible highlight through the same
handler as Enter. Submission preserves focus when no result is eligible and
respects the existing close-on-select policy.

The existing feed/account/tab/session guard still rejects retired callbacks.
Replacing that owner now removes the Popover with its anchor, so lifecycle
tests assert dismissal without a Navigator pop. Before-frame forum-switch
regressions still invoke the original controls and assert that no replacement
feed is changed.

## Native inspection — 2026-09-10

Built `tool/topic_filters_review_main.dart` with Flutter 3.47.2 using
`flutter build macos --debug --no-pub -t tool/topic_filters_review_main.dart`.
The fixture mounts the production filter bar and the existing Combobox Popup
styleguide example with local data only. No account data is read or written.

Inspected a separate ad-hoc signed copy at
`/tmp/DiscourseTopicFiltersReview-01a08cde.app`, bundle identifier
`org.discourse.native.topic-filters-review.01a08cde`. The copy omits restricted
team/application/push entitlements; read-back confirmed only sandbox, JIT and
network client/server debug entitlements. Deep strict signature verification
and actual macOS launch succeeded. The production bundle was not modified.

Under the desktop lease, CUA inspected:

- Dark category popup, retained color indicators, local filtering and Return
  selection; subcategory search and its no-match state.
- Dark tag loading, remote results and Return selection; reopening with a
  remote selection, adding a known tag and the two-tag trigger count.
- Light palette, selected check indicator and clearing all tags.
- A 320px fixture lane, 200% text, RTL alignment, wrapped long category labels
  and scrolling to later options.
- The real Combobox Popup styleguide example at the same RTL/text scale.
- Escape dismissal and visible trigger focus restoration.

CUA screenshots and AX observations are retained in the task conversation.
The review app was quit and the desktop lease released. This is a native macOS
pass, not an iOS/Android device or spoken VoiceOver pass. The kit's existing
visual primitives were composed without changing their renderer.
The subsequent Done-handler addition was verified with Flutter text-input
actions in widget tests; the native visual pass predates that handler.

## Verification

- Root `flutter analyze --no-pub`: no issues.
- 229 focused tests passed with seed `391447`: `test/ui/d_combobox_test.dart`,
  `test/topic_list_filter_bar_test.dart`,
  `test/styleguide/combobox_examples_test.dart`,
  `test/topic_list_navigation_test.dart`,
  `test/topic_list_filter_menu_ownership_test.dart`,
  `test/shell_navigation_integration_test.dart` and `test/group_page_test.dart`.
- Coverage includes Done selection/no-match/disabled results, multiple input
  closing policies, all six original tag Done regressions, concurrent lookup
  invalidation, popup focus and dismissal, routing and retired feed ownership,
  multiple tags, 320px layouts at 200% text in both directions, and the existing
  group-member Combobox consumer.
- `dart format` on touched Dart files and `git diff --check`: clean.
