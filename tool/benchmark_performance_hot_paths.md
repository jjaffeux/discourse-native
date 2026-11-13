# Performance hot paths

Run these commands from the repository root on Apple Silicon macOS with the
project's Flutter SDK and Xcode command-line tools.

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py --baseline ac4e51af7 --output /tmp/discourse-performance.json
```

The runner builds the same four drivers against the baseline sources and the
current checkout with the same dependencies. Both sides use release Dart AOT
and the same macOS Flutter engine in a headless runner. It alternates which
revision runs first and saves every process median. Pass
`--driver benchmark_chat_timeline.dart` to rerun only the chat cases, or use
`--help` for the other driver names.

Each driver checks the results against expected data and exits with an error
if any check fails. The timings cover in-memory operations on production Dart
entry points. They measure elapsed time on the benchmark host and do not measure
network latency, frame time, or performance on a phone.

The JSON decoder bypasses MIME and charset parsing for the two common JSON
headers. The palette parser sends only plausible palette rules to csslib.
The topic merge skips building a membership set when the incoming stream ends
with the last held ID.

Checklist annotation clears copied indexes and finds owned boxes in one tree
walk. Composer literal detection checks line starts on ordinary LF drafts.
Link detection skips directly to a bracket when no label is open and no
inline callback needs to inspect intervening characters.

Chat paging removes held IDs from the incoming page map. Chat reordering
sorts entries with their timestamps in hand. Search expression parsing
builds the localized filter definitions once per expression. Emoji
autocomplete uses the catalog's alphabetical order and can stop when enough
prefix matches fill the result.

## Results

Medians and ranges are in microseconds per operation, with five release
processes per revision. All output checks passed. The raw samples are in
[benchmark_performance_hot_paths.json](benchmark_performance_hot_paths.json).

| Operation | Before [range] | After [range] | Less time |
| --- | ---: | ---: | ---: |
| Annotate a 30-item post checklist | 245.360 [244.503, 246.357] | 222.527 [219.747, 234.437] | 9.3% |
| Detect literal containers in an 80-paragraph draft | 100.332 [97.650, 105.519] | 47.411 [44.356, 48.097] | 52.7% |
| Find 40 Markdown links in a draft | 16.001 [15.816, 16.321] | 9.136 [8.779, 9.450] | 42.9% |
| Decode a small JSON response | 0.770 [0.750, 0.877] | 0.532 [0.489, 0.562] | 30.9% |
| Extract a palette from a theme with 400 unrelated rules | 6670.750 [6410.650, 6867.733] | 1219.117 [1165.500, 1237.433] | 81.7% |
| Merge an unchanged 3,000-post topic refetch | 44.913 [41.113, 45.846] | 11.076 [10.328, 11.337] | 75.3% |
| Prepend a 50-message chat page with 1,000 messages held | 25.888 [24.991, 26.611] | 18.162 [17.900, 18.894] | 29.8% |
| Reorder a late arrival among 1,000 held chat messages | 122.952 [117.871, 124.336] | 82.232 [79.381, 85.169] | 33.1% |
| Parse a global search expression | 76.045 [74.290, 83.915] | 25.403 [25.085, 26.855] | 66.6% |
| Rank composer emoji suggestions for 11 queries | 108.815 [106.636, 110.682] | 72.248 [69.764, 74.655] | 33.6% |

The stale topic refetch control measured 61.843 → 63.498 µs. The sparse
emoji control measured 100.406 → 96.925 µs. Both had overlapping ranges.
