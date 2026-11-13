# App operation latency benchmarks

Each sample measures one production operation from entry through completion
or canonical publication. The runner alternates baseline and candidate
order across five pairs of macOS ARM64 Flutter release AOT processes.
The drivers check the operation's result and relevant request counts or
retained state. Values are milliseconds per operation.

Media runs use real temporary-file staging, a 35 ms HTTP fixture and 12 ms
adapter delays for directory and credential lookups where used. The video
attachment fixture uses a 2 MiB source and a stubbed encoder with a 40 ms
encoding delay. The other operations use 30 ms service responses. The
benchmarks demonstrate the savings under those conditions. They do not
measure native codec performance, live server latency, or phone frames.

From the repository root on Apple Silicon macOS:

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py --baseline 0f430ae05 \
  --driver benchmark_media_operation_latency.dart \
  --driver benchmark_solution_operation_latency.dart \
  --driver benchmark_nested_reload_latency.dart \
  --driver benchmark_nested_admin_latency.dart \
  --driver benchmark_feed_latency_followup.dart \
  --output /tmp/discourse-operation-latency.json
```

| Operation | Before [range] | After [range] | Saved |
| --- | ---: | ---: | ---: |
| Share a downloaded image | 66.24 [65.66, 66.73] | 52.11 [51.85, 52.35] | 14.13 |
| Save a protected video | 66.59 [65.57, 67.19] | 52.19 [51.93, 52.95] | 14.40 |
| Prepare a composer video attachment | 73.57 [72.84, 75.27] | 58.63 [58.28, 65.80] | 14.95 |
| Replace an accepted solution | 128.26 [127.92, 128.37] | 96.22 [95.83, 96.31] | 32.04 |
| Reload three expanded nested-reply branches | 128.38 [127.50, 128.47] | 64.26 [63.80, 65.10] | 64.12 |
| Recheck nested-reply admin settings | 64.09 [64.06, 64.18] | 32.09 [32.05, 32.09] | 32.00 |
| Open an uncached category directory | 64.35 [64.19, 64.45] | 32.22 [31.64, 32.24] | 32.13 |
| Resolve an uncached chat bookmark | 64.26 [63.07, 64.34] | 32.19 [32.18, 32.20] | 32.07 |
| Open an uncached chat thread | 64.35 [64.31, 64.37] | 32.19 [31.89, 32.22] | 32.15 |
| Repair retained posts after bulk moderation | 96.40 [94.74, 96.47] | 32.17 [31.90, 32.20] | 64.23 |

[Raw samples](benchmark_operation_latency_followup.json)
