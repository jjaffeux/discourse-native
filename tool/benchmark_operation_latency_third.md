# App operation latency benchmarks

Each sample measures one production operation through completion or publication
in the app model. The comparison alternates baseline and candidate order over
five pairs of macOS ARM64 Flutter release AOT processes. The drivers verify
the result, including persisted picker preferences, output image dimensions,
refreshed records, chat navigation and messages, and the selected voice
devices. They also check relevant request counts. The table shows medians and
ranges in milliseconds across the five process results.

Forum responses use a controlled 30 ms delay. The cold emoji picker also
uses a 12 ms persistence adapter delay. The image case uses 15 ms each for
file-provider metadata and temporary-directory lookup, with real file staging,
image resizing and encoding. The voice case uses 30 ms per audio-device
selection at the platform adapter. These timings show savings under the
specified fixture conditions. Live forum, device and UI frame timings vary.

Run from the repository root on Apple Silicon macOS.

```sh
flutter pub get
flutter precache --macos
python3 tool/compare_performance_hot_paths.py --baseline ca861a39f \
  --driver benchmark_picker_and_board_latency.dart \
  --driver benchmark_image_and_event_latency.dart \
  --driver benchmark_chat_feed_operation_latency.dart \
  --driver benchmark_voice_device_restore_latency.dart \
  --output /tmp/discourse-operation-latency.json
```

| Operation | Before [range] | After [range] | Saved |
| --- | ---: | ---: | ---: |
| Open a cold emoji picker with saved tone and history | 48.216 [46.599, 48.245] | 33.202 [31.915, 33.294] | 15.014 |
| Resolve a prefilled emoji alias query | 66.199 [65.566, 66.235] | 33.139 [31.997, 33.143] | 33.060 |
| Clear a board column containing a topic card | 98.256 [98.042, 99.375] | 65.339 [65.054, 66.260] | 32.917 |
| Prepare and resize a composer image from a file provider | 71.450 [70.097, 72.078] | 53.290 [52.607, 54.637] | 18.160 |
| RSVP and reconcile the event and its topic | 98.438 [98.163, 99.300] | 65.690 [65.116, 66.321] | 32.748 |
| Follow a chat thread link with a cold channel directory | 66.535 [66.433, 66.743] | 33.383 [32.016, 33.433] | 33.152 |
| Open a topic with a known, uncached category | 66.400 [66.342, 66.498] | 33.269 [33.231, 33.313] | 33.131 |
| Reconcile a topic and retained feed after a plugin mutation | 66.360 [65.241, 68.780] | 33.233 [33.203, 33.240] | 33.127 |
| Open an embedded chat thread with an uncached channel | 66.331 [65.729, 67.184] | 33.214 [33.186, 33.240] | 33.117 |
| Join a macOS voice room with saved audio devices | 66.260 [66.225, 66.701] | 33.156 [33.152, 33.160] | 33.104 |

[Raw samples](benchmark_operation_latency_third.json)
