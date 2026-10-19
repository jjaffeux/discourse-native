# Tab presentation context

Desktop panels can display two documents while one tab owns keyboard input.
`ShellController.activeTab` identifies that input target. A displayed document
reads through `ShellTabContext`, captured from `ForumTabScope.tabOf(context)`.

```dart
ForumTabSelector<TopicViewportSnapshot>(
  select: (shell, tab) => TopicViewportSnapshot.from(shell, tab: tab),
  builder: (context, snapshot, child) => buildReader(snapshot),
);

final tab = ForumTabScope.tabOf(context);
final route = tab.currentContent;
await tab.loadFeed(tab.currentFeedId!, force: true);
if (!context.mounted || !tab.isCurrent || tab.currentContent != route) return;
```

The context captures its controller, site, account session, account identity and
tab ID. It resolves the latest tab on each read, so moving a tab between panels
preserves ownership. Removing the tab, disposing the controller or replacing the
account retires the context. Deferred widget work also checks that its widget
still uses the captured controller and route. Context validity establishes tab
ownership; each interaction decides whether it also requires visibility or input
focus.

An explicit null tab ID represents an empty panel. Outside `ForumTabScope`, the
lookup captures the focused tab. Neither case temporarily changes shell state.
Global chrome uses `ShellSelector`; document selectors use `ForumTabSelector`.
Both suppress rebuilds when their selected value is equal. Services such as
topic feeds and search keep their independent notifiers.

The shell facade retains its existing focused getters and commands for app
shortcuts, plugin services and headless callers. Document projections share one
implementation in the shell's context part. Tab-sensitive commands carry their
source through feed-path resolution, topic anchors, draft restoration and
hydration. Both selected desktop tabs hydrate explicitly.

This design keeps the live context narrow rather than forwarding the whole shell
through a proxy. A frozen tab snapshot would become stale during deferred work;
dynamic callback scoping would keep ownership hidden. Stable widget keys and
editor controllers remain with the existing panel and composer owners.

Keyboard fallback and entry focus intentionally inspect the focused shell tab.
Display ownership alone must never cause a background reader to request focus.
The panel, scope, rebuild-isolation, list-restoration and reader lifecycle tests
cover these boundaries, including delayed commands and retained editor identity.

Users directory selection belongs to the displayed tab. `ShellTabContext` reads
its complete `UserDirectoryQuery` from `ShellSearchController` and applies field
changes to the latest value. Users page words adapt that same query, so search
chrome and directory controls share one selection. Queries remain in session
memory and follow the existing retention of live and reopenable tabs. Workspace
serialization is unchanged. `UserDirectoryController` owns shared site metadata
and the bounded `(site, query)` result cache. Its state and load methods require
an explicit query. A current tab can reuse those results without choosing a
query for any other tab. Host callbacks also capture their route and controller.
