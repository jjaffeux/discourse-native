# Reusing default CSS during HTML conversion

The [first-render investigation](long-post-first-render.md) found that converting
a parsed HTML body into widget descriptions still blocks the UI isolate.
Profiling the remaining work identified repeated parsing of identical default
CSS as a material cost. For 450 plain paragraphs, the renderer parsed the same
`display: block; margin: 1em 0` defaults 450 times. Custom element builders took
only a fraction of a millisecond in that fixture, so their dispatch was left
unchanged.

## Change

The renderer now shares a cache among one body's build trees. Identical default
CSS is parsed once and copied for subsequent elements. Default-style callbacks
still run for every element, and the key includes their complete ordered output,
so attribute-dependent and plugin-provided defaults retain their behavior.

Every element receives independent declarations, expression lists, identifiers
and Dart-style metadata. The cache accepts only simple literals whose complete
state can be copied faithfully; complex expressions retain the original parser
path. It admits at most 64 strings of at most 4,096 characters each and is owned
by that body's trees. It does not cache widgets or UI contexts across posts.

This is a two-source-file patch to the published HTML package, retained as a
local dependency in both application graphs. The [patch manifest](../../packages/flutter_widget_from_html_core/PATCHES.md)
pins the archive checksum and lists all six local files, including tests and
provenance metadata. The package API, HTML traversal and staged mounting are
unchanged. Remove the fork when an upstream version supplies equivalent reuse
and mutation isolation.

## Measurements

Two baseline/cache process pairs used the existing native profile fixture:
Flutter 3.47.2 on macOS, 450 paragraphs, 76,840 HTML characters, and a 680-logical-
pixel content width. Each process ran four cycles of column, sliver and
progressive rendering. Temporary probes measured the same regions in both
builds; baseline bypassed the cache. Probes and the bypass switch were removed
from the final source.

Medians of 12 samples per process, milliseconds:

| Phase | Baseline 1 | Cached 1 | Baseline 2 | Cached 2 |
| --- | ---: | ---: | ---: | ---: |
| Default CSS parsing / cache lookup and copies | 4.616 | 0.428 | 2.365 | 0.358 |
| Custom widget builders | 0.278 | 0.304 | 0.145 | 0.227 |
| Entire HTML conversion | 21.216 | 18.298 | 11.609 | 17.450 |

The targeted phase fell about **85–91%**. The default-style probe excludes
callback execution and map serialization, which remain unchanged. There are
still 450 default-style requests; repeated matching requests reuse the parse.

Other conversion timings varied substantially between processes. The second
pair did not improve overall, so these samples do not establish a precise
whole-conversion speedup or a scrolling frame-rate improvement. They show the
specific repeated work removed. All samples are in [the measurements](html-default-style-cache.json).

The final build without probes completed all 12 native rendering and scrolling
cycles. The Mac was locked at the final CUA inspection, so no fresh manual visual
check is claimed and those final timings are excluded from comparisons.

## Verification

516 focused tests passed with seed `391614`, covering the new cache and nested
renderer integration, cooked markup, plugin defaults, theme/body updates,
selection and quoting, topic scrolling, retention, reading and keyboard
navigation. The six cache regressions also pass independently in the vendored
package; a root test wrapper includes them in the application's normal CI run.

Root, compatibility-profile and vendored-package analysis passed. Formatting,
the macOS profile build, and all three vendor archive provenance checks passed.
The Flutter pin and unrelated dependencies are unchanged; both application
lockfiles now resolve the reviewed local HTML package.

Reproduce the uninstrumented conversion measurement:

```sh
flutter run --profile -d macos -t tool/long_post_render_profile_main.dart
```

HTML conversion remains synchronous. Tables, large single blocks, complex CSS
and custom/plugin rendering can still pause the UI. This change removes repeated
default-style parsing; incremental conversion is a separate future step.

## Final integration

Integration with main `dd11940d` passed 528 focused tests with seed `391615`,
including chat quoting and alert tables, and clean static analysis and archive
provenance checks. A lifecycle fixture also failed on unchanged main because a
post-action layout change left the next post outside its assumed initial
viewport. The fixture now explicitly exposes only the start of the tall final
post and verifies that it remains unread until scrolled to its end. No reading
or scrolling production behavior was changed for that repair.
