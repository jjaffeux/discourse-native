# Reusing recent rich chat rows

Follow-up to [the CSS investigation](rich-chat-scrolling.md), using the same
offline 1,000-message fixture with images, reactions, oneboxes, quotes and code.

## Diagnosis

Detailed widget-build/layout tracing found 18.84 ms under `_Reactions` within
39.99 ms spent mounting 17 `ChatMessageTile` trees: about 47% of row mounting in
that instrumented pass. This is an inclusive subtree measurement, not 47% of
frame time. Text layout and rich HTML construction remain substantial costs.
The old `cacheExtent: 0` list also destroyed every row immediately after it left
the viewport, repeating those costs on direction reversals.

The opt-in `SCROLL_TRACE_PHASE=fast SCROLL_FAST_STEPS=6` harness enables Flutter
widget and layout timeline spans and writes a VM timeline JSON. Its overhead is
substantial; normal frame comparisons leave it disabled.

## Changes

- Retain the last 24 mounted message trees for local reversals. No unseen rows
  are built ahead. A step larger than one viewport releases the previous window
  to avoid carrying rich trees through long jumps. Additional visible rows and
  a brief eviction transition can exceed the retained-row limit.
- Keep live record subscriptions and existing message identity. Offscreen
  controls are excluded from keyboard focus traversal; cached rows can rebuild
  before receiving layout. Hover previews still dismiss when scrolling away.
- Migrate reaction pills to Native `DToggle`/`DHoverCard` and their picker action
  to `DButton`. The approved long-press and read-only additions preserve reactor
  inspection, including reactions the viewer cannot change. Native desktop and
  touch sizes replace the previous fixed-size controls.
- Avoid allocating unused hover-card/tooltip animations during disposal, and
  avoid spare owned focus/controller allocations when resources are borrowed.
- Fix Toggle hover under the app's keyboard-focus policy and preserve the
  documented muted fill for selected/hovered outline toggles.

The Native migration alone did not establish a frame-time win. It changes row
geometry, so comparing old/new controls with equal pixel jumps also changes the
message workload. Retention measurements instead use one identical binary with
only retention switched off/on.

## Reproducing the comparison

Apply [the temporary probe](rich-chat-retention-probe.patch) in an isolated
checkout and build `tool/chat_scroll_profile_main.dart` in macOS profile mode.
Run that same binary with `SCROLL_RETAIN=false` and `SCROLL_RETAIN=true`.
The probe is absent from production source. `SCROLL_RICH=true SCROLL_LOCAL=true`
uses offsets 0 → 14,400 → 7,200 → 14,400 (360/180/180 steps of 40 pixels).
Without `SCROLL_LOCAL`, the original long-jump workload is unchanged.

Captures use Flutter 3.47.4 / Dart 3.13.3, an Apple M4 Pro, macOS 26.6.2,
Skia/Metal and a 120 Hz display. The repository pin stays at 3.47.2. Native
accessibility and VM CPU sampling are enabled identically as described in the
earlier investigation. Bring the isolated app to the foreground before its
start delay expires; background captures are invalid.

## Final measurements

The final adaptive binary preserves the local reversal benefit. UI frame build
p95 in milliseconds (retention off/on):

| Phase | Off | On |
| --- | ---: | ---: |
| Steady | 2.049 | 2.338 |
| Revisit | 1.887 | 0.758 |
| Reread | 1.828 | 0.786 |

Revisit/reread p95 falls by 60%/57%. Each pass constructs one day separator
instead of 18 rows. Both versions mount 39 rows on the steady pass. Total UI
work is less consistent: revisit falls from 87.9 to 71.1 ms, while reread rises
from 77.8 to 81.1 ms. This supports reduced reconstruction spikes, not a blanket
frame-time speedup. No local revisit/reread UI or raster frame exceeds 8.33 ms.

Long-jump UI p95, with the second pair run in reverse order:

| Phase | Off 1 | On 1 | Off 2 | On 2 |
| --- | ---: | ---: | ---: | ---: |
| Fast | 8.111 | 9.246 | 9.432 | 7.957 |
| Return | 7.814 | 8.055 | 8.589 | 7.960 |

Long-distance p95 is mixed. Aggregate UI work falls from 499.8/442.4 to
480.1/424.4 ms in pair 1, and from 489.9/451.2 to 445.2/440.6 ms in pair 2.
Both versions build the same 223/210 rows, and finish with only 1/2 mounted
messages rather than carrying a 24-row cache. The sustained penalty from the
unconditional cache is gone; no consistent long-distance p95 win is claimed.

Compact captures, frame distributions, CPU summaries, fixture offsets and
memory snapshots are in [rich-chat-row-reuse.json](rich-chat-row-reuse.json).

## Tradeoffs and discarded experiments

The initial unconditional 24-row cache reduced local-revisit UI p95 by 67–70%
in two complete pairs, but worsened long-jump p95 and increased GC samples.
That version was rejected; the final cache releases the old window on jumps.
One intervening baseline capture started in the background and recorded zero
steady frames; it is excluded from paired results.

One after-GC snapshot after the local workload measured 31.1 MB of Dart heap
without retention and 53.2 MB with 24 retained rich rows (about 21 MiB extra).
Process RSS was about 50 MiB higher. These are single snapshots of the initial
cache, not a general memory benchmark. The final local retention limit is the
same, while long jumps discard that window. Flutter's decoded-image cache was
identical in the local pair: 19,588,224 bytes, with zero pending images.

Cold-image raster stalls remain intermittent. This change does not establish
their cause or claim to eliminate them. Physical mobile performance and live
network behavior have not been measured.

## Verification

The retention regression checks element reuse across reversals, bounded
eviction, live reaction updates, hover dismissal, disposal and clearing the
window on long jumps. Disabling retention fails its retained-element assertion.
The existing scroll tests still enforce zero held-message rebuilds during
steady scrolling and bounded construction during jumps. Chat lifecycle tests
cover channel/site changes, paging, selection, keyboard navigation and edits.

Toggle tests exercise pointer and semantic long press, read-only pointer and
keyboard activation, disabled behavior, both constructors, and hover under the
app's `DFocusHighlight`. Reaction tests cover async writes, native target sizes,
selection semantics, reactor inspection and picker behavior. Existing tests
with obsolete Material-control expectations were updated to Native controls.

The native pass covered light channels and a 360-pixel dark DM: rich content,
reaction 12 → 11, scrolling and jump-to-latest preserving that updated value.
No native runtime/AX-tree errors were logged. Touch behavior is widget-tested;
this is not a physical mobile or spoken VoiceOver verification.

One unrelated existing navigation test, “opens a new direct message with
Command+K and shows the shortcut,” fails on untouched main `8a0ac354` because
its expected sidebar tooltip is absent. It is excluded by name from the final
focused run; the rest of that navigation file remains included.

All 554 remaining focused tests pass, including chat lifecycle/navigation,
threads, uploads, rich scrolling, reactions, Toggle/Toggle Group, Hover Card,
Tooltip and Voice consumers. Root and full-profile static analysis are clean;
formatting, the profile build, `git diff --check` and applying the temporary
probe patch all pass. The native hook and probe switch are absent from shipping
source. The JSON includes the tested AOT binary and source hashes.

Integration from main `8a0ac354` was conflict-free. All 82 combined chat
scrolling/lifecycle and diagnostics-capture tests pass, and root static
analysis remains clean. The final merge is performed from the main checkout.
