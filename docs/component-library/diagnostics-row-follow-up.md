# Diagnostics rows at larger text

The actual DiagnosticsPanel export used during Scroll Area review exposed a pre-existing fixed 70px row height: its two metadata columns overflowed by 14px at 200% text. The coordinator owns this fix independently of Scroll Area’s scrollbar migration.

Rows now use intrinsic content with a 70px minimum. The method column grows with its text scale so short GET/POST labels stay on one line. The normal compact rows, lazy list, event ordering, selection and detail callbacks remain intact.

Executable source: `a872962fe3b02c7bd7d596fcb517707d36c13619` on `codex/component-fidelity-follow-up`. The change is native-verified and awaits the coordinator branch merge.

## Verified

- Reproduced the original layout exception in a narrow populated panel before the fix.
- 31 Diagnostics panel/acceptance tests and 1 font-loaded render test pass, seed909515. The regression checks normal and200% row heights, method/status/duration readability and detail navigation. Root/full-profile analysis are clean.
- The actual production panel renders at 360×1000 logical pixels, 100%/200% text, 2× output with SFNS and MaterialIcons loaded. Images and hashes are in `/Users/joffreyjaffeux/.codex/visualizations/2026/09/08/01a0816f-d4e0-7f93-9d6b-baeaf6961181/diagnostics-row-render-provenance.json`.
- Final logs: `/private/tmp/diagnostics-row-verified.log`, `/private/tmp/diagnostics-row-analysis-final.log`, `/private/tmp/diagnostics-row-full-analysis-final.log`.

## Native review bundle

`/private/tmp/DiscourseComponentFidelityB104-a872962f.app`

Identifier: `org.discourse.native.component-fidelity.b104.a872962f`. URL scheme: `discourse-component-fidelity-b104-a872962f`.

Kernel SHA256: `58be24947baedb42ee067e049ec9253d5fbb6b23cdf03f55378a74f04e539fe5`.

All 1386 tracked source files match the source commit. app.dill, built and copied kernels match; deep strict ad-hoc signature verification passes. Exact provenance is `/private/tmp/component-fidelity-native-provenance-a872962f.json`; build log is `/private/tmp/component-fidelity-final-native-build.log`.

`tool/title_review_main.dart` adds a Diagnostics rows route with memory-only sample request lifecycles and an error. Select 200% text before opening it, inspect the 360px panel, and open an event’s details. The same bundle retains the title Escape/save fixture and actual styleguide for floating Sidebar and preview-scrollbar checks.

Native review on2026-09-09 inspected the actual360px panel in dark100%/200% and light100%. GET/POST, status200 and120ms duration remain readable; scrolling and opening request details at200% work. Header/filter truncation at200% remains with their future control migrations. Native images and checks are in `/Users/joffreyjaffeux/.codex/visualizations/2026/09/08/01a0816f-d4e0-7f93-9d6b-baeaf6961181/native-fidelity-a872962f/manifest.json`. No spoken VoiceOver or iOS/Linux device verification is claimed.
