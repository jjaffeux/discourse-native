# Topic scrolling: surrounding navigation rebuilds

September 22, 2026, live macOS debug session. Interactions were limited to
scrolling an existing topic. Widget-build and render-layout tracing were enabled
for attribution; these timings include debug and instrumentation overhead.

Two upward-scroll captures showed different contributors:

- A 68.0 ms root layout included 55.9 ms of widget building and 2.9 ms of
  paragraph layout. HTML conversion took 6.4 ms. First construction remains
  expensive in this case.
- The next capture had 74.8 ms and 60.1 ms root layouts, containing 70.1 ms
  and 57.2 ms of building respectively. Paragraph layout was 0.35 ms and
  zero. There was no HTML conversion in this capture. The latter frame rebuilt
  the sidebar (19.7 ms inclusive) and all nine forum tabs while earlier posts
  were being loaded. Nested timings must not be added together.

Two avoidable paths were confirmed in the source:

1. Saving a reading anchor replaces a `ForumTab` and its list. The next shell
   notification invalidates the tab-strip selector, although its visible
   presentation can be unchanged. `ForumTabsBar` now retains its rendered
   subtree when all presentation inputs match. Callbacks delegate to current
   widget properties. Presentation, inherited dependency and hot-reload changes
   invalidate that subtree. Plugin destinations are still evaluated normally.
2. `ChatShellService` forwarded every host notification to its listeners,
   including the sidebar-panel listener. It now forwards host changes only
   when its exposed presentation changes, including instance identity, route,
   totals, reader bounds, chat availability and Do Not Disturb expiry. Drawer
   commands continue to notify normally.

The tab regression reproduces two control rebuilds before the fix and zero
afterwards for equivalent replacement items. It also checks replacement
callbacks and changed labels/badges/selection. Service and
integration tests cover notification filtering and chat behavior.

The relevant suites passed 216 tests. Four existing mobile-navigation failures
were reproduced with both production changes removed and excluded from that
run: the two mobile forum-tab subtree cases, mobile Chat mode visibility, and
the disconnected-site navigation case.

The first post-change capture was discarded: after hot reload Flutter entered
an accessibility assertion loop (`node.built` / semantics-node geometry). The
user restarted the app, and profiling continued without hot reload. The new
session remained stable.

A subsequent uncached-post capture contained no `DDocumentTab` or
`ShellSelector<_SidebarPanelSnapshot>` builds. First-time post construction still
produced 54.4 ms and 51.8 ms root layouts, including 44.4 ms and 46.7 ms of
building. Seven HTML conversions totalled 4.2 ms across that capture. This
confirms that removing navigation work does not eliminate post mounting cost.

With detailed widget/layout tracing disabled, the final debug capture had 80
frames: UI median 0.95 ms, p95 6.69 ms, maximum 47.62 ms, and three frames over
16.67 ms. The worst layout contained 38.9 ms of building in 45.5 ms. Raster
median was 1.30 ms, p95 2.63 ms, and maximum 19.30 ms. These are observations,
not a matched before/after benchmark: posts and viewport width differed from
the earlier session. Profile-mode measurement is still needed before treating
remaining debug mounting costs as production bottlenecks. Both detailed
profiling flags were restored to false afterwards.
