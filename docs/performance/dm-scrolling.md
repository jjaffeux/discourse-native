# Channel and DM scrolling

The channel benchmark now covers one-to-one DMs and group DMs as well as public
channels. Captures identify the conversation kind and record each row's layout
duration and size (`chat.row.layout`) and full date-extent scans
(`chat.dayExtents.scanned`). The compact export includes both distributions;
the JSON associates the work with engine frames and available CPU samples.
Events contain row indices, sizes, counts and timings, never message bodies or
account identities. Disarmed observers do not collect timestamps or event maps.

## Findings and fixes

The virtualizer reports every scroll layout, including layouts that reuse all
child sizes. The stream treated every notification as changed row heights,
invalidating its floating-date prefix sums and scanning the whole loaded
history again on the next frame. This added work proportional to history size
even when scrolling within a single already measured row.

The stream now invalidates those sums when a row actually lays out. Changes to
the stream's rows and pagination leading rows still invalidate the index.
The layout observer also catches image/content resizing and viewport changes
without rebuilding message widgets or changing the Native scroller's API.

CPU samples also show rich HTML construction in slow jump frames. The existing
default-CSS parser cache lived only as long as one HTML body, so newly mounted
messages repeatedly parsed the same defaults. Those templates now share a
bounded isolate-local cache (64 entries, at most 4,096 characters per key).
When that pool fills, each body retains its original bounded local reuse for
additional styles, so earlier bodies cannot crowd out later messages.
Every lookup still returns independent declarations and expressions; callbacks
still run per element and their complete output forms the key. Attribute-
dependent colors, mutable build operations, custom/inline CSS, and complex
expressions retain their behavior. No widget, context, body, or resolved theme
state is shared. See the renderer's [patch manifest](../../packages/flutter_widget_from_html_core/PATCHES.md).

## Regression evidence

The deterministic 500-message widget fixture scrolls 360 steps at 10 pixels,
then 12 steps at 1,200 pixels in each direction. The baseline performs 384 full
date scans in every layout. With the fix:

| Conversation | Width / theme | Full scans | Existing message rebuilds |
| --- | --- | ---: | ---: |
| Channel | 800 / light | 74 | 0 |
| Channel | 360 / dark | 57 | 0 |
| DM | 800 / light | 74 | 0 |
| DM | 360 / dark | 53 | 0 |
| Group DM | 800 / light | 68 | 0 |
| Group DM | 360 / dark | 48 | 0 |

These counts represent an 81–88% reduction in full-history scans, not an
equivalent reduction in total frame time. The regression guard fails on the
instrumented baseline in all six layouts. Another test edits a visible DM
until its date crosses the viewport boundary, then resizes the viewport,
checking that the pinned date and measurements refresh without scrolling.

The focused renderer/cache, cooked HTML, text selection, scroll, DM, channel
lifecycle, thread workspace and capture suites pass (271 tests across two
commands). Root and renderer-package analysis pass. The renderer's standalone
seven-test suite and the vendor archive/patch inventory checks also pass.
Two lifecycle assertions were updated for the centered row padding already
merged in `ec9ec0c0`.

## Native measurements and limits

macOS profile builds used the installed Flutter 3.47.4, Skia/Metal, device pixel
ratio 2 and a 120 Hz display (8.33 ms budget), with Dart CPU profiling enabled.
The baseline includes the current DM layout from `ec9ec0c0` and the same
observational instrumentation. `fixed` in the [compact evidence](dm-scrolling.json)
isolates the date cache; `styles` includes both fixes. The evidence preserves
all runs and their order, including an alternating repeat and a later date-only
control. The measured shared-cache build predates the saturation fallback;
that later change retains the same shared-hit path and adds tested local reuse
only when the 64-entry pool fills. The 5,000-message input is pruned by the production window to **1,486
loaded messages**, as recorded in each capture's context.

| Incoming DM fixture | Phase | Baseline UI p95 | Both fixes UI p95 |
| --- | --- | ---: | ---: |
| 500 loaded | Steady | 2.13 ms | 1.09 ms |
| 500 loaded | Fast | 8.51 ms | 7.75 ms |
| 500 loaded | Return | 6.82 ms | 6.75 ms |
| 1,486 loaded, run 1 | Steady | 1.28 ms | 1.39 ms |
| 1,486 loaded, run 1 | Fast | 11.83 ms | 9.83 ms |
| 1,486 loaded, run 1 | Return | 8.67 ms | 8.18 ms |
| 1,486 loaded, repeat | Steady | 1.14 ms | 1.69 ms |
| 1,486 loaded, repeat | Fast | 10.31 ms | 7.04 ms |
| 1,486 loaded, repeat | Return | 8.51 ms | 6.21 ms |

The repeatable result is removal of redundant work. Native steady scrolling
performs 57 full date scans instead of 360; in the 500-message comparison, date
scan time fell from 7.3 ms total to 1.1 ms with the date fix alone. Native frame
times are noisier: the longer-history steady p95 increased in both runs, and
some fast frames still overrun while mounting HTML, shaping text and collecting
garbage. These short captures do not establish a universal frame-time speedup.
The final 500-message run had no UI overruns but three steady raster overruns;
the final longer-history runs had four and zero UI overruns respectively.

The final narrow dark group-DM capture had UI p95 of 1.08/7.12/4.34 ms for
steady/fast/return, no UI overruns, and one steady raster overrun. Manual native
review exercised mouse scrolling across pinned dates and jump-to-latest in an
800-pixel light DM using the date-cache build and a 360-pixel dark group DM
using the shared-style build, confirming message 500 and
the disappearance of the jump control. Rich text, lists, inline code and group
avatars rendered correctly. Captures use local incoming messages and fake
transport; live network media, real account histories, and mobile devices were
not profiled.

## Reproduce

```sh
flutter run --profile -d macos -t tool/chat_scroll_profile_main.dart \
  --dart-define=SCROLL_DM=true --dart-define=SCROLL_LABEL=dm
```

`SCROLL_GROUP=true` selects group DMs, `SCROLL_WIDTH=360` and
`SCROLL_DARK=true` select the narrow dark fixture, and `SCROLL_MESSAGES` changes
the loaded history size. Defaults remain an 800-pixel light public channel
with 500 messages. An already built native executable accepts the same options
as environment variables; `SCROLL_EXIT=true` exits after all three captures.
The reports' temporary file paths are printed after each phase.

See [the earlier channel investigation](chat-scrolling.md) for the existing
chrome-rebuild and offscreen-HTML fixes.
