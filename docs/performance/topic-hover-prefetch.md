# Topic hover prefetch

Desktop forum topic rows start fetching after 40 ms of pointer dwell. Touch
platforms do not prefetch. The request targets the same unread post position
as row activation. Topics already held at that position, currently loading,
or already open do not generate speculative requests.

`TopicPrefetchController` retains one active request and one replaceable
pending hover target. A new hover cancels the previous speculative request;
the replacement starts only after both its dwell and the previous operation's
settlement. Cancellation propagates through credential lookup, the topic API,
the origin queue, HTTP headers, and response-body streaming. Cancellation can
stop the client but cannot guarantee that the server stops database work
already underway. There is no additional rate throttle beyond the dwell and
single speculative slot; ordinary per-origin limits and 429 cooldowns apply.

A completed result is retained for at most 15 seconds for reuse, with only the
latest hovered topic retained. The key includes site, account session, topic,
and requested post position. Hover does not publish posts into the visible
store, send read receipts, or run navigation/presentation side effects.

Navigation adopts an in-flight or completed result, so pointer exit cannot
cancel a topic the user opened. An earlier click bypasses the dwell and sends
a normal request. Failed prefetches are silent and normal loading retries on
click. Forced/stale loads discard speculation. Bookmark/archive versions from
prefetch dispatch preserve concurrent writes when navigation publishes data.
Leaving the list, changing context/account, and backgrounding cancel
speculation. Backgrounding alone does not cancel an adopted navigation load.

The Native `DItem.onHoverChanged` callback owns pointer entry/exit. Its caller
releases work when the row is deactivated or its destination changes. The
Item styleguide has a runnable callback example. No control geometry, paint,
keyboard activation, or touch interaction changed.

Desktop reader-tab activation already hydrates its destination. `_openTopic`
now avoids scheduling a second ordinary load, which previously queued a
redundant refresh for numbered destinations, including prefetched ones.

## Verification (2026-09-24)

- `flutter analyze --no-pub`: clean.
- 26 prefetch controller, topic-list interaction, and transport tests passed.
  Coverage includes the exact dwell, replacement while cancellation settles,
  completed/running click handoff, desktop reader tabs, early clicks, unread
  positions, forced loads, slow credential cancellation, account isolation,
  expiry, failures, backgrounding, row removal, touch platforms, cancellation
  before headers/during a body, and removal from a full origin backlog.
- Native Item callback tests and existing transport/coordinator tests passed
  (98 tests in the initial combined transport/component run).
- The broader focused run passed 366 tests with one pre-existing desktop
  full-screen-composer failure. Row/semantics/scroll coverage passed 61 tests
  with one pre-existing mobile author-label expectation failure.
- Broader topic-reading/styleguide suites passed 105 tests and had 37 existing
  failures. All failures were reproduced on an isolated checkout of baseline
  `2f1974bbe`; baseline had 38 failures in those two suites. This change also
  fixes the existing unread-row duplicate-request failure. No baseline
  assertions or goldens were changed to hide failures.

Native inspection used `tool/topic_hover_prefetch_review_main.dart`, an offline
macOS app with a 600 ms simulated request and an on-screen request log. Checked
light and dark palettes, full and narrower windows, the Item callback example,
hover starts, and a completed hover opening without a second request. The
preview used an isolated ad-hoc signed bundle without push/team/application
identity entitlements. Cancellation timing and in-flight handoff were verified
by deterministic tests; no real-forum latency or server-load benchmark was run.
