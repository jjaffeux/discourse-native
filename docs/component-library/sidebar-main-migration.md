# Main sidebar migration

Implementation task: `01a08b5d-17c8-7de0-9c87-9679d9695d60`.
Branch: `codex/main-sidebar-ui-kit`.

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
