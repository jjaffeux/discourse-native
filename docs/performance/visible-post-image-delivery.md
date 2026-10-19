# Visible post-image delivery

On a deterministic shared-link scrolling workload, the last visible cohort waits 1,020 modeled milliseconds after it becomes visible, down from 4,600 ms. Five alternating baseline/candidate pairs produce identical results within each side. This is a 77.8% shorter encoded-byte wait and 59.0% fewer wire bytes in this workload. It measures useful image delivery through the production repository, not physical-device latency or internet throughput.

## Request ownership

`SiteImageRepository.request` returns one consumer handle with `result`, `setVisible(bool)` and idempotent `release()`. A per-account `ByteCache` transfer owns the consumer set. Any visible consumer gives queued work interactive priority. Releasing one handle settles only that consumer. The final release removes the transfer from sharing before canceling local admission, origin admission, pending headers or its body subscription. Reappearance creates fresh work and cannot join an abandoned transfer. Cancellation creates no failure record, negative cache entry, diagnostic or origin cooldown.

`load` keeps a completion-owned consumer for saves and deliberate prefetch. Shared consumers and these explicit loads keep work alive after a widget disappears. Credential opening, lifecycle retirement, redirect credential policy and the shared cross-account memory budget remain account-owned. Public avatar/emoji raw-request pooling retains completion-owned loads; the explicit cancellable API refuses pooled caches before starting work.

Both the cache-local queue and shared coordinator read current consumer priority. They retain FIFO order within priority and allow at most three interactive overtakes before eligible normal work gets a turn. Aggregate and per-origin transfer limits remain 16 and eight.

Cooked images, post lightbox thumbnails and grid images opt into demand checks on natural frames. They use the grid's existing ancestor-paint and nested-viewport rules. Visible demand is interactive, the one-viewport vertical margin is normal, and leaving that region releases unfinished demand. These checks do not request idle frames. Completed images retain their presentation and cache behavior.

Unknown-size progressive HTML images keep eager layout ownership. Their `HtmlBodyLoading` completion gates topic opening, saved-position restoration and keyboard paging, including while the reader is Offstage. Their dimension predicate is shared with the layout-loading decision. Composer and full lightbox images also keep eager delivery. A directly viewport-aware zero-size placeholder uses its point in the text flow so it can obtain dimensions.

## Workload and results

The baseline is main revision `9eeca8ff1e1f0b8f9a9c0a1a506619655168db26`, which already has bounded post-image admission and the shared memory budget. The measured candidate is `5cea2adfcb10fb2acc0fc0ad64a5e7698ee79f87`. Flutter 3.47.7 and Dart 3.13.5 run the repository and actual bounded response-body reader under `flutter test`.

A synthetic link grants exactly 512 KiB per modeled second in 10 ms ticks, with a fixed 20 ms header delay and 64 KiB responses. Host CPU cannot advance its clock. The script checks account headers, validates every successful payload byte and checksum, counts failures and cancellation separately, and reconciles wire bytes with successful bodies plus canceled partial bytes. Link capacity is the limiter. Both sides use production admission settings.

The scroll workload requests 16 images at 0, 250 and 500 ms. Each new cohort releases all earlier consumers. The first four in each cohort are visible and the other 12 are near the viewport. The final four visible images are useful. The baseline adapter calls completion-owned `load`; the candidate adapter owns releasable requests. The common workload file is byte-identical, and each typed adapter has a recorded hash.

All numbers below are medians of five alternating runs per side. Every minimum and maximum equals its median.

| Scroll measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Useful completion after becoming visible | 4,600 ms | 1,020 ms |
| Useful completion from workload start | 5,100 ms | 1,520 ms |
| Useful queue wait after becoming visible | 3,580 ms | 0 ms |
| Wire bytes | 3,145,728 | 1,289,750 |
| Wire bytes after consumer release | 1,976,565 | 0 |
| Canceled partial wire bytes | 0 | 241,174 |
| Peak unfinished body bytes | 519,045 | 519,045 |
| Peak obsolete unfinished body bytes | 519,045 | 0 |
| Peak active transfers | 8 | 8 |
| Completed consumers | 48 | 16 |
| Canceled consumers | 0 | 32 |
| Failed consumers | 0 | 0 |
| Useful cache revisits | 4 | 4 |
| Revisit wire bytes | 0 | 0 |

The 32 canceled consumers are intentional superseded work. Bytes sent before their release remain counted in candidate wire bytes. The candidate does not reduce the already-bounded overall partial-body peak.

The promotion workload requests 32 near-viewport images at once, then promotes images 24 through 27 at 250 ms while every other consumer remains interested. Useful completion after promotion changes from 3,830 to 1,790 ms, a 53.3% shorter wait. Queue wait after promotion changes from 2,810 to 770 ms. Both sides still complete all 32 responses at 4,080 ms, transmit 2,097,152 bytes, retain eight peak active transfers and have zero failures. This demonstrates priority without a faster aggregate link or cancellation of needed work.

## Validation and reproduction

Focused tests cover shared widgets plus explicit loads, both queues, promotion/demotion and fairness, abort-insensitive late headers, partial bodies, redirects, immediate reacquisition, account opening/retirement, pool ownership, cache revisits, nested viewports, retained widgets, Offstage and zero-size hydration. Production TopicView tests cover image delivery behind the opening skeleton and distant-image J/K paging. Temporarily removing layout ownership makes the opening regressions fail with one expected request versus zero actual requests. Baseline and candidate post-image render PNGs are byte-identical.

Run the candidate workload with:

```sh
POST_IMAGE_LEASES=1 POST_IMAGE_VISIBILITY_OUTPUT=/tmp/visible-images.json \
  flutter test --no-pub test/site_image_visibility_benchmark_test.dart
```

The complete paired runner, raw JSON, per-transfer records, 10 ms timelines, checksums, exact source hashes, typed adapter hashes and verification logs are in `/private/tmp/discourse-native-perf-wave2-01a15463/visible-post-images/`. `measure.py` alternates five runs of each frozen revision. `summary.json` contains medians and ranges. `render-parity.json` records rendered equivalence.

These are modeled encoded-delivery results and Flutter test rendering. They exclude physical-device timing, image decoding speed, real-server behavior, internet throughput and total process memory. Partial-body counts describe modeled unfinished bodies rather than measured heap residency. Real transports can continue sending bytes already in flight after cancellation. No native-device performance improvement is claimed.
