# Code block gutter metadata investigation

Status: repeated macOS profile captures confirm materially lower callback CPU
time for large blocks. No native frame improvement is claimed.

`_CodeBlockState.build` constructs one `_Line` per cooked code line inside a
`LayoutBuilder`. Each row previously evaluated `_gutterWidth`, which maps and
folds every line number. This performs N² metadata visits for both numbered and
plain blocks. A 20-line production widget reads its line list 440 times: 400
metadata visits, 20 clipboard reads and 20 row reads. The baseline regression
fails for both variants; see `code-block-gutter-evidence/baseline-tests.txt`.

The candidate computes the same getter once per LayoutBuilder invocation and
shares the nullable width between rows. There is no retained cache, changed
width formula, public API change, or renderer replacement. Each rebuild uses
current data; deferred highlighting and data replacement remain owned by the
existing state. Fullscreen continues to use its existing editor.

## Measurement protocol

The temporary instrumenter `tool/code_block_gutter_instrument.py` operates on
the original source. It adds one Stopwatch around the actual production
LayoutBuilder callback. Scan counts come from separate regression tests;
there is no per-getter counter in timed captures. The callback includes
metadata scanning and construction of row widget descriptions, but excludes
mounting/layout/paint and unchanged clipboard text construction. Both branches
use identical outer instrumentation.
`GUTTER_MODE=baseline|fixed` selects the branch in the same profile binary.
The instrumented source must be restored before committing.

`tool/code_block_gutter_profile_main.dart` parses cooked `lang-text` numbered
and plain fixtures (20, 100, 500, 1000 lines) before measurements. It mounts the
real CodeBlock then requests real element rebuilds: three warmups and twelve
retained iterations in each of four cycles. Syntax work is intentionally bypassed
to isolate this candidate, unlike the separate deferred-highlighting work.
Use a baseline/fixed/fixed/baseline process order. Preserve stdout and optional
GUTTER_OUTPUT frame-boundary records. `tool/code_block_gutter_summarize.py`
extracts callback microseconds.
These stopwatch intervals measure elapsed synchronous CPU work, not sampled CPU
profiler attribution or native frame improvements. Frame-boundary timestamps
include vsync waits and are not performance results.

Use the same installed Flutter 3.47.4 for both paths (repository pin remains
3.47.2), macOS profile mode, same hardware and foreground window. No SDK pin or
lockfile changes are part of this investigation. Native capture remains gated
by the parent's exclusive slot and the shared desktop lease. The harness waits
10 seconds to allow manual foregrounding, requires resumed lifecycle at capture
start and every fixture/iteration, exits on any foreground loss, and verifies an
attached CodeBlock RenderBox with positive dimensions. Semantics is enabled.
SDK, Dart, OS, DPR and viewport metadata are logged before capture.

## Validation

Baseline source: `552e9a729180e010054183edd0a5a306f3b565bc`.
All eight independent baseline complexity regressions fail with exactly
N² + 2N list reads. The once-per-callback implementation passes
all 44 focused code-block and syntax tests. Coverage includes mixed null and
negative numbers, light/dark data replacement, deferred token application
without geometry changes, and existing horizontal scroll/copy/fullscreen tests.
Targeted static analysis reports no issues. Raw outputs are retained in the
evidence directory. These results establish behavior and complexity, not timing.

## Matched profile results

Four separate processes ran the same profile binary in baseline/fixed/fixed/
baseline order on 2026-09-18. All completed with resumed lifecycle, mounted
positive block geometry and semantics enabled on every iteration. Flutter
3.47.4 / Dart 3.13.3, macOS 26.6.2 arm64, Skia/Metal, DPR 2, and a
3456 × 2098 physical (1728 × 1049 logical) viewport were identical. Fixtures
were parsed before loops. Each table value is a median of 48 retained callback
samples (12 per cycle after three warmups). Times are microseconds:

| Lines | Kind | Baseline A1 | Fixed B1 | Fixed B2 | Baseline A2 |
| ---: | --- | ---: | ---: | ---: | ---: |
| 20 | Plain | 3 | 1 | 1 | 3 |
| 20 | Numbered | 13 | 2 | 2 | 7 |
| 100 | Plain | 122.5 | 7 | 8 | 119 |
| 100 | Numbered | 106.5 | 3 | 4 | 115 |
| 500 | Plain | 879.5 | 12 | 12 | 858 |
| 500 | Numbered | 2289.5 | 15 | 15.5 | 2182.5 |
| 1000 | Plain | 3518 | 20.5 | 21 | 3353 |
| 1000 | Numbered | 11681 | 19 | 22 | 11692.5 |

At 1000 lines, the medians remove roughly 3.4 ms of plain-block callback work
and 11.7 ms of numbered-block callback work. The 20-line absolute differences
are only a few microseconds and subject to timer resolution and warmup noise;
they are not a meaningful user-visible speed claim. Number formatting and row
construction remain in their original implementation. The fix changes the
metadata visits from N² to N, for numbered and unnumbered blocks alike.

This is a narrow elapsed synchronous CPU interval in a real mounted production
widget. It does not measure overall post latency, layout, painting, raster cost,
fullscreen rendering, sampled CPU attribution, mobile devices, or native frame
improvement. The synthetic cooked fixtures represent common code-block shapes
and realistic sizes; they are not private-topic captures. The timed binary has
one extra shared branch per row to select baseline/fixed, which the shipped
source does not contain. No per-getter counters run inside the timed interval.

The first pilot completed its callbacks but failed writing an optional frame
record to `/tmp` under the application sandbox. It has been excluded entirely;
`rejected-output-path.txt` and `.err` retain the failure. The four accepted runs
omitted this optional output and completed normally. Each used the exact same
CUA selection of the running bundle followed by an observed container click
during the ten-second startup window. No focus or semantics guard was bypassed.

Raw accepted stdout/stderr are `a1`, `b1`, `b2`, `a2` in the evidence directory.
`summary.json` retains metadata, every callback sample and per-case summaries;
`profile-binary.sha256` identifies the shared binary and `sdk.json` records the
installed toolchain. The baseline/fixed tests and analysis output are also kept.

## Reproduction

In a disposable checkout containing the harness, restore only
`lib/src/shell/code_block.dart` from the baseline commit named above, then run
`python3 tool/code_block_gutter_instrument.py`. Build using:

```sh
flutter build macos --profile -t tool/code_block_gutter_profile_main.dart \
  --dart-define=PROFILE_FLUTTER_VERSION=3.47.4-9584c6713b
```

Launch that exact bundle with `GUTTER_MODE=baseline` or `fixed`, capturing stdout
and stderr through LaunchServices. Omit `GUTTER_OUTPUT` (the app sandbox denies
arbitrary `/tmp` file writes). Select the running bundle with CUA and click its
observed container within ten seconds. Keep it foreground until `GUTTER_DONE`;
discard any run emitting `GUTTER_INVALID` or an exception. Repeat ABBA, then run
`python3 tool/code_block_gutter_summarize.py a1.txt b1.txt b2.txt a2.txt`.
Restore the production file before committing; the generated instrumentation
is for the disposable capture checkout only.
