# Title Tooltip follow-up

Status: source verified; native review pending. This correction is committed on
`codex/fix-title-tooltip-escape` at `c5d37bd18148337f3a6be894c27c44af920f0e2c`.
It has not been merged into main.

The current review bundle is
`/private/tmp/DiscourseComponentFidelityB104-6a99b2d2.app`, built at
`6a99b2d29cf15f404db598894557fbd7e75649fc` on
`codex/component-fidelity-follow-up`. It includes this unchanged title fix and
the floating Sidebar `rounded-lg` correction. Inspect title editing, the final
styleguide preview scrollbar, and the floating Sidebar in this one fixture.
Its unique identifier is `org.discourse.native.component-fidelity.b104`, scheme
`discourse-component-fidelity-b104`, and kernel SHA256
`db4f29d8e34dbf63f7862f17b96bd959c948dd208a67d0e7d8db99de053ce7e1`.
Tracked source equality, original/copied kernel equality and deep strict
signature verification pass. Provenance is
`/private/tmp/component-fidelity-native-provenance.json`. The following original
bundle evidence is retained as history; it is superseded for native review.

The existing compact-topic-title Escape test failed after the Tooltip migration:
the duplicate value hint consumed Escape before the editor could cancel. The
editor now disables that supplementary hint while focused or saving. Its visible
text and inline keyboard instructions remain available; the shared Tooltip
component keeps its existing Escape dismissal behavior.

The existing failure was reproduced before the correction. All 114 focused tests
across `topic_inbox_test`, `topic_title_test`, `topic_title_field_ownership_test`,
`ui_tooltip_test` and `d_tooltip_test` pass with seed 9309127. Formatting and root /
full-profile analysis are clean. Logs are in `/private/tmp/title-tooltip-*.log`.

`tool/title_review_main.dart` mounts the real title editor using local fake
services, includes successful and failed-save modes, theme/text-size controls,
and opens the real styleguide. No real account data or app settings are used.

The isolated macOS debug build completed and its copied kernel matches the
source build. The bundle is `/private/tmp/DiscourseTitleReviewB104-c5d37bd1.app`,
with identifier `org.discourse.native.title-review.b104` and URL scheme
`discourse-title-review-b104`. Deep strict ad-hoc signature verification passed,
preserving debug entitlements, flags and runtime.

Kernel SHA256: `b0729f42b1e502b9c87aeb0fe48ac96199008bb667a46862fc68c5e1e0859cdc`.
The source manifest and provenance are in
`/private/tmp/title-tooltip-native-provenance.json`.

The Mac is locked. Native pointer-to-editor focus, Escape cancellation, failed
save recovery, representative themes and the final styleguide scrollbar remain
queued. No native/device or spoken VoiceOver verification is claimed.
