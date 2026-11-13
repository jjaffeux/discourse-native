# Performance round two

Run these commands from the repository root on Apple Silicon macOS with the
project's Flutter SDK and Xcode command-line tools.

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py \
  --baseline 28771ff42 \
  --driver benchmark_model_paths_round_two.dart \
  --driver benchmark_feed_paths_round_two.dart \
  --output /tmp/discourse-performance-round-two.json
```

Both revisions use the same benchmark drivers and Flutter release AOT engine.
Each driver warms up the operations, times repeated batches, and checks every
output. The runner alternates the order of the baseline and candidate in five
pairs. The table shows process medians and ranges in microseconds per operation.
The timings cover in-memory work and exclude network, rendering, and mobile
device performance. See the [raw samples](benchmark_performance_round_two.json).

| Operation | Before [range] | After [range] | Less time |
| --- | ---: | ---: | ---: |
| Extract text from a cooked HTML excerpt | 13.3471 [13.1657, 13.4286] | 7.2657 [7.1771, 7.3700] | 45.6% |
| Read a plain localized topic title | 0.9388 [0.9338, 0.9573] | 0.0515 [0.0495, 0.0538] | 94.5% |
| Parse a category color | 0.0968 [0.0937, 0.0990] | 0.0126 [0.0123, 0.0132] | 87.0% |
| Build an emoji asset URL | 0.5912 [0.5883, 0.5978] | 0.4634 [0.4576, 0.4698] | 21.6% |
| Find emoji shortcodes in display text | 2.6923 [2.6809, 2.7389] | 1.8420 [1.8274, 1.9014] | 31.6% |
| Classify a composer video attachment | 0.1561 [0.1516, 0.1589] | 0.1187 [0.1179, 0.1197] | 24.0% |
| Append a live message to 1,000 chat IDs | 7.8308 [7.7415, 7.8854] | 1.9038 [1.7469, 1.9523] | 75.7% |
| Append an account feed page with three overlapping rows | 11.8600 [11.6983, 12.3854] | 5.6087 [5.4650, 5.7417] | 52.7% |
| Project 512 unread topics that remain visible | 2.8929 [2.8653, 2.9590] | 1.6603 [1.6373, 1.6681] | 42.6% |
| Calculate a grouped notification badge total | 0.6398 [0.6294, 0.7017] | 0.0423 [0.0418, 0.0433] | 93.4% |

HTML excerpt extraction replaces repeated selector walks and DOM edits with one
text traversal. Plain localized titles bypass the parser. Category colors decode
directly from hex digits. Emoji asset URLs bypass tone parsing for bare names,
and shortcode matching skips code-range discovery on text without backticks.
Composer video detection reuses its extension pattern.

Chat append wraps the new list in a read-only view, avoiding a second copy.
Account feed append indexes only held rows that overlap the incoming page.
Unread projection allocates a filtered list only after a row is hidden.
Notification totals sum once at decode time and subtract excluded types when
the badge is queried.
