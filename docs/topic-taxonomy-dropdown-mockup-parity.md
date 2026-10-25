> Historical design and capture notes. The app now uses the [flat appearance](material-mockup-parity.md); earlier glass and depth measurements describe the retired rendering.

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

## Selected-filter header

`FilterToken` and the inline field in the reference's `FilterSheet` define the
header geometry. Native `DFilterToken` puts independent edit/remove actions
inside one translucent accent pill: 12/18px text, a 5px label/value gap, 9px outer
insets and a 10px remove glyph. The category key uses the theme's accent text;
the value is semibold. Actions retain separate accessible names and Enter/Space
activation, including when nested inside the command menu.

`DCommandInputDensity.menuFilter` uses 13px borderless text with 3px/4px insets.
Tokens and query share a 5px wrapping row; the query fills remaining space or
moves below when less than 90px remains. The header has 2px top/side and 8px
bottom padding above its stationary separator. Both controls use Native's
reference text scale, retaining app zoom and OS accessibility without the mobile
reading-text uplift. Short and long selected values retain bounded pill targets.

`test/topic_taxonomy_header_test.dart` renders the selected **baking** category
on macOS/iOS Liquid Glass and Linux/Android Standard, at normal and 200% text.
The owning Native tests check adjacent action bounds, RTL, keyboard activation,
and the query's 90px wrapping threshold. Existing production tests exercise
editing, removal, search, Escape/Backspace and retained unrelated filters.

The native iPhone 18 Pro simulator checks also passed at normal and 200% text,
using the actual 402x874 logical viewport, DPR 3 and Liquid Glass shaders. Both
PNG captures were inspected; these are simulator renders, not physical-device
captures.

For actual iPhone renderer screenshots (using an isolated bundle as below):

```sh
TAXONOMY_REVIEW_DIR=/private/tmp/taxonomy-native-header \
flutter drive --no-pub --no-start-paused --debug -d <simulator-id> \
  --driver integration_test/taxonomy_header_driver.dart \
  --target integration_test/topic_taxonomy_header_test.dart
```

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

Long command lists now mount a lazy viewport with individual row repaint
boundaries. Short menus retain their shrink-wrapped geometry. Keyboard navigation
reveals unmounted variable-height rows, including Home/End and filtered results.
The long viewport fills its bounded menu: shrink wrapping caused a fractional
iOS scroll-offset correction loop during sheet expansion in the native run.
Regression checks bound resident artwork and preserve cached visible text; rows
entering the viewport paint once. Filtering still scores the full vocabulary,
so these changes do not establish constant-time search or selection.

Historical macOS profile capture at `72ccf56ac` on 2026-10-15: 1280x860 logical pixels, DPR 2,
250 categories and 500 tags. The macOS engine reported shader filters unsupported,
so both saved material settings used Liquid Glass fallback. Apple platforms
force Liquid Glass; the saved Standard setting did not exercise Standard rendering. No physical iPhone timing claim
is established by this run.

| Menu | Saved setting (both effective Glass fallback) | Scroll build p95 | Scroll raster p95 | Hover build p95 |
| --- | --- | ---: | ---: | ---: |
| Category | Standard | 0.622 ms | 1.887 ms | 0.703 ms |
| Category | Liquid Glass fallback | 0.757 ms | 2.141 ms | 0.762 ms |
| Tags | Standard | 0.868 ms | 2.175 ms | 0.738 ms |
| Tags | Liquid Glass fallback | 0.947 ms | 2.155 ms | 0.842 ms |

Each scroll capture recorded 726 frames; none exceeded 8.33 ms of build or
raster work. Peak tag search builds reached 105 ms, selection/matching-mode
builds reached 41 ms, and opening the 500-tag menu reached 96 ms of build work.
The first category opening also recorded a 186 ms raster spike. These were the
eager renderer's construction costs before the lazy-list fix. The historical
fixture's 24 phases and 114 directly related widget tests passed.


### Long-list iPhone touch comparison

The native iPhone 18 Pro simulator (iOS 27, 402x874 logical pixels, DPR 3)
exercised 2,000 tags with the real Impeller Liquid Glass shader path. Debug-mode
before/after captures used the same workload: sheet expansion by touch, a
three-second bidirectional pointer stream at 120 Hz, and three ballistic flings.
Both saved material settings resolve to Liquid Glass on iOS. Cases are repeated
workloads, not comparisons between materials.

| Workload | Eager renderer | Lazy renderer |
| --- | ---: | ---: |
| Mounted tag rows | 2,000 | 7 opening; 18-23 expanded/scrolling |
| Opening peak build, first / second case | 1,441 / 1,048 ms | 129 / 39 ms |
| Touch drag raster p95, first / second case | 6.69 / 6.39 ms | 5.10 / 3.93 ms |
| Fling raster p95, first / second case | 6.57 / 6.36 ms | 4.98 / 4.03 ms |
| Touch-event scheduling lateness p95, first / second case | 47.3 / 49.7 ms | 16.2 / 16.9 ms |

Touch-event lateness measures the test driver's injection backlog, not physical
end-to-end touch latency. Debug simulator timings vary with host load; they do
not establish physical iPhone frame rates. Both eight-phase captures passed
movement and interaction assertions. The optimized run still recorded a 41 ms
opening raster frame and a 52 ms sheet-expansion raster frame, so opening and
sheet animation are not claimed hitch-free. Physical-device profiling was
attempted with an isolated benchmark app ID but blocked by missing local Xcode
account/provisioning; the user's installed phone app was not replaced.

```sh
flutter drive --no-pub --no-start-paused --debug -d <simulator-id> \
  --driver integration_test/performance_driver.dart \
  --target integration_test/topic_taxonomy_performance_test.dart \
  --dart-define=TAXONOMY_TOUCH_ONLY=true \
  --dart-define=TAXONOMY_TAG_COUNT=2000 \
  --dart-define=PROFILE_LABEL=touch-current
```

For an isolated iOS bundle, point `XCODE_XCCONFIG_FILE` at a temporary file with
`PRODUCT_BUNDLE_IDENTIFIER = org.discourse.native.taxonomy-performance`.
Use `--profile` and a provisioned physical-device ID for actual iPhone timings.
