# Performance gains of at least 5 ms

Each row times one production operation through completion. Both revisions
run in the macOS Apple Silicon Flutter release AOT engine. The runner
alternates revision order across five pairs of fresh processes. The theme
and artwork drivers report the median of seven measured actions per process.
The feed and shell drivers measure one checked action per process. Output
checks cover saved selections, icon names and symbol definitions, notification
state, and feed contents or topic IDs.

The theme fixture holds 120 saved light/dark palettes and 12 connected forums.
It uses in-memory persistence and includes the controller's restore or save
operation. This is a large library, so expect less absolute savings for
smaller libraries. Network fixtures replace the remote service with fixed
delays. Feed, topic recovery, notifications, and shell requests use 30 ms.
Appearance uses 80 ms for the forum document and 30 ms for its other requests.
The artwork fixture uses 18–65 ms for individual icons and 30 ms for each
composite symbol. Actual savings depend on server latency and concurrent
request capacity. These runs do not measure rendered frames or phone performance.

## Reproduce

Run from the repository root on Apple Silicon macOS with the project's Flutter
SDK and Xcode command-line tools.

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py --baseline 832b0676e \
  --driver benchmark_theme_restore_five_ms.dart \
  --driver benchmark_sidebar_artwork_five_ms.dart \
  --driver benchmark_appearance_five_ms.dart \
  --driver benchmark_five_ms_feed.dart \
  --driver benchmark_five_ms_shell_feed.dart \
  --output /tmp/discourse-five-ms.json
```

## Results

Times are milliseconds. Brackets show the minimum and maximum process
measurements. The saving is the difference between revision medians.
[Raw samples](benchmark_performance_five_ms.json)

| Operation | Before [range] | After [range] | Saved |
| --- | ---: | ---: | ---: |
| Restore saved forum themes | 11.47 [9.48, 14.64] | 0.73 [0.69, 1.68] | 10.74 |
| Save a forum theme selection | 17.76 [17.23, 19.12] | 1.83 [1.24, 3.25] | 15.93 |
| Load 12 custom sidebar icons | 205.94 [204.39, 210.79] | 110.69 [108.57, 116.33] | 95.25 |
| Resolve a composite sidebar icon | 103.94 [98.41, 106.83] | 67.44 [65.71, 70.37] | 36.50 |
| Load signed-in forum appearance | 185.61 [178.70, 192.29] | 151.12 [146.59, 152.91] | 34.50 |
| Restore four evicted topic summaries | 135.51 [130.72, 136.08] | 32.42 [32.35, 32.90] | 103.09 |
| Recover a topic submission among three same-title topics | 230.97 [226.14, 242.67] | 106.41 [96.51, 109.14] | 124.56 |
| Dismiss assignment notifications and refresh the badge | 100.12 [96.91, 107.03] | 64.93 [64.63, 69.81] | 35.19 |
| Reconcile a reader visit and refresh the source list | 64.64 [64.61, 64.73] | 32.47 [32.42, 32.48] | 32.17 |
| Load the sidebar when switching to a connected forum | 64.39 [64.36, 64.49] | 32.24 [31.26, 32.28] | 32.14 |
