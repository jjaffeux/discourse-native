# Channel and DM scrolling

The channel benchmark now covers one-to-one DMs and group DMs as well as public
channels. Captures identify the conversation kind and record each row's layout
duration and size (`chat.row.layout`) and full date-extent scans
(`chat.dayExtents.scanned`). The compact export includes both distributions;
the JSON associates the work with engine frames and available CPU samples.
Events contain row indices, sizes, counts and timings, never message bodies or
account identities. Disarmed observers do not collect timestamps or event maps.

## Finding and fix

The virtualizer reports every scroll layout, including layouts that reuse all
child sizes. The stream treated every notification as changed row heights,
invalidating its floating-date prefix sums and scanning the whole loaded
history again on the next frame. This added work proportional to history size
even when scrolling within a single already measured row.

The stream now invalidates those sums when a row actually lays out. Changes to
the stream's rows and pagination leading rows still invalidate the index.
The layout observer also catches image/content resizing and viewport changes
without rebuilding message widgets or changing the Native scroller's API.

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

The focused scroll, DM, channel lifecycle, thread workspace and capture suites
pass (134 tests); `dart analyze` reports no issues. Two lifecycle assertions
were updated for the centered row padding already merged in `ec9ec0c0`.

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
