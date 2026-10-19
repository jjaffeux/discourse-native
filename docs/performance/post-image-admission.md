# Post image admission

`SiteImageRepository` owns one admission coordinator shared by its account caches. It allows 16 active transfers in total and eight per origin. Each account cache admits eight loads into its download path. Its remaining work waits before the existing download timeout starts. Requests for the same URL still share work only inside the same account cache.

Account caches retain their credentials, lifecycle leases, redirect rules, and memory limits. The coordinator owns slots and origin cooldowns, not response bytes. Account retirement aborts that account's work without closing other account caches. Repository disposal closes every cache before closing their coordinator. Public avatars and emoji retain their existing pipeline admission and pooling.

## Measurement

The benchmark drives the real repository and response-body reader through a deterministic shared-link client. Each encoded response is 64 KiB. The link grants about 512 KiB per modeled second in 10 ms steps. The gallery requests 32 images together. The scroll case requests three batches of 16 at 0, 250, and 500 modeled milliseconds. The first four gallery images and the first four images in the final scroll batch represent useful images.

These measurements describe encoded byte delivery and partial response buffers. The obsolete payload count includes entire responses from the first two superseded scroll batches, including bytes sent before they became obsolete. Delivered payload bytes are cumulative bytes returned to consumers, not sampled cache retention. They do not measure image decoding, rendering, physical-device latency, total process memory, or actual internet throughput. The byte payloads are synthetic. Host CPU activity cannot advance the modeled link clock. Every load must return the entire expected payload, and the total transmitted bytes must match the workload.

Five alternating runs per side produced identical modeled results within each side. The table gives their medians; each minimum and maximum equals its median.

| Measurement | Gallery baseline | Gallery candidate | Scroll baseline | Scroll candidate |
| --- | ---: | ---: | ---: | ---: |
| Useful encoded bytes ready | 4,030 ms | 1,010 ms | 6,020 ms | 5,050 ms |
| All encoded bytes ready | 4,030 ms | 4,040 ms | 6,020 ms | 6,060 ms |
| Peak active transfers | 32 | 8 | 48 | 8 |
| Peak partial body bytes | 2,096,832 | 524,000 | 2,803,952 | 524,000 |
| Delivered payload bytes | 2,097,152 | 2,097,152 | 3,145,728 | 3,145,728 |
| Obsolete scroll payload bytes | 0 | 0 | 2,097,152 | 2,097,152 |
| Wire bytes | 2,097,152 | 2,097,152 | 3,145,728 | 3,145,728 |
| Completed loads | 32 | 32 | 48 | 48 |
| Failed loads | 0 | 0 | 0 | 0 |

The candidate bounds active work and incomplete encoded bodies while delivering the selected cohort sooner. Aggregate completion is slightly later in the model's 10 ms steps. No aggregate download speedup or reduction in obsolete payload was measured. Retained cache budgets remain unchanged.

The focused batch passed 116 tests across the repository, image widget, public media boundary, and ByteCache files. Coverage includes full-body caps, aggregate and shared CDN limits, a 96-image backlog, a 24-second fake-time queue with eight-second active downloads, retirement, redirect credentials, redirected cooldowns, account isolation, natural dimensions, display decoding, SVG, and GIF behavior.

## Limits

FIFO admission does not establish viewport visibility or cancel obsolete images during ordinary scrolling. `SiteImage` currently ignores late delivery after disposal, while multiple consumers can await one shared request. A cancellation API would need consumer ownership. Visible priority would need a visibility signal and queued promotion. This change adds neither signal.

Waiting for the shared coordinator still counts against a download's timeout when several account caches contend. The cache-local queue keeps ordinary single-account backlog outside that timeout and avoids overflowing the coordinator's 64-waiter origin queue for large single-account galleries. Extreme contention across many account caches can still hit the bounded coordinator backlog.

## Reproduction

Run `POST_IMAGE_BENCHMARK_OUTPUT=/tmp/post-images.json flutter test --no-pub test/site_image_admission_benchmark_test.dart` for the current implementation. The JSON includes useful-byte completion, all-byte completion, peak transfers, partial body bytes, delivered payload bytes, obsolete scroll payload, wire bytes, completion counts, and failures.

The paired run alternates the baseline repository file from `080f5c2ea78976164cd98d5d7ac90a45e2f05efe` with the candidate repository file. It runs five times per side with one unchanged benchmark. The baseline repository file is replaced only within the isolated worktree during the serialized measurement batch, then the candidate is restored. Raw outputs and the batch script are in `/private/tmp/discourse-native-perf-20261019-01a153f7/post-images/`.
