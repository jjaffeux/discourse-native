# Topic prepend scrolling — September 14

The supplied 16.6-second debug capture contained 134 UI frames over the
8.33 ms budget out of 1,160 frames, with a 224.95 ms maximum. No raster frame
exceeded the budget. Four of its five worst UI frames coincided with earlier
pages being prepended. They built many new reply trees and disposed them in
the same frame; viewport bookkeeping itself remained below 0.5 ms.

## Causes and changes

`SuperSliverList` uses Flutter's `replaceMovedChildren: true`: moving a keyed
reply also constructs a replacement at its old index. With retained replies,
this includes offscreen slots. Those temporary trees parse HTML and compete
for retention, evicting useful replies that then need rebuilding on return.
Unkeyed separators also leave children at the old positions.

The topic now uses a small layout adapter around the same sliver. It disables
replacement construction, moves separators with their replies, and restores
child offsets from the extent table that TopicView shifts before rebuilding.
This adapter deliberately accesses the package's internal element and render
classes; dependency upgrades must run the topic lifecycle and churn tests.
Native controls and the retention limits are unchanged.

Prepending also rebases the scroll position by the inserted estimated height
before layout, preserving the active scroll activity. The renderer compensates
for changes in preceding slivers during layout, including the Inbox activity
summary revealed when the first page arrives. These corrections preserve an
ongoing drag instead of depending on a later anchor jump that dragging cancels.
The extent table is also retained when earlier and later pages arrive together.

## Native measurement

The `SCROLL_PREPEND` fixture starts with replies 95–114 from the existing
114-reply synthetic rich discussion, warms several replies, and prepends 20
replies before each of two passes. Each pass scrolls up and back using two
60 × 40 pixel wheel legs. It contains quotes, code, lists and links, with no
network media or private content.

Baseline `05a14e18` and final candidate `aa33c19e` ran in separate macOS profile
processes with Flutter 3.47.2, a 120 Hz display, DPR 2, and a 1280 × 860 logical
viewport. One baseline run, one intermediate fixed run, and one final fixed run
are recorded in [topic-prepend-scrolling.json](topic-prepend-scrolling.json).

| Measurement | Baseline pass 1 / pass 2 | Final pass 1 / pass 2 |
| --- | ---: | ---: |
| UI duration of the prepend frame | 19.80 / 35.20 ms | 2.30 / 1.02 ms |
| Maximum UI frame in the whole pass | 19.80 / 35.20 ms | 4.97 / 1.89 ms |
| UI overruns in topic-active frames | 1 / 1 | 0 / 0 |
| Reply mounts during the whole pass | 15 / 30 | 1 / 0 |
| Reply disposals during the whole pass | 11 / 31 | 0 / 0 |
| Reply layouts during the whole pass | 16 / 29 | 5 / 2 |

The final run had 124 and 123 topic-active frames. One first-pass raster
overrun remained in both baseline and final runs. These small local samples
demonstrate the removed work; they are not a general frame-rate guarantee or
measurements of the private topic, cold complex media, or mobile devices.
Debug timings are not directly comparable with these profile timings.

Reproduce with:

```sh
flutter run --profile -d macos -t tool/topic_scroll_profile_main.dart \
  --dart-define=SCROLL_PREPEND=true --dart-define=SCROLL_LABEL=prepend
```

## Verification

All eight new regressions fail on the baseline and pass on the fix. They cover
both topic layouts, keeping or removing the earlier-page header, an ongoing
drag, simultaneous page arrivals, preservation of visible and offscreen HTML
elements, and zero premature earlier-reply HTML mounts. Existing tests cover
long async posts, measured heights, offscreen edits, selection, navigation,
reading progress, and paging retries.

The final candidate based on main `c9e5719c` passed 301 selected tests and
full-project static analysis. One existing test, `keeps action hover
affordances inside the viewport`, failed its menu-cursor expectation on both
the baseline and the fix and was excluded from that final passing run.

Native inspection of the final profile build verified scrolling through
earlier pages, matching topic progress, and selecting returned text with the
Copy quote toolbar.
