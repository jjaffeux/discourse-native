# HTML text-boundary conversion investigation

**Status: unmerged candidate, blocked on native validation.** The Mac was found
locked before the boundary-scan candidate's native comparison. The parent audit
paused native captures and requested an unlock. No unlock was attempted, no
boundary-candidate native result is claimed, and this change must not be merged
on the debug timings below alone.

This follows [first-render profiling](long-post-first-render.md), the
[default-style cache](html-default-style-cache.md), and
[rich-chat scrolling](rich-chat-scrolling.md). Those optimizations are retained.

## Production-path evidence

Temporary probes in the vendored renderer measure actual `CookedHtml`
conversion, custom widget dispatch, style setup, text normalization and
flattening. Conversion remains synchronous on the UI isolate. Phase totals
include nested quote bodies mounted during cold rendering; the first conversion
span is the root body's synchronous pause. The collector snapshots these totals
before scrolling, so later sliver children do not contaminate cold totals.

The existing profile harness now supports two deterministic offline workloads:

- Plain: 450 paragraphs, 76,840 HTML characters.
- Varied: 68,149 HTML characters, 90 technical-discussion sections with varying
  subjects/IDs, headings, links, emphasis, nested lists, quotes, code blocks,
  inline CSS containers, breaks, rules and multilingual/non-breaking-space text.
  Full column/progressive mounting converts 1,065 text nodes, including 15 nested
  quote bodies. This is generated realistic markup, not captured private content.

A first experiment excluded ordinary single spaces from internal regex matches.
It removed 6,567 discarded matches in the varied workload, but native gains were
small relative to the remaining cost. That experiment is **not** in the proposed
production change. A later non-Unicode-regex experiment barely changed the
trailing-boundary phase in debug and was also discarded.

Exploratory same-binary regex-only measurements used Flutter 3.47.4 / Dart 3.13.3,
macOS 26.6.2, Apple M4 Pro, profile mode, a configured 1280 × 860 viewport and
680-logical-pixel content width. The repository's 3.47.2 pin was unchanged.
Eight launches alternated baseline/fixed/baseline/fixed for each workload; each
launch completed four cycles of column, sliver and progressive rendering.
Cycle zero is retained as warmup and excluded from these nine-sample medians.
Both pairs produced identical conversion-operation counts for every mode/cycle.

Milliseconds, exploratory **rejected regex-only variant**:

| Workload / phase | Baseline 1 | Regex 1 | Baseline 2 | Regex 2 |
| --- | ---: | ---: | ---: | ---: |
| Varied root conversion | 21.501 | 21.219 | 21.334 | 20.695 |
| Varied normalization | 8.417 | 8.106 | 8.503 | 7.972 |
| Plain root conversion | 18.915 | 17.805 | 19.357 | 16.794 |
| Plain normalization | 12.250 | 11.587 | 12.308 | 11.033 |

These captures ran in a coordinated CPU-quiet window, but the initial collector
had no lifecycle/foreground gate or native-semantics marker. The Mac was later
found locked. Treat them as exploratory synchronous CPU spans, not acceptance
of a rendering or scrolling improvement. No frame-rate claim is made.

## Proposed bounded change

Subprobes identify avoidable boundary work: the trailing-whitespace regex searches
ordinary prose in full even when its final character is not whitespace. The
candidate scans only the leading/trailing edges with the exact HTML ASCII set:
TAB, LF, FF, CR and SPACE. It stops at the first non-whitespace code unit at each
edge. An all-whitespace node is scanned once, and empty input retains its prior
empty whitespace bit. NBSP, Unicode spaces, vertical tab and surrogate code units
are not trimmed.

This removes two boundary-regex invocations per text node: 2,130 for the fully
mounted varied fixture, or 900 for the plain fixture. Internal regex matching,
text/whitespace bit construction, CSS, plugin traversal, selection/quoting,
disposal, edits, mounting and progressive geometry are unchanged.

The debug production-path subprobe attributed about 2.2 ms to trailing-boundary
matching in warmed varied-fixture iterations. Direct edge scanning reduced that
subphase to approximately 0.08–0.22 ms. Debug/JIT timings include probe overhead
and concurrent-machine uncertainty; they establish a candidate to measure, not
a native conversion speedup. All captured phase samples and explicit warmup
markers are retained in [the measurements](html-text-boundaries.json), separately
from the rejected regex variant. Native boundary-candidate results are absent.

## Reproduction

Uninstrumented production harness:

```sh
LONG_POST_VARIETY=true LONG_POST_EXIT=true flutter run --profile -d macos \
  -t tool/long_post_render_profile_main.dart
```

Omit `LONG_POST_VARIETY` for the original plain fixture. The harness also records
semantics state, physical viewport and DPR. Do not interpret its ancillary frame
arrays as proof of smoother scrolling.

For the exact remaining comparison, apply
[the optional probe patch](html-text-boundary-probe.patch) in an isolated checkout.
It reinstates the legacy boundary regex behind `LONG_POST_OPTIMIZED=false` and
selects direct boundary scanning with `LONG_POST_OPTIMIZED=true`. Both paths use
one native binary and the same surrounding algorithm. Count probes are disabled
in native timing runs. Run both workloads in alternating pairs, exclude cycle
zero, verify identical operation counts/text/geometry, and compare the root
conversion span separately from boundary/normalization totals. Restore the
unpatched source afterward; no probe or runtime bypass belongs in shipping code.

Native captures and main integration must be serialized through the parent audit
and the desktop/main leases. Do not launch while the Mac remains locked. A ready
instrumented bundle was retained locally as
`/tmp/html-conversion-boundary-0694.app`; it is not a repository artifact.

## Verification so far

- Independent character-scanner oracle over 1,000 deterministic random strings,
  with ASCII whitespace, Unicode spaces, line separators and unpaired surrogates;
  explicit empty/all-space, RTL, NBSP, 4,096-space runs and 2,000-word prose cases.
- Temporary differential tests compared the exact legacy and candidate build-bit
  streams for that corpus. Actual `CookedHtml` produced identical text and
  rectangles for adjacent inline nodes, `pre`, `nowrap`, Arabic/Hebrew and NBSP.
- 125 focused application tests passed with seed `391616`, including cooked
  markup, plugin/theme updates, details/tables/quotes, selection and formatted
  quote behavior, progressive geometry, disposal and edits.
- All 11 vendored-package tests passed. Root static analysis and analysis of the
  changed vendor files passed. Full vendor analysis reports two pre-existing
  diagnostics in unchanged `default_styles_rendering_test.dart` (nullable access
  and control-body formatting); no unrelated repair is included.
- Formatting, `git diff --check`, optional patch applicability, all three archive
  provenance contracts and the final probe-free macOS profile build passed.

No fresh native accessibility or visual check was performed. Native
before/after evidence for this boundary candidate, final acceptance and a
serialized main merge remain outstanding.
