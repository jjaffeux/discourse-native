# Topic-list category and tag dropdowns

Reference: `discourse-native-mockups` commit
`37001839df3efbeb5f2650668a38140462ce9c45`, specifically `CategoryPath`,
`FilterSheet`, `FilterOption`, and `tagPillLabel` in `src/App.tsx`.

- Each category breadcrumb opens its own sibling level. The menu browses
  children separately from selecting the whole category, shows ancestry for
  search results, and displays category counts from the forum's data.
- Exact category selection has an explicit "No subcategories" breadcrumb.
  Selecting another category replaces exactness. Backspace removes exactness,
  then ancestry; a shortened path retains the editor on its remaining segment.
- Scoped menus show only their own filter chips, hide the syntax prefix, and
  use category/tag search placeholders. Category selection closes immediately;
  tag choices and matching modes update the list while their menu stays open.
  Other category, tag, and advanced clauses remain intact.
- Tags retain usage order, one checkbox per selection, four matching modes,
  and a Done row. Pills describe single, multiple, excluded, group, and special
  tag scopes. Group and special choices depend on the server's vocabulary.
  The approved Native compact checkbox preset is 14px, with matching hit bounds.
  Native toggle groups wrap the matching modes as text grows, preserving their
  selection and keyboard navigation.
- Desktop menus remain inside their owning pane; phones use the Native
  adaptive menu sheet and wait for an explicit request to focus the input.
  Escape clears a search first, then dismisses. This uses the approved Native
  `DPopover.onEscape` hook.
- Feed, tab, forum, account, and session replacements retire the editor and
  pending lookups. Live choices may replace only their own feed; they cannot
  adopt a different navigation context.

The focused widget tests exercise the production shell and fake API contracts.
Real-font captures cover desktop/phone, Standard/Liquid Glass, light/dark, and
200% text. These are widget renders, including the test renderer's glass
fallback, rather than physical-device captures. Set `SIDEBAR_FILTER_REVIEW_DIR`
when running `test/topic_taxonomy_dropdown_parity_test.dart` to export PNGs.

## Performance checks

`test/topic_taxonomy_scroll_performance_test.dart` drives the production menus
with scrollable category/tag data on desktop and phone layouts in both materials.
It verifies real scroll movement, stable viewport geometry, cached row text,
and no repainting of the stationary input or underlying page. Hover must still
change selection without rebuilding the editor. The Native command regression
in `test/ui/d_command_test.dart` bounds highlight rebuild work with 500 rows.

The native timing fixture uses the production `DiscourseApp`, 250 categories,
500 tags, actual view size/pixel ratio, and fake API responses. It measures
opening, six seconds of bidirectional scrolling after warmup, actual row hover,
searching, tag selection, matching modes, and closing. Assertions verify scroll
extent/position, highlight changes, filtered results, and applied selections.
Frame timing batches are filtered by the measured action's timestamps. JSON
reports include p50/p95/p99/max build and raster durations and counts above
8.33/16.67 ms. These are Flutter frame costs, not end-to-end input latency or
GPU completion times; phase percentiles also include intervening idle frames.

Run the native fixture with the integration driver (this SDK's `flutter test`
does not support `--profile`):

```sh
flutter drive --no-pub --no-start-paused --profile -d macos \
  --driver integration_test/performance_driver.dart \
  --target integration_test/topic_taxonomy_performance_test.dart \
  --dart-define=PROFILE_LABEL=current
```

Use a physical device ID for iPhone profiling; simulator/debug measurements
cannot establish physical-device performance. If local macOS provisioning is
unavailable, a temporary `XCODE_XCCONFIG_FILE` containing
`CODE_SIGNING_ALLOWED = NO` allows this local benchmark to build without
changing project signing settings.

The scroll header is a repaint boundary. Highlight-only notifications preserve
the editor and command list, and only rows whose selected state changes rebuild.
The command controller's public notifications and selection behavior are retained.

The results list still mounts all matching rows. Opening/restoring a long list
or changing tag selections can therefore exceed a frame budget even when its
steady scrolling is cheap. The stress workload is intended to expose this
limit; passing its interaction assertions is not a claim of hitch-free rendering.

Native macOS profile capture on 2026-10-15: 1280x860 logical pixels, DPR 2,
250 categories and 500 tags. The macOS engine reported shader filters unsupported,
so the Liquid Glass setting used its fallback. No physical iPhone timing claim
is established by this run.

| Menu | Material setting | Scroll build p95 | Scroll raster p95 | Hover build p95 |
| --- | --- | ---: | ---: | ---: |
| Category | Standard | 0.622 ms | 1.887 ms | 0.703 ms |
| Category | Liquid Glass fallback | 0.757 ms | 2.141 ms | 0.762 ms |
| Tags | Standard | 0.868 ms | 2.175 ms | 0.738 ms |
| Tags | Liquid Glass fallback | 0.947 ms | 2.155 ms | 0.842 ms |

Each scroll capture recorded 726 frames; none exceeded 8.33 ms of build or
raster work. Peak tag search builds reached 105 ms, selection/matching-mode
builds reached 41 ms, and opening the 500-tag menu reached 96 ms of build work.
The first category opening also recorded a 186 ms raster spike. These remaining
list-construction costs require separate optimization. The native fixture's 24
phases and all 114 directly related widget tests passed.
