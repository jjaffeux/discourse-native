# Performance round three

Run from the repository root on Apple Silicon macOS with the project’s Flutter
SDK and Xcode command-line tools.

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py --baseline 571d9dd71 \
  --driver benchmark_model_paths_round_three.dart --output /tmp/model-performance.json
python3 tool/compare_performance_hot_paths.py --baseline 571d9dd71 --runs 7 \
  --driver benchmark_feed_paths_round_three.dart --output /tmp/feed-performance.json
```

Both sides use the same release AOT engine and driver. Each process warms up
three batches and reports the median of seven measured batches. The runner
alternates baseline-first and candidate-first pairs. Each driver checks every
operation's output outside its timed loop. These are in-memory measurements
on macOS. Network latency, frame times, and phone performance are outside
their scope. See the [raw samples](benchmark_performance_round_three.json).

| Operation | Before [range], µs | After [range], µs | Less time |
| --- | ---: | ---: | ---: |
| Generate a draft list excerpt | 72.4577 [71.3192, 77.4615] | 40.7115 [38.8592, 41.9423] | 43.8% |
| Parse a plain search excerpt | 12.5440 [12.3663, 13.9506] | 10.7900 [9.9457, 10.9869] | 14.0% |
| Fingerprint 30 checklist markers | 101.5530 [98.6260, 115.3620] | 85.0110 [79.6180, 93.5660] | 16.3% |
| Rank 40 recent emoji uses | 8.8522 [8.2087, 8.9522] | 2.9296 [2.7591, 3.0287] | 66.9% |
| Resolve an animated emoji URL | 1.2353 [1.2296, 4.6249] | 1.1693 [1.0976, 1.2024] | 5.3% |
| Parse a numeric Retry-After header | 0.3145 [0.3119, 1.4048] | 0.0131 [0.0118, 0.0143] | 95.8% |
| Read 30 first-page account feed rows | 0.3162 [0.3061, 0.3372] | 0.0067 [0.0065, 0.0068] | 97.9% |
| Filter live topics by muted tags | 0.1789 [0.1752, 0.1830] | 0.1047 [0.1019, 0.1071] | 41.4% |
| Order a 320-category sidebar tree | 55.5476 [54.7232, 57.4556] | 51.3096 [50.2988, 51.9944] | 7.6% |
| Sort 100 chat channels by priority | 44.8407 [42.8571, 46.8946] | 18.5746 [18.3229, 19.1521] | 58.6% |

Draft excerpts batch printable ASCII while retaining grapheme-aware truncation.
Plain search excerpts bypass HTML parsing. Checklist fingerprints validate
and normalize markers in one pass. Favorite emoji ranking checks the tone suffix
directly, and animated emoji URLs reuse compiled patterns. Numeric Retry-After
headers validate digits and apply their cap without converting the cap to text.

Single-page account feeds reuse their immutable row list. Live topic filtering
can decide a tag match without materializing a list. Category ordering skips
the fallback traversal when all IDs are reachable. Chat priority ordering
computes comparison keys once per channel.

The category gain is smaller than the others. The first integrated run had
slightly overlapping ranges (53.406–57.602 µs before, 51.028–53.728 µs after).
