# App operation latency benchmarks

The benchmarks time individual production operations through completion or
publication in the app model. They compare macOS ARM64 Flutter release
builds against `7c62c3e6c`, reversing baseline and candidate order on
successive pairs. The drivers assert outputs and relevant request counts.
The table shows process medians and observed ranges in milliseconds.

Forum requests use a controlled 30 ms response delay. Authorization uses a
55 ms push-registration fixture and runs real ephemeral RSA key generation
and callback decryption. Random prime search varies between runs. The voice
report fixture starts with an enabled moderator flag in the site catalog.
The dashboard may request one extra previous period for the core overview
when current data cannot be compared. Live server, platform and UI frame
timings vary.

Run from the repository root on Apple Silicon macOS.

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py --baseline 7c62c3e6c \
  --driver benchmark_group_membership_latency.dart \
  --driver benchmark_notification_dismiss_latency.dart \
  --driver benchmark_dashboard_and_authorization.dart \
  --driver benchmark_plugin_mutation_latency.dart \
  --driver benchmark_topic_feed_and_category_latency.dart \
  --output /tmp/discourse-operation-latency-fourth.json
```

| Operation | Before [range] | After [range] | Saved |
| --- | ---: | ---: | ---: |
| Add a group member and refresh group detail and member rows | 96.197 [96.144, 96.456] | 64.241 [64.108, 64.321] | 31.956 |
| Mark all notifications read and refresh rows and totals | 96.307 [96.208, 96.366] | 64.268 [64.148, 64.281] | 32.039 |
| Authorize a forum account with push registration | 145.399 [119.037, 190.173] | 81.775 [64.972, 141.538] | 63.624 |
| Refresh the admin dashboard with a previous-period comparison | 96.609 [96.052, 96.760] | 64.511 [64.382, 64.768] | 32.098 |
| Save and verify a gamification leaderboard | 96.245 [95.595, 96.298] | 64.222 [64.188, 64.272] | 32.023 |
| Browse chat threads across four channels | 160.365 [159.581, 160.538] | 64.196 [64.180, 64.253] | 96.169 |
| Report a voice participant with a warm flag catalog | 64.174 [64.158, 64.224] | 32.073 [32.066, 32.090] | 32.101 |
| Refresh three retained bookmark-filtered feeds | 96.185 [96.139, 96.277] | 32.146 [32.109, 32.186] | 64.039 |
| Change a draft category and revalidate three tags | 96.135 [96.126, 96.307] | 32.069 [32.063, 32.083] | 64.066 |
| Save an existing topic category after three tag checks | 128.205 [127.999, 128.289] | 64.135 [64.125, 64.147] | 64.070 |

[Raw samples](benchmark_operation_latency_fourth.json)
