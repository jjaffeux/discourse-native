# Forum switching

Forum selection already restores cached feeds and topic routes without waiting
for a network response. The measured controller dispatch is sub-millisecond.
The repeatable unnecessary work was reconstructing both complete Flutter themes
on every switch, including Material seed colors and control styles.

The app now retains up to 32 themes in its existing bounded LRU cache, keyed by
the complete immutable palette, requested brightness, and target platform.
Returning to a forum reuses its theme. Equal palettes can share it; changed
palettes, radii, brightness, and platform defaults resolve separately. Neutral
fallback themes are also cached. The cache belongs to the app state and does
not retain credentials, forum content, or widget trees. This preserves existing
account boundaries, feed refresh rules, and reading-position restoration.

## Instrumentation

Enable the content-free timeline markers in the ordinary app:

```sh
flutter run --profile -d macos --dart-define=TRACE_SURFACE_OPENING=true
```

The existing `SurfaceOpeningTrace` emits these `opening.forum.*` events:

| Event | Meaning |
| --- | --- |
| `select` | Entry to forum selection |
| `workspaceRestored` | Synchronous workspace activation finished |
| `notified` | Selection observers have been notified |
| `theme.start`, `theme.end` | Resolving both app themes |
| `frame` | The selected forum's first layout/paint pass finished |

`frame` is a post-frame milestone, not raster completion or a guarantee that an
uncached feed has arrived. Rapidly superseded selections and disposed owners
cannot emit it. Raster timings are recorded separately. The markers carry no
site URLs, titles, account details, or credentials and are inactive by default.

For a repeatable capture using the production `DiscourseApp`:

```sh
FORUM_SWITCH_LABEL=capture \
  flutter run --profile -d macos -t tool/forum_switch_profile_main.dart
```

The fixture mounts two synthetic connected forums with distinct light/dark
palettes, 60 topics, 12 categories, and 20 rich replies in each of two topics.
Feed requests have an 80 ms artificial delay. Credentials, drafts, and forum
tabs are fake, preferences have an isolated prefix, and no real forum is used.
It captures the first visit to the second forum, eight cached list switches,
and eight switches between restored topics. Every capture records shell
notifications, feed request count, individual UI/raster timings, frame-budget
counts, and milestones. The report path is printed in the app's temporary
directory. Semantics stay enabled during capture; timing batches are allowed
to arrive and filtered by their vsync timestamps. Empty captures fail.

Keep the app visible. It waits 15 seconds before starting by default.
`FORUM_SWITCH_MANUAL_START=true` waits instead for the signal file printed in
the log. Activate/inspect the window before creating it; avoid UI inspection,
builds, and tests during the timing window. `FORUM_SWITCH_PASSES` accepts 1–30.
`FORUM_SWITCH_CPU=true` includes bounded CPU summaries collected after each
window. For direct executable launches, enable sampling with
`FLUTTER_ENGINE_SWITCHES=1` and
`FLUTTER_ENGINE_SWITCH_1=enable-dart-profiling=true`; Flutter's profile launcher
already enables it. CPU-disabled runs are used for the timing comparison.

## Verification

The comparison uses macOS arm64, Flutter 3.47.4 / Dart 3.13.3, profile mode,
Skia on Metal, a 120 Hz display, DPR 2, and a 1280 × 860 logical viewport.
The repository's Flutter 3.47.2 pin and dependency locks are unchanged.
All captures use the manual gate, enabled semantics, and the fixture's dark
palette selected by the host's system appearance. The standalone bundles were
ad-hoc signed with the existing review entitlements, retaining the app sandbox.
Baseline is `d99611ce` with the same instrumentation and fixture added.

The raw reports and source fingerprints are in
[forum-switching.json](forum-switching.json). The first pair used an equivalent
inline LRU implementation; the final pair uses the existing `BoundedLruCache`.
Both pairs are retained to show run-to-run variation. The separate baseline CPU
capture is diagnostic only: it shows widget mounting, text layout, semantics,
and allocations spread across the destination frame, without another dominant
application hotspot. First-visit raster outliers are retained, too.

Each number below is the median across eight cached switches, in milliseconds.
Peak UI includes build, layout, paint, and semantics for the worst frame of
each switch; theme time is the interval between the two theme milestones.

| Measurement | Baseline 1 | Cache 1 | Baseline 2 | Final 2 |
| --- | ---: | ---: | ---: | ---: |
| List theme resolution | 0.951 | 0.024 | 1.538 | 0.018 |
| Topic theme resolution | 0.908 | 0.042 | 0.712 | 0.018 |
| List peak UI frame | 11.69 | 12.19 | 17.29 | 8.14 |
| Topic peak UI frame | 19.71 | 22.28 | 18.35 | 17.67 |

Repeated theme work is consistently removed. Whole-frame results vary across
processes, so these measurements do not establish a reliable overall switching
speedup percentage. Some destination frames still exceed the 8.33 ms display
budget. Warm switches made zero feed requests in every measured run. The
remaining cost is predominantly destination rendering, not waiting for a feed.
Real-network first visits and device platforms other than macOS were not
profiled.

The theme identity regression fails on baseline and passes after caching.
Focused tests cover immediate palette changes, equal palettes, live appearance
refresh, dark/light/neutral themes, account disconnection, rapid switch trace
ownership, tab restoration, and startup request budgets. Root and full-profile
static analysis pass, as does the macOS profile build.
The final fixture was also checked through native rail clicks: both forums
restored their own topics in dark mode, then again after switching to Light in
Settings. The synthetic palette's appearance is not a visual design baseline.

The broader `forum_tabs_integration_test.dart` currently has 27 failures from
expecting a visible `InstanceSidebar` at narrow desktop widths, where
`DesktopNavigation` keeps it offstage. The first failing case was reproduced
with the unchanged baseline app source. That unrelated fixture issue is not
changed here; the focused controller tab tests pass.
