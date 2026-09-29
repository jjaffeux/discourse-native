# Desktop topic prefetch

Topic lists combine three intent signals through one coordinator:

- Native `DItem` hover waits 40 ms.
- Keyboard topic selection waits 40 ms, replacing the previous selection.
- A cursor approaching exactly one visible row can start immediately after
  the prediction agrees on two successive sampled frames.

The predictor samples at most once per frame. It uses up to eight positions
from the last 120 ms to extrapolate 80 ms forward. Pauses and reversals reset
history. Paths crossing multiple rows and paths starting inside a row use the
ordinary hover fallback. Visible bounds are clipped to the list viewport;
normal hit testing rejects covered targets. No hit areas are expanded.

Scrolling suspends pointer speculation, clears its history, and releases its
request. Fresh pointer movement after scrolling can resume ordinary hover.
Keyboard selection survives its own programmatic reveal scroll. Leaving
keyboard focus releases keyboard interest. A predicted approach expires after
120 ms without confirmation or hover. Hidden/deactivated lists disconnect
pointer observation, and touch platforms do not use these signals.

The coordinator transfers the same request from prediction to hover and then
navigation. The existing request controller still permits one request at a
time, aborts displaced work, retains one completed result for 15 seconds, and
keys reuse by site, account session, topic, and unread post position. No topic
content is published or marked read until real navigation consumes it.

## Measuring the tradeoff

Run a desktop profile with both `--dart-define=TRACE_TOPIC_PREFETCH=true` and
`--dart-define=TRACE_SURFACE_OPENING=true`, then record the DevTools timeline.
The prefetch trace contains no site URLs, topic IDs, or content. Each request
has a process-local numeric ID and its original intent (`hover`, `keyboard`,
or `trajectory`):

- `topicPrefetch.started`: speculative dispatch, including credential lookup.
- `topicPrefetch.ready`: a successful response; `elapsedMs` is preparation time.
- `topicPrefetch.adopted`: navigation takes ownership; `elapsedMs` is lead time
  since dispatch, and `completed` distinguishes ready versus running reuse.
- `topicPrefetch.cancelled`: interest ended before completion, including a
  window/account retirement after adoption.
- `topicPrefetch.unused`: a completed response was discarded without adoption.
  Retained responses emit this only when evicted, validated stale, or cleared.
- `topicPrefetch.failed`: the loader failed without an explicit interest release.

Group events by request ID to avoid counting adoption plus readiness twice.
Adoption can still end in failure or cancellation; `opening.topic.prefetchUsed`
marks actual reuse in navigation. Compare `opening.topic.request` to
`opening.topic.publish` for click-to-published-content latency (and existing
frame traces for rendering), alongside unused and cancelled request counts.
The 80 ms horizon is a conservative starting point, not a measured speedup.

The prediction approach was informed by [ForesightJS's mouse predictor](https://github.com/spaansba/ForesightJS/blob/b03622cd36cdad6363720f51d1381c3d2868fd7f/packages/js.foresight/src/predictors/MousePredictor.ts).
Unlike its all-intersections dispatch, the topic-list predictor requires a
single unambiguous candidate and keeps the existing request budget.
