# App operation latency benchmarks

The benchmarks time individual production operations through completion or
publication in the app model. They compare macOS ARM64 Flutter release
builds against `d66b18efb`, reversing baseline and candidate order on
successive pairs. The drivers assert outputs and relevant request counts.
The table shows process medians and observed ranges in milliseconds.

Network cases use controlled 30 ms fixture responses. The voice fixture
models an iOS native mute transaction with a 30 ms delay. The Linux inline
video fixture uses a simulated WebView adapter on macOS with 12 ms replies
for three configuration calls. The draft cases use real private file I/O
with a 20 ms directory-provider fixture and warm API keys. Live server,
platform and UI frame timings vary.

The warm dashboard may issue an extra report batch when the dashboard layout
changed on the server. Badge, thread and gamification readers can dispatch
a speculative read that is discarded when its admission check fails.

Run from the repository root on Apple Silicon macOS.

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py --baseline d66b18efb \
  --driver benchmark_dashboard_refresh_latency.dart \
  --driver benchmark_badge_detail_latency.dart \
  --driver benchmark_plugin_reader_latency.dart \
  --driver benchmark_composer_moderation_latency.dart \
  --driver benchmark_account_and_composer_latency.dart \
  --output /tmp/discourse-operation-latency-fifth.json
```

| Operation | Before [range] | After [range] | Saved |
| --- | ---: | ---: | ---: |
| Refresh an already loaded admin dashboard | 69.722 [67.824, 73.013] | 34.732 [33.437, 35.787] | 34.990 |
| Open a badge and its recipient list | 64.904 [64.598, 65.415] | 32.671 [32.613, 32.978] | 32.233 |
| Reopen a visible chat thread | 66.018 [65.679, 67.469] | 33.024 [32.244, 33.703] | 32.994 |
| Refresh enabled gamification admin | 66.976 [64.727, 67.250] | 32.463 [32.357, 33.541] | 34.513 |
| Join a voice room initially muted | 65.121 [64.354, 65.969] | 33.190 [32.383, 33.932] | 31.931 |
| Open the composer in an uncached category | 64.688 [63.542, 64.973] | 32.403 [31.982, 32.433] | 32.285 |
| Reconcile a whole-topic moderation action | 64.540 [63.679, 65.924] | 32.469 [31.854, 32.531] | 32.071 |
| Disconnect an account and purge its drafts | 82.247 [81.567, 83.237] | 57.235 [56.984, 57.819] | 25.012 |
| Prepare the Linux inline video player | 42.711 [42.293, 42.777] | 14.361 [14.054, 14.375] | 28.350 |
| Restore a new-topic draft from the server | 79.352 [78.764, 79.945] | 56.088 [55.914, 56.517] | 23.264 |

[Raw samples](benchmark_operation_latency_fifth.json)
