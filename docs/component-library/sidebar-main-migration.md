# Main sidebar migration

Implementation task: `01a08b5d-17c8-7de0-9c87-9679d9695d60`.
Branch: `codex/main-sidebar-ui-kit`.
Source commit: `eea76c81dc985c945218a7764279f51332e3725c`.
Independent review task: `01a08b90-a915-7e83-a5c4-af5ea7981e23`.

The approved follow-up replaces the shared Forum/Chat sidebar presentation with
Native Sidebar. The shell still owns its forum rail, desktop resizing (208px
default, saved 200–480px), mobile page navigation, routing, permissions and
persistence. Plugin interfaces and storage formats are unchanged. The separate
Chat drawer retains its own interaction behavior.

## Composition

- `DSidebarContent.slivers` owns one `CustomScrollView` and `DScrollBar`; a
  supplied controller is borrowed. The eager constructor remains compatible.
- `DSidebarGroup.sliver` composes an eager header and lazy content.
  `DSidebarMenu.sliverBuilder` and `DSidebarMenuSub.sliverBuilder` accept stable
  keys and a child-index callback. Optional fixed extents avoid boundary jumps
  at normal text size. The submenu's estimate includes its 4px row gaps.
- `DCollapsibleContent.sliver` shares the existing controlled disclosure,
  focus restoration, keyboard and hidden-content semantics. Sliver changes
  are immediate; retained content excludes focus while closed.
- `DSidebarMenuItem` measures trailing controls before the primary button in
  the same layout pass. Its full-width button and trailing action remain
  independent hit/semantic targets. Unusually wide trailing content leaves
  up to 96px (at most half the row) for the label and leading artwork.
- The application adapter composes static Sidebar, headers, footers, groups,
  menus, counts, skeletons and dropdowns through `discourse_ui.dart`. It keeps
  artwork, unread dots, live plugin state, More-link promotion, callbacks and
  section restoration. Normal rows use fixed 32px desktop / 48px touch
  extents; scaled rows use natural height and up to two label lines. Status
  and count tokens can wrap independently without splitting each token.
- Chat contributes `DSidebarMenuAction(showOnHover: true)`: desktop hover or
  focus reveals it, mobile viewports show it continuously. Its dropdown opens
  below on mobile and to the side on desktop. Main-sidebar rows no longer
  consume long press. The existing DTO field and Chat drawer remain compatible.

The official [base-nova source](https://ui.shadcn.com/r/styles/base-nova/sidebar.json)
uses a desktop-only opacity rule for `showOnHover` and an enlarged mobile action
hit area. The [application example](https://ui.shadcn.com/r/styles/base-nova/sidebar-07.json)
places project menus below/end on mobile and right/start on desktop. The Native
adapter uses those interaction rules with the kit's platform touch targets.

## Regression evidence

The wide-badge test was added and run before changing the layout. At 200% text,
the label extended 73px into the count (`/tmp/sidebar-wide-badge-before.log`).
The same regression passed after measured trailing layout
(`/tmp/sidebar-wide-badge-after.log`).

The initial native fixture also revealed a Voice status/count squeezing away
its label at 200% text. The added narrow LTR/RTL assertion failed before the
correction (`/tmp/sidebar-scaled-label-before.log`). The corrected row reserves
readable label space, uses two scaled label lines, and wraps status/count tokens.

The 400-row tests verify offscreen destinations stay unbuilt, the final submenu
row is reachable without changing the end boundary, header/footer remain fixed,
and supplied controllers survive disposal. Disclosure tests verify both retained
and unmounted content, keyboard reopening and focus restoration. Changing counts
are checked with independent touch actions at 200px, 200% and both directions.
The registered **Lazy navigation** styleguide example exercises 400 rows, counts,
row actions, collapse and selection, with an interaction regression.

The final combined run passed 394 focused tests
(`/tmp/sidebar-final-verification.log`), covering Sidebar, Collapsible,
styleguide, shell navigation/resizing, Chat, categories, tags, Events, Voice,
section storage and rebuild isolation. After the native label correction,
287 affected Sidebar/styleguide/shell/Chat tests passed
(`/tmp/sidebar-scaled-fix-tests.log`). Final root and full-profile `dart analyze --fatal-infos` passed without issues
(`/tmp/sidebar-root-analysis-final.log`, `/tmp/sidebar-full-analysis-final.log`). No lockfile, dependency or Flutter
version changes are part of this migration.

## Native fixture and review

`tool/sidebar_review_main.dart` mounts the actual `AdaptiveShell` and registered
styleguide/example builders using fake accounts, stores and API responses. Its
controls switch production/example/styleguide surfaces, light/dark, desktop/
390px mobile, 100/200% text and LTR/RTL. Production data includes 400 custom
links, subcategories, disabled destinations, Voice-style status/count tokens,
100 Chat channels and a second site. It performs no real account writes.

An isolated macOS debug bundle is built in the implementation worktree as
`Sidebar Migration Review 8b21.app`, bundle identifier
`org.discourse.sidebarmigrationreview8b21.dev`, URL scheme
`discourse-sidebar-migration-review-8b21`. Temporary runner identity/signing
settings are restored after the build. The fixture is locally ad-hoc signed
with local debug entitlements, excluding push registration; deep strict
signature verification passes. No provisioning, release or OS settings change.
The final build log is `/tmp/sidebar-native-build-final.log`.

Initial light production inspection at 208px and 100/200% text exposed the
scaled-label issue above. The independent reviewer completes the final native
matrix, source review and local main merge under
[the documented procedure](review-and-merge.md). Actual final checks, source
provenance, reviewer ID and merge SHA must be recorded before acceptance.

Final implementation spot checks on 2026-09-10 used the corrected isolated bundle:

- Light production shell at 208px, 100% and 200%: site identity, category artwork,
  disabled destination, Voice status and intact 1234 count, fixed Chat footer.
- 390px mobile Chat navigation at 200%: the visible action opened below its row
  without leaving navigation; Escape dismissed the menu and restored a visible
  action focus ring. Dark RTL retained the action/label/unread-dot ordering.
- Dark RTL mobile lazy example at 200%: count increased 1234 → 2234, disclosure
  closed and reopened with Return, scrolling reached channel 399 while header
  and footer stayed fixed. Only the nearby final rows appeared in native AX.
- The actual desktop ComponentStyleguidePage opened Sidebar and its new Lazy
  navigation section, with the existing eager examples still rendered.

Screenshots and native accessibility trees are inline in the implementation
task. The review task completes official rendered-reference comparison, any
remaining palette/resize/site-switch checks and independent source review.
No physical iOS/Linux device or spoken VoiceOver verification is claimed.

## Independent acceptance — 2026-09-10

Reviewer: `01a08b90-a915-7e83-a5c4-af5ea7981e23`.
Review branch: `codex/review-main-sidebar-ui-kit`, based on local main
`b9ff6ebc5eff4c39cb30fc1bf291031efcfe781f` and preserving implementation
`eea76c81dc985c945218a7764279f51332e3725c` plus final handoff `802036d0`.
Accepted source: `d9106662` (production fixes in `e71fb259`).

Source review found and corrected two shared-layout defects. An `IntrinsicWidth`
row measured its label before reserving the trailing controls, reducing the
test label from 114px to 49px. A submenu also inherited its parent row's badge
reservation, so changing the parent count narrowed the nested destination in
both directions. The regressions failed before correction in
`/tmp/sidebar-review-layout-before.log`. Intrinsic and dry measurements now
compensate for the current trailing width without mutating measurement state;
the item scope surrounds only the primary row. Tests also cover badge growth
and shrinkage, intrinsic height, predicted versus actual resized layout, and
keyboard focus following reordered stable keys in both lazy menu types.

The active separate Chat panel now exposes **Chat navigation** as its native
region label; Forum retains **Forum navigation**. This has an integration
semantics assertion and was confirmed in native AX. The offline fixture gained
Forest/Plum controls and empty local message responses for all 100 channels.
The latter fixes a fixture-only unreachable-site gate when navigating to a
channel with no configured fake message response.

### Verification

- All **401** focused checks pass with seed `9102026` in
  `/tmp/sidebar-review-focused-final.log`: the implementation's 17-file matrix
  above plus `test/d_sidebar_layout_review_test.dart`. This includes affected
  Sidebar, Collapsible, styleguide, Forum/Chat, resizing, routing, persistence,
  permissions, Events, Voice and editor compositions.
- Root and `profiles/full` `dart analyze --fatal-infos` pass in
  `/tmp/sidebar-review-root-analysis-final.log` and
  `/tmp/sidebar-review-full-analysis-final.log`. The subsequent fixture-only
  response map also passes targeted fatal-info analysis in
  `/tmp/sidebar-review-fixture-analysis.log`.
- Formatting and `git diff --check` pass. Root/full dependency resolution used
  `--enforce-lockfile`; dependency files and Flutter 3.47.2 are unchanged.
- Every other progress row and top-level progress record matches the main
  baseline. All required owners are already accepted and merged in main.

### Rendered reference and native inspection

The official [Sidebar demo](https://ui.shadcn.com/view/base-nova/sidebar-demo)
was inspected in Chrome at 1024×800 and 390×800, at 100% scale. Desktop light
and dark, expanded submenus, desktop project actions and the mobile action
dropdown were rendered. The registry hash still matches the original Sidebar
snapshot; the current sidebar-07 registry hash is
`2c1bfd041147775f01ef5c9ac26f74b1475a9a450af6779d3a62141ba9e50d06`.
Measured reference geometry includes the 256px panel, 8px group padding, 32px
group label, 14px/20px menu typography, 20px actions and submenu 2px/10px
padding with 4px gaps. The native styleguide's 256px Application sidebar was
compared at 100% in light and dark, including the independently opening project
menu, centered action, submenu guide, fixed account footer and Share feedback.
The existing app font, palette and radius mapping are retained; this is a
logical-geometry and visual comparison, not pixel equality across renderers.

The reviewer ran the real `AdaptiveShell`, registered Lazy navigation builder
and actual `ComponentStyleguidePage` on macOS 26.6.2, Flutter 3.47.2, using the
project's existing Skia renderer and native font family. Captures and AX trees
are inline in this review task. The following checks were completed:

- Production light at the default 208px; dragging to the explicit 200px minimum
  confirmed **Resize sidebar, 200 pixels wide** in AX. Forest at 200% retained
  separate status/count tokens, disabled styling and the fixed Chat footer.
  Long labels remain ellipsized at that minimum while their full navigation
  names are available to accessibility.
- A collapsed Voice section survived switching to Second community and back.
  Unmounting the shell through Lazy example and returning to Production
  restored both the collapsed section and the saved 200px width. These checks
  used `e71fb259`; only the later fixture message map changed before the final
  bundle, with the relevant production/component source identical.
- Final-bundle 390px Chat at 200% in Plum and Forest: successful local channel
  navigation, the mobile Back path to Chat navigation, visible actions opening
  below independently of the row, live palette updates while the menu remained
  open, Escape closing with a visible action focus ring, and Return reopening.
  Plum RTL preserved icon, label, unread indicator and action ordering.
- Final-bundle Plum RTL lazy example at 200%: count 1234 → 2234, section hiding
  and Return reopening, scrolling to channel 399 with the Community header and
  400-channel footer fixed. Native AX exposed only nearby final rows.
- Final-bundle desktop Sidebar styleguide page: existing eager compositions,
  project action feedback and the new Lazy navigation section.

The exact-source isolated bundle, hashes, signing and launch details are in
[the review build record](evidence/sidebar/main-migration-review-build.json).
The first fixture-only Chat failure is resolved; it was not a production
regression. All account/store data was local and fake. Physical iOS/Linux and
spoken VoiceOver were not tested. The owned app was quit and its absence was
verified, the owned reference tab was closed, temporary browser viewport and
reference theme changes were restored, and the desktop lease was released.

The accepted local main merge is recorded under the existing Sidebar row's
`mainSidebarMigration` object in `progress.json`; original Sidebar history is
preserved.

Cleanup: the isolated app was quit through its menu and its absence verified
with CUA. Desktop lease released; the user application was left running.

## Section row follow-up — 2026-09-10

At the user's request, collapsible section headers now use the same
`DSidebarMenuButton` as Drafts, Users and Filter, retaining the supplied title
casing. A leading disclosure arrow occupies the normal icon slot and mirrors
in RTL. `DSidebarMenuItem` keeps section actions separate from disclosure.
The button owns keyboard activation and expanded semantics; controlled
`DCollapsibleContent.sliver` and the existing store retain visibility and
restoration. No component library API changed.

One shared `DSidebarGroup.sliver` supplies the navigation's outer padding,
so successive section rows have the same spacing as ordinary destinations.
The user requested one separator after More; it has 8px of space above and
below. Other section separators were removed. Headerless Community links,
lazy menus, badges and the fixed forum/Chat controls retain their owners.

Source: `c86ed14b`, branch `codex/sidebar-section-rows`, reviewer
`01a08b90-a915-7e83-a5c4-af5ea7981e23`. Native macOS inspection covered the real
production fixture at 208px in light/dark, collapsed custom sections and an
independent action that incremented local feedback without expanding its
section. Plum RTL at 200% was checked at 208px and in the 390px iOS-target
fixture. Full section names remained in native accessibility output; narrow
labels wrap or ellipsize as ordinary rows do. Returning to desktop retained
the collapsed state. The inspected source and kernel hashes are recorded in
[the build evidence](evidence/sidebar/section-rows-review-build.json).

Existing shell regressions now compare row typography, alignment and height,
assert the sole separator's placement, and reopen a section with Enter after
pointer collapse. The scaled-width check verifies that the trailing action
does not toggle disclosure. Chat heading queries now use disclosure tooltips
to distinguish sections from other title-cased Chat labels.

Verification: 127 shell/width/Voice/Events/rebuild/store checks passed, followed
by all 139 Chat checks after replacing old uppercase-heading expectations
(`/tmp/sidebar-section-rows-tests.log`,
`/tmp/sidebar-section-rows-chat-tests.log`, seed 9102026). The final candidate
starts from main `de07b578`, preserving its independently merged scrollbar
defaults. All 111 shell/width checks and fatal-info root analysis passed on
that candidate (`/tmp/sidebar-section-rows-integration-tests.log`,
`/tmp/sidebar-section-rows-integration-analysis.log`). The inspected row and
disclosure sources remain identical; the new shared scrollbar width does not
change row layout. Formatting and diff checks passed.

The isolated app was quit through its menu, its absence verified, and the
desktop lease released. No physical iOS/Linux or spoken screen reader testing
was performed. Original Sidebar review history remains in progress; this
follow-up's local merge is recorded in `sectionRowsFollowUp`.

## Custom child icon follow-up — 2026-09-10

The user requested smaller icons for links inside custom sections. Those
sections use the `custom-` ID prefix supplied by `SidebarSection.customFromJson`.
Their destination icons now pass size 12 to `DIcon`, down from 16. The existing
leading column stays centered and retains its width, so text alignment and row
hit areas do not move. Disclosure arrows and other navigation artwork retain
their existing sizes. This uses the existing public UI kit without an API change.

All 111 existing shell navigation/width checks, root fatal-info analysis and
formatting passed. Native macOS inspection covered the production fixture in
light/dark at 208px and the dark 390px iOS-target layout at 100% text. Smaller
link icons remained centered and readable beside the unchanged labels.
[Build evidence](evidence/sidebar/custom-child-icons-review-build.json) records
the inspected source, kernel and cleanup. No physical iOS/Linux or spoken
screen reader verification was performed. The local merge is recorded under
`customChildIconsFollowUp` in the existing Sidebar progress row.

## Chat header tooltip follow-up — 2026-09-10

The user requested no disclosure tooltips on Starred channels, Chat and
Direct messages. Chat opts those sections out through `showHeaderTooltip`;
the shell uses the existing `DTooltip.disabled` and `excludeFromSemantics`
options. The disclosure button retains its accessible Expand/Collapse label
and expanded state. Other section and action tooltip settings retain their
existing behavior. Model copies and the plugin ownership adapter preserve
the option, keeping Chat-specific IDs out of the shell renderer.

The first native pass caught the plugin adapter dropping this setting. A hover
check in the existing starred-channel test reproduced the visible tooltip
before that copy was fixed (`/tmp/chat-header-tooltips-hover-before.log`).
All 244 focused Chat/shell/section-store tests now pass, with root fatal-info
analysis and formatting clean. The final native macOS light/dark 208px fixture
confirmed the three collapsed headers have no popup under the pointer and
Return reopens Direct messages with visible keyboard focus.
[Build evidence](evidence/sidebar/chat-header-tooltips-review-build.json)
records exact source, kernel and cleanup. No physical iOS/Linux or spoken
screen reader verification was performed. Local merge history is stored in
`chatHeaderTooltipsFollowUp` under the existing Sidebar progress row.

## All header tooltips follow-up — 2026-09-10

The user extended the request to every sidebar section, including custom
sections, Categories and Voice rooms. The shell now renders disclosure buttons
without a tooltip wrapper. The preceding Chat-specific `showHeaderTooltip`
option and its model copies are no longer needed and were removed. Native
menu buttons still own their accessible Expand/Collapse labels, expanded state
and keyboard activation; independent section actions retain their tooltips.
The public component library is unchanged.

Existing tests now locate the menu buttons directly. The custom-section
navigation check hovers expanded Projects/Categories and collapsed Projects,
then reopens Projects with Enter. All 252 focused Chat, shell, width and
section-store checks pass, with fatal-info root analysis and formatting clean
(`/tmp/sidebar-no-header-tooltips-tests.log` and
`/tmp/sidebar-no-header-tooltips-analysis.log`, seed 9102026).

Native macOS inspection covered the real production fixture at 208px in
light/dark at 100%, plus a dark 200% wrapped disclosure. Collapsed section
headers display no popup under the pointer. Return reopens the Voice-style
section with visible focus, and its independent plus action increments local
feedback while the section stays collapsed. Full labels remain in native AX.
[Build evidence](evidence/sidebar/all-header-tooltips-review-build.json)
records source, kernel and cleanup. No physical iOS/Linux or spoken screen
reader verification was performed. The local merge is recorded in
`allHeaderTooltipsFollowUp` under the existing Sidebar progress row.

## Row gap follow-up — 2026-09-10

The user requested a 1px separation between selected and hovered sidebar rows.
The app now composes its existing Native menu buttons with one logical pixel
of bottom padding on each top-level destination and section header. Fixed
lazy row extents include that extra pixel, retaining the 32px desktop and 48px
touch buttons. Stable row keys sit on the padded lazy children, and scaled
rows continue to size from their content. The submenu's existing 4px gap and
the public component library are unchanged.

The existing hover check now uses an authenticated macOS-target fixture with
Topics selected and Messages hovered. It measures a 1px gap and verifies that
moving the pointer into the gap clears the hover background. Existing custom
section and 200% header geometry checks include the gap. One stale rail
assertion was aligned with the Native avatar adoption already on main.
All 252 focused Chat/shell/width/section-store tests pass with seed 9102026
(`/tmp/sidebar-row-gap-final-tests.log`), along with fatal-info root analysis
(`/tmp/sidebar-row-gap-final-analysis.log`), formatting and diff checks.

Native macOS inspection covered Topics selected beside Messages hovered at
208px in light/dark at 100% and dark at 200%. Their backgrounds remain
separate. The dark 390px iOS-target fixture also retained its normal navigation
layout and separate section actions after returning through Back.
[Build evidence](evidence/sidebar/row-gap-review-build.json) records the exact
source, kernel and cleanup. The fixture's unconfigured personal-message inbox
showed an error when opened; hover inspection returned to Topics. No physical
iOS/Linux or spoken screen reader verification was performed. The local
merge is recorded under `rowGapFollowUp` in the existing Sidebar progress row.

## Forum header tooltip follow-up — 2026-09-10

The user requested no tooltip on the forum identity header. The URL and
options-icon tooltip wrappers were removed. The existing Native dropdown
trigger still owns the header button, focus and expanded state, while the
visible name and hostname supply its accessible identity. No component API
or header layout changed.

All 111 existing shell navigation and width tests pass with seed 9102026
(`/tmp/forum-header-no-tooltips-tests.log`). Fatal-info root analysis,
formatting and diff checks pass (`/tmp/forum-header-no-tooltips-analysis.log`).

Native macOS inspection at 208px in light/dark at 100% confirmed no tooltip
over the URL or options icon. The full forum name and hostname remain in AX.
Click opens the menu, Escape closes it with visible focus restored to the
header, and Return reopens it. [Build evidence](evidence/sidebar/forum-header-tooltips-review-build.json)
records the inspected source, kernel and cleanup. No physical iOS/Linux or
spoken screen reader verification was performed. Local merge history is
recorded under `forumHeaderTooltipsFollowUp` in the existing Sidebar row.
