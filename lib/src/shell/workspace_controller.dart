part of 'shell_controller.dart';

final class _WorkspaceController {
  _WorkspaceController(this._shell);

  final ShellController _shell;
  final Map<String, ForumWorkspace> _forumWorkspaces = {};
  final List<_ClosedForumTab> _closedForumTabs = [];
  final Map<_PluginPaneKey, ForumTab> _mainPaneTabs = {};
  final Map<_PluginPaneKey, ForumTab> _pluginPaneTabs = {};
  final Map<_PluginPaneStateKey, PluginId> _activePluginPanes = {};
  final Set<_PluginPaneStateKey> _coldPluginPanes = {};
  int _tabSequence = 0;
  ShellTabContext? _pendingTabSelection;
  bool _tabSelectionSettlementScheduled = false;
  bool _tabSelectionPersistencePending = false;
  Timer? _anchorPersistTimer;
  bool _anchorPersistencePending = false;
  Future<void> _writesSettled = Future<void>.value();
  bool _disposed = false;

  bool get canCreateTab =>
      _shell.forumTabsEnabled &&
      (_shell.currentWorkspace?.tabs.length ?? 0) < ForumWorkspace.maximumTabs;

  void reset(DiscourseInstance instance) => put(_newWorkspace(instance));

  void configureDesktopPanels() {
    for (final workspace in values.toList()) {
      put(workspace);
    }
    scheduleMicrotask(() {
      if (!_disposed &&
          _shell.desktopPanelsEnabled &&
          _shell.currentInstance != null) {
        _shell._hydrateActiveTab(_shell.currentInstance!);
        _shell._syncTopicChannels();
      }
    });
  }

  Iterable<ForumWorkspace> get values => _forumWorkspaces.values;
  ForumWorkspace? forSite(String siteUrl) => _forumWorkspaces[siteUrl];
  Future<void> get writesSettled => _writesSettled;
  bool awaitsHomepage(String id) => _pendingHomepageTabs.contains(id);
  void consumeHomepage(String? id) => _pendingHomepageTabs.remove(id);

  bool restore(Iterable<ForumWorkspace> workspaces) {
    for (final workspace in _forumWorkspaces.values) {
      _shell._readerProjections.retainTabs(
        workspace.siteUrl,
        _shell.lifecycle.capture(workspace.siteUrl),
        {},
      );
    }
    _forumWorkspaces.clear();
    var workspacesNormalized = false;
    for (final workspace in workspaces) {
      final normalized = _normalize(workspace);
      workspacesNormalized =
          workspacesNormalized || !identical(normalized, workspace);
      final instance = _shell._instanceAt(workspace.siteUrl);
      if (instance != null &&
          workspace.accountIdentity ==
              ShellController._workspaceAccountIdentity(instance)) {
        _forumWorkspaces[workspace.siteUrl] = normalized;
      }
    }
    _retainTabState();
    return workspacesNormalized;
  }

  void flushSelection() {
    if (_tabSelectionPersistencePending) persist();
  }

  void dispose() {
    _disposed = true;
    _pendingTabSelection = null;
    _tabSelectionSettlementScheduled = false;
    _anchorPersistTimer?.cancel();
    _anchorPersistTimer = null;
    if (_tabSelectionPersistencePending || _anchorPersistencePending) persist();
    _closedForumTabs.clear();
  }

  String _nextTabId() {
    final held = <String>{
      for (final workspace in _forumWorkspaces.values)
        for (final tab in workspace.tabs) tab.id,
    };
    late String id;
    do {
      _tabSequence++;
      id =
          'tab-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
          '${_tabSequence.toRadixString(36)}';
    } while (held.contains(id));
    return id;
  }

  final Set<String> _pendingHomepageTabs = {};

  ForumTab _newDefaultTab() {
    final id = _nextTabId();
    return ForumTab(
      id: id,
      rootDestinationId: 'new-tab',
      contentStack: [ContentRoute.newTab()],
    );
  }

  ForumWorkspace _newWorkspace(DiscourseInstance instance) {
    final id = _nextTabId();
    final tab = ForumTab(
      id: id,
      rootDestinationId: instance.defaultDestination.id,
      contentStack: [_shell._homepageFor(instance)],
    );
    _pendingHomepageTabs.add(id);
    return ForumWorkspace(
      siteUrl: instance.url,
      accountIdentity: ShellController._workspaceAccountIdentity(instance),
      tabs: [tab],
      activeTabId: tab.id,
    );
  }

  ForumWorkspace _normalize(ForumWorkspace workspace) {
    if (!_shell.forumTabsEnabled && workspace.tabs.length > 1) {
      return workspace.copyWith(tabs: [workspace.activeTab]);
    }
    if (_shell.forumTabsEnabled) {
      final limit = _shell.desktopPanelsEnabled
          ? ForumWorkspace.maximumWorkspaceTabs
          : ForumWorkspace.maximumTabs;
      for (final panel in ForumPanel.values) {
        if (panel == ForumPanel.secondary && !_shell.desktopPanelsEnabled) {
          continue;
        }
        if (workspace.tabsIn(panel).isEmpty && workspace.tabs.length < limit) {
          final tab = _newDefaultTab().copyWith(panel: panel);
          workspace = workspace.copyWith(tabs: [...workspace.tabs, tab]);
        }
      }
    }
    return workspace;
  }

  ForumWorkspace ensure(DiscourseInstance instance, {bool persist = true}) {
    final existing = _forumWorkspaces[instance.url];
    if (existing != null &&
        existing.accountIdentity ==
            ShellController._workspaceAccountIdentity(instance)) {
      return existing;
    }
    _forgetPluginPaneTabs(instance.url);
    final workspace = _normalize(_newWorkspace(instance));
    _forumWorkspaces[instance.url] = workspace;
    _retainTabState();
    if (persist) this.persist();
    return workspace;
  }

  void put(ForumWorkspace workspace, {bool persist = true}) {
    final normalized = _normalize(workspace);
    _forumWorkspaces[normalized.siteUrl] = normalized;
    _retainTabState();
    final liveTabIds = {for (final tab in normalized.tabs) tab.id};
    _mainPaneTabs.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _pluginPaneTabs.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _activePluginPanes.removeWhere(
      (key, _) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    _coldPluginPanes.removeWhere(
      (key) =>
          key.siteUrl == normalized.siteUrl && !liveTabIds.contains(key.tabId),
    );
    if (persist) this.persist();
  }

  void _retainTabState() {
    for (final workspace in _forumWorkspaces.values) {
      _shell._readerProjections.retainTabs(
        workspace.siteUrl,
        _shell.lifecycle.capture(workspace.siteUrl),
        {for (final tab in workspace.tabs) tab.id},
      );
    }
    _shell.search.retainTabs({
      for (final workspace in _forumWorkspaces.values)
        for (final tab in workspace.tabs)
          (siteUrl: workspace.siteUrl, tabId: tab.id),
      for (final closed in _closedForumTabs)
        (siteUrl: closed.siteUrl, tabId: closed.tab.id),
    });
  }

  void remove(String siteUrl, {bool persist = true}) {
    _shell._readerProjections.retainTabs(
      siteUrl,
      _shell.lifecycle.capture(siteUrl),
      {},
    );
    _forgetPluginPaneTabs(siteUrl);
    final removed = _forumWorkspaces.remove(siteUrl);
    if (removed == null) return;
    for (final tab in removed.tabs) {
      _pendingHomepageTabs.remove(tab.id);
    }
    if (persist) this.persist();
  }

  void _forgetPluginPaneTabs(String siteUrl) {
    _mainPaneTabs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _pluginPaneTabs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _activePluginPanes.removeWhere((key, _) => key.siteUrl == siteUrl);
    _coldPluginPanes.removeWhere((key) => key.siteUrl == siteUrl);
  }

  void persist() {
    _tabSelectionPersistencePending = false;
    _anchorPersistencePending = false;
    _writesSettled = _shell.forumTabs
        .save(
          _forumWorkspaces.values,
          selectedSiteUrl: _shell.currentInstance?.url,
        )
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  void schedulePersistAnchors() {
    _anchorPersistencePending = true;
    if (_anchorPersistTimer != null) return;
    _anchorPersistTimer = Timer(_shell.anchorPersistDebounce, () {
      _anchorPersistTimer = null;
      if (_disposed || !_anchorPersistencePending) return;
      persist();
    });
  }

  void flushAnchors() {
    _anchorPersistTimer?.cancel();
    _anchorPersistTimer = null;
    if (_anchorPersistencePending) persist();
  }

  void replaceTab(String siteUrl, ForumTab replacement, {bool persist = true}) {
    final workspace = _forumWorkspaces[siteUrl];
    if (workspace == null || workspace.tabById(replacement.id) == null) return;
    put(
      workspace.copyWith(
        tabs: [
          for (final tab in workspace.tabs)
            if (tab.id == replacement.id) replacement else tab,
        ],
      ),
      persist: persist,
    );
  }

  void replaceActiveTab(ForumTab replacement, {bool persist = true}) {
    _pendingHomepageTabs.remove(replacement.id);
    final siteUrl = _shell.currentInstance?.url;
    if (siteUrl != null) {
      replaceTab(siteUrl, replacement, persist: persist);
    }
  }

  TabOpenResult openContentInNewTab(
    ContentRoute route, {
    String? siteUrl,
    ForumPanel? panel,
    int? index,
    bool? select,
    String? rootDestinationId,
    ForumTab? source,
  }) {
    if (!_shell.forumTabsEnabled) return TabOpenResult.unsupported;
    final instance = siteUrl == null
        ? _shell.currentInstance
        : _shell._instances.where((site) => site.url == siteUrl).firstOrNull;
    if (instance == null) return TabOpenResult.unsupported;
    final workspace = ensure(instance);
    if (workspace.tabs.length >= ForumWorkspace.maximumTabs) {
      return TabOpenResult.limitReached;
    }
    final root = _newDefaultTab();
    final tab =
        (source != null
                ? ForumTab(
                    id: root.id,
                    rootDestinationId: source.rootDestinationId,
                    contentStack: [
                      ...source.contentStack
                          .where(
                            (item) =>
                                !item.sameDestinationAs(route) &&
                                (!route.isTopic || !item.isTopic),
                          )
                          .take(ForumTab.maximumContentRoutes - 1),
                      route,
                    ],
                  )
                : root.copyWith(
                    rootDestinationId: rootDestinationId ?? route.id,
                    contentStack: [route],
                  ))
            .copyWith(
              panel: panel ?? workspace.activeTab.panel,
              rootDestinationId: rootDestinationId,
            );
    final activate = select ?? _shell.desktopTopicTabs;
    _pendingHomepageTabs.remove(tab.id);
    final tabs = [...workspace.tabs];
    if (index == null) {
      tabs.add(tab);
    } else {
      final destinationTabs = tabs
          .where((item) => item.panel == tab.panel)
          .toList();
      final position = index.clamp(0, destinationTabs.length);
      final insertion = position < destinationTabs.length
          ? tabs.indexOf(destinationTabs[position])
          : destinationTabs.isEmpty
          ? tabs.length
          : tabs.indexOf(destinationTabs.last) + 1;
      tabs.insert(insertion, tab);
    }
    put(workspace.copyWith(tabs: tabs, activeTabId: activate ? tab.id : null));
    _shell._rememberRoute(instance.url, workspace.accountIdentity, route);
    if (activate && _shell.currentInstance?.url == instance.url) {
      _shell._mobilePane = MobilePane.content;
      _shell._hydrateActiveTab(instance);
    }
    _shell._syncTopicChannels();
    _shell._notify();
    return TabOpenResult.opened;
  }

  TabOpenResult openContentInPanel(
    ContentRoute route, {
    required ForumPanel panel,
    bool resetScrollPosition = false,
    ShellTabContext? context,
  }) {
    final instance = _shell.currentInstance;
    final workspace = _shell.currentWorkspace;
    if (context != null &&
        (!identical(context.shell, _shell) || !context.isCurrent)) {
      return TabOpenResult.unsupported;
    }
    final source = context == null ? _shell.activeTab : context.tab;
    if (instance == null || workspace == null || source == null) {
      return TabOpenResult.unsupported;
    }
    if (source.panel == panel &&
        context != null &&
        source.id != _shell.activeTabId) {
      final anchors = Map<String, ForumTabAnchor>.of(source.anchors);
      if (resetScrollPosition) anchors.remove(route.id);
      _pendingHomepageTabs.remove(source.id);
      replaceTab(instance.url, source.copyWith(anchors: anchors).push(route));
      _shell._setForumContentRoot();
      _shell._syncTopicChannels();
      _shell._notify();
      _shell._hydrateTab(instance, context);
      return TabOpenResult.opened;
    }
    if (source.panel == panel) {
      if (resetScrollPosition && source.anchors.containsKey(route.id)) {
        replaceActiveTab(
          source.copyWith(
            anchors: Map<String, ForumTabAnchor>.of(source.anchors)
              ..remove(route.id),
          ),
          persist: false,
        );
      }
      _shell.pushContent(route);
      _shell._hydrateActiveTab(instance);
      return TabOpenResult.opened;
    }
    final selected = workspace.selectedTabIn(panel);
    if (selected == null) {
      return openContentInNewTab(
        route,
        panel: panel,
        select: true,
        source: source,
      );
    }

    final target = selected.navigate(
      rootDestinationId: source.rootDestinationId,
      contentStack: [
        ...source.contentStack
            .where(
              (item) =>
                  !item.sameDestinationAs(route) &&
                  (!route.isTopic || !item.isTopic),
            )
            .take(ForumTab.maximumContentRoutes - 1),
        route,
      ],
    );
    final updated = resetScrollPosition
        ? target.copyWith(
            anchors: Map<String, ForumTabAnchor>.of(target.anchors)
              ..remove(route.id),
          )
        : target;
    _pendingHomepageTabs.remove(updated.id);
    put(
      workspace.copyWith(
        tabs: [
          for (final tab in workspace.tabs)
            if (tab.id == updated.id) updated else tab,
        ],
        activeTabId: updated.id,
      ),
    );
    _shell._setForumContentRoot();
    _shell._syncTopicChannels();
    _shell._notify();
    _shell._hydrateActiveTab(instance);
    return TabOpenResult.opened;
  }

  /// Switches sidebar panels in a fresh tab, retaining both pane histories.
  void switchSidebarPanel(VoidCallback switchPanel) {
    if (!_shell.forumTabsEnabled || _shell.desktopPanelsEnabled) {
      switchPanel();
      return;
    }
    final instance = _shell.currentInstance;
    final workspace = _shell.currentWorkspace;
    final source = _shell.activeTab;
    if (!canCreateTab ||
        instance == null ||
        workspace == null ||
        source == null) {
      return;
    }

    final id = _nextTabId();
    ForumTab copyTab(ForumTab tab) => ForumTab(
      id: id,
      panel: tab.panel,
      rootDestinationId: tab.rootDestinationId,
      contentStack: tab.contentStack,
      backHistory: tab.backHistory,
      forwardHistory: tab.forwardHistory,
      anchors: tab.anchors,
    );

    for (final panes in [_mainPaneTabs, _pluginPaneTabs]) {
      final entries = panes.entries
          .where(
            (entry) =>
                entry.key.siteUrl == instance.url &&
                entry.key.tabId == source.id,
          )
          .toList();
      for (final entry in entries) {
        panes[(siteUrl: instance.url, tabId: id, owner: entry.key.owner)] =
            copyTab(entry.value);
      }
    }
    final sourceKey = (siteUrl: instance.url, tabId: source.id);
    final targetKey = (siteUrl: instance.url, tabId: id);
    if (_activePluginPanes[sourceKey] case final owner?) {
      _activePluginPanes[targetKey] = owner;
    }
    if (_coldPluginPanes.contains(sourceKey)) {
      _coldPluginPanes.add(targetKey);
    }
    put(
      workspace.copyWith(
        tabs: [...workspace.tabs, copyTab(source)],
        activeTabId: id,
      ),
    );
    _shell._mobilePane = MobilePane.content;
    _shell._syncTopicChannels();
    _shell._notify();
    switchPanel();
  }

  void createTab({ForumPanel? panel}) {
    if (!canCreateTab) return;
    final instance = _shell.currentInstance;
    if (instance == null) return;
    final workspace = ensure(instance);
    final tab = _newDefaultTab().copyWith(
      panel: panel ?? workspace.activeTab.panel,
    );
    put(
      workspace.copyWith(tabs: [...workspace.tabs, tab], activeTabId: tab.id),
    );
    _shell._mobilePane = MobilePane.content;
    _shell._syncTopicChannels();
    _shell._notify();
    _shell._hydrateActiveTab(instance);
  }

  void selectTab(String id) {
    if (!_shell.forumTabsEnabled) return;
    final instance = _shell.currentInstance;
    final workspace = _shell.currentWorkspace;
    if (instance == null || workspace?.tabById(id) == null) return;
    if (workspace!.activeTabId != id) {
      put(workspace.copyWith(activeTabId: id), persist: false);
      _tabSelectionPersistencePending = true;
      _shell._mobilePane = MobilePane.content;
      _pendingTabSelection = _shell.tabContext(id);
      _shell._notify();
      _scheduleTabSelectionSettlement();
    }
  }

  /// Moves a tab without replacing its route, history, anchors or identity.
  void moveTabToPanel(String id, ForumPanel panel, {int? index}) {
    if (!_shell.desktopTopicTabs || !_shell.forumTabsEnabled) return;
    final workspace = _shell.currentWorkspace;
    final tab = workspace?.tabById(id);
    if (workspace == null || tab == null) return;
    final sourceWillBeEmpty =
        tab.panel != panel && workspace.tabsIn(tab.panel).length == 1;
    if (sourceWillBeEmpty &&
        workspace.tabs.length >= ForumWorkspace.maximumTabs) {
      return;
    }
    final tabs = [...workspace.tabs]..removeWhere((item) => item.id == id);
    final destinationTabs = tabs.where((item) => item.panel == panel).toList();
    final offset = (index ?? destinationTabs.length).clamp(
      0,
      destinationTabs.length,
    );
    final insertion = offset < destinationTabs.length
        ? tabs.indexOf(destinationTabs[offset])
        : destinationTabs.isEmpty
        ? tabs.length
        : tabs.indexOf(destinationTabs.last) + 1;
    tabs.insert(insertion, tab.copyWith(panel: panel));
    if (sourceWillBeEmpty) {
      tabs.add(_newDefaultTab().copyWith(panel: tab.panel));
    }
    put(workspace.copyWith(tabs: tabs, activeTabId: id));
    _shell._syncTopicChannels();
    _shell._notify();
    if (_shell.currentInstance case final instance?) {
      _shell._hydrateActiveTab(instance);
    }
  }

  void moveTab(String id, int newIndex) {
    if (!_shell.forumTabsEnabled) return;
    final workspace = _shell.currentWorkspace;
    if (workspace == null || workspace.tabs.length < 2) return;
    final oldIndex = workspace.tabs.indexWhere((tab) => tab.id == id);
    if (oldIndex < 0) return;
    final destination = newIndex.clamp(0, workspace.tabs.length - 1);
    if (oldIndex == destination) return;

    final reordered = List<ForumTab>.of(workspace.tabs);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(destination, moved);
    put(workspace.copyWith(tabs: reordered));
    _shell._notify();
  }

  void _scheduleTabSelectionSettlement() {
    // Controller-only consumers have nothing to paint. Preserve their
    // synchronous hydration/persistence semantics rather than leaving a task
    // waiting for a test or headless binding to produce a frame.
    if (!_shell._workspaceHasListeners) {
      _settlePendingTabSelection();
      return;
    }
    if (_tabSelectionSettlementScheduled) return;
    _tabSelectionSettlementScheduled = true;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final needsAnotherFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.postFrameCallbacks;
    unawaited(() async {
      // endOfFrame schedules a frame when called while idle. Unlike a zero
      // duration timer, it guarantees the selected indicator, header and
      // cached viewport have had an opportunity to paint first.
      await SchedulerBinding.instance.endOfFrame;
      // A selection raised while layout/paint or another post-frame callback
      // is running cannot notify its widgets until the following frame.
      if (needsAnotherFrame) await SchedulerBinding.instance.endOfFrame;
      if (!_disposed) _settlePendingTabSelection();
    }());
  }

  void _settlePendingTabSelection() {
    final target = _pendingTabSelection;
    _pendingTabSelection = null;
    _tabSelectionSettlementScheduled = false;
    if (_tabSelectionPersistencePending) persist();
    if (target == null ||
        !target.isCurrent ||
        _shell.activeTabId != target.tabId) {
      return;
    }

    final instance = _shell._instanceAt(target.siteUrl!);
    if (instance == null) return;
    _shell._syncTopicChannels();
    _shell._hydrateActiveTab(instance);
  }

  void closeTab(String id) {
    if (!_shell.forumTabsEnabled) return;
    final instance = _shell.currentInstance;
    final workspace = _shell.currentWorkspace;
    if (instance == null || workspace == null) return;
    final index = workspace.tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;

    final closedActive = workspace.activeTabId == id;
    final closedVisible = _shell.isTabVisible(id);
    _rememberClosedForumTab(
      siteUrl: workspace.siteUrl,
      accountIdentity: workspace.accountIdentity,
      tab: workspace.tabs[index],
      index: index,
    );
    late ForumWorkspace replacement;
    if (workspace.tabs.length == 1) {
      final fresh = _newDefaultTab().copyWith(
        panel: workspace.tabs[index].panel,
      );
      replacement = workspace.copyWith(tabs: [fresh], activeTabId: fresh.id);
    } else {
      final remaining = [
        for (final tab in workspace.tabs)
          if (tab.id != id) tab,
      ];
      final neighbours = [
        ...workspace.tabs.skip(index + 1),
        ...workspace.tabs.take(index).toList().reversed,
      ];
      final neighbour = neighbours
          .where((tab) => tab.panel == workspace.tabs[index].panel)
          .firstOrNull;
      final fresh = neighbour == null
          ? _newDefaultTab().copyWith(panel: workspace.tabs[index].panel)
          : null;
      if (fresh != null) remaining.add(fresh);
      final activeId = closedActive
          ? (neighbour ?? fresh ?? remaining.first).id
          : workspace.activeTabId;
      replacement = workspace.copyWith(
        tabs: remaining,
        activeTabId: activeId,
        mainTabId: workspace.selectedTabIn(ForumPanel.main)?.id == id
            ? (neighbour ?? fresh)?.id
            : null,
        secondaryTabId: workspace.selectedTabIn(ForumPanel.secondary)?.id == id
            ? (neighbour ?? fresh)?.id
            : null,
      );
    }

    put(replacement);
    if (closedVisible) {
      _shell._syncTopicChannels();
      _shell._hydrateActiveTab(instance);
    }
    _shell._notify();
  }

  bool reopenClosedTab([String? id]) {
    if (!_shell.forumTabsEnabled || !canCreateTab) return false;
    final instance = _shell.currentInstance;
    final workspace = _shell.currentWorkspace;
    if (instance == null || workspace == null) return false;

    for (var index = _closedForumTabs.length - 1; index >= 0; index--) {
      final closed = _closedForumTabs[index];
      if (closed.siteUrl != workspace.siteUrl ||
          closed.accountIdentity != workspace.accountIdentity ||
          (id != null && closed.tab.id != id)) {
        continue;
      }
      _closedForumTabs.removeAt(index);
      if (workspace.tabById(closed.tab.id) != null) continue;

      final tabs = List<ForumTab>.of(workspace.tabs);
      tabs.insert(closed.index.clamp(0, tabs.length), closed.tab);
      put(workspace.copyWith(tabs: tabs, activeTabId: closed.tab.id));
      _shell._mobilePane = MobilePane.content;
      _shell._syncTopicChannels();
      _shell._notify();
      _shell._hydrateActiveTab(instance);
      return true;
    }
    return false;
  }

  void _rememberClosedForumTab({
    required String siteUrl,
    required String accountIdentity,
    required ForumTab tab,
    required int index,
  }) {
    if (tab.currentContent.isNewTab) return;
    _closedForumTabs.removeWhere(
      (closed) =>
          closed.siteUrl == siteUrl &&
          closed.accountIdentity == accountIdentity &&
          closed.tab.id == tab.id,
    );
    _closedForumTabs.add((
      siteUrl: siteUrl,
      accountIdentity: accountIdentity,
      tab: tab,
      index: index,
    ));
    if (_closedForumTabs.length > ForumWorkspace.maximumTabs) {
      _closedForumTabs.removeAt(0);
    }
  }

  void closeOtherTabs(String id, {bool? reading, ForumPanel? panel}) {
    if (!_shell.forumTabsEnabled) return;
    final instance = _shell.currentInstance;
    final workspace = _shell.currentWorkspace;
    if (instance == null || workspace == null || workspace.tabs.length == 1) {
      return;
    }
    final kept = workspace.tabById(id);
    if (kept == null) return;

    final reverseReopenOrder = workspace.tabs.indexed.toList().reversed;
    for (final (index, tab) in reverseReopenOrder) {
      if (tab.id == id ||
          (panel != null
              ? tab.panel != panel
              : reading != null && tab.currentContent.isTopic != reading)) {
        continue;
      }
      _rememberClosedForumTab(
        siteUrl: workspace.siteUrl,
        accountIdentity: workspace.accountIdentity,
        tab: tab,
        index: index,
      );
    }
    final activeChanged = workspace.activeTabId != id;
    final remaining = [
      for (final tab in workspace.tabs)
        if (tab.id == id ||
            (panel != null
                ? tab.panel != panel
                : reading != null && tab.currentContent.isTopic != reading))
          tab,
    ];
    for (final panel in ForumPanel.values) {
      if (workspace.tabsIn(panel).isNotEmpty &&
          !remaining.any((tab) => tab.panel == panel)) {
        remaining.add(_newDefaultTab().copyWith(panel: panel));
      }
    }
    put(workspace.copyWith(tabs: remaining, activeTabId: id));
    if (activeChanged) {
      _shell._syncTopicChannels();
      _shell._hydrateActiveTab(instance);
    }
    _shell._notify();
  }

  bool activatePluginPane(PluginId owner) {
    if (_shell.mobileNavigationEnabled || _shell.desktopPanelsEnabled) {
      return false;
    }
    final instance = _shell.currentInstance;
    var tab = _shell.activeTab;
    if (instance == null || tab == null) return false;

    var stateKey = (siteUrl: instance.url, tabId: tab.id);
    var activeOwner = _activePluginPanes[stateKey];
    if (activeOwner == null &&
        tab.currentContent.destination is ExtensionDestination) {
      final currentRouteId = tab.currentContent.id;
      final restoredPolicy = _shell._pluginSession
          .capabilities<PluginPaneRoutePolicy>()
          .where(
            (policy) =>
                policy.ownsPluginPaneRoute(currentRouteId) &&
                policy.separatesPluginPane(currentRouteId),
          )
          .firstOrNull;
      if (restoredPolicy != null) {
        activeOwner = restoredPolicy.pluginPaneOwner;
        _activePluginPanes[stateKey] = activeOwner;
      }
    }
    if (activeOwner == owner) {
      return !_coldPluginPanes.contains(stateKey);
    }
    if (activeOwner != null) {
      _deactivatePluginPane(activeOwner, notifyAndHydrate: false);
      tab = _shell.activeTab;
      if (tab == null) return false;
      stateKey = (siteUrl: instance.url, tabId: tab.id);
    }
    final key = (siteUrl: instance.url, tabId: tab.id, owner: owner);
    _activePluginPanes[stateKey] = owner;
    _mainPaneTabs[key] = tab;
    final pluginTab = _pluginPaneTabs[key];
    if (pluginTab == null) {
      _coldPluginPanes.add(stateKey);
      return false;
    }

    _coldPluginPanes.remove(stateKey);
    _restorePluginPaneTab(instance, pluginTab);
    return true;
  }

  void deactivatePluginPane(PluginId owner) {
    if (_shell.mobileNavigationEnabled) {
      _shell.handleBack();
      return;
    }
    if (_shell.desktopPanelsEnabled) {
      final instance = _shell.currentInstance;
      final active = _shell.activeTab;
      if (instance == null || active == null) return;
      final policies = _shell._pluginSession
          .capabilities<PluginPaneRoutePolicy>();
      final source = _shell.tabsForCurrentForum.reversed
          .where(
            (tab) =>
                tab.panel == _shell.activeTab?.panel &&
                (tab.currentContent.destination is! ExtensionDestination ||
                    policies.every(
                      (policy) =>
                          !policy.ownsPluginPaneRoute(tab.currentContent.id),
                    )),
          )
          .firstOrNull;
      replaceActiveTab(
        active.navigate(
          rootDestinationId:
              source?.rootDestinationId ?? instance.defaultDestination.id,
          contentStack: [
            source?.currentContent ?? _shell._homepageFor(instance),
          ],
        ),
      );
      _shell._mobilePane = MobilePane.content;
      _shell._syncTopicChannels();
      _shell._notify();
      _shell._hydrateActiveTab(instance);
      return;
    }
    _deactivatePluginPane(owner, notifyAndHydrate: true);
  }

  void _deactivatePluginPane(PluginId owner, {required bool notifyAndHydrate}) {
    final instance = _shell.currentInstance;
    final tab = _shell.activeTab;
    if (instance == null || tab == null) return;

    final stateKey = (siteUrl: instance.url, tabId: tab.id);
    final activeOwner = _activePluginPanes[stateKey];
    if (activeOwner != null && activeOwner != owner) return;
    _activePluginPanes.remove(stateKey);
    final wasCold = _coldPluginPanes.remove(stateKey);
    final key = (siteUrl: instance.url, tabId: tab.id, owner: owner);
    if (!wasCold) _pluginPaneTabs[key] = tab;
    final mainTab =
        _mainPaneTabs.remove(key) ??
        ForumTab(
          id: tab.id,
          rootDestinationId: instance.defaultDestination.id,
          contentStack: [_shell._homepageFor(instance)],
        );
    _restorePluginPaneTab(
      instance,
      mainTab,
      notifyAndHydrate: notifyAndHydrate,
    );
  }

  bool preparePluginPaneForRoute(ContentRoute route) {
    final routeId = route.id;
    final isExtension = route.destination is ExtensionDestination;
    if (_shell.mobileNavigationEnabled || _shell.desktopPanelsEnabled) {
      return false;
    }
    final instance = _shell.currentInstance;
    final tab = _shell.activeTab;
    if (instance == null || tab == null) return false;

    final stateKey = (siteUrl: instance.url, tabId: tab.id);
    final policies = _shell._pluginSession
        .capabilities<PluginPaneRoutePolicy>()
        .toList(growable: false);
    var owner = _activePluginPanes[stateKey];
    if (owner == null &&
        tab.currentContent.destination is ExtensionDestination) {
      final currentRouteId = tab.currentContent.id;
      final currentPolicy = policies
          .where(
            (policy) =>
                policy.ownsPluginPaneRoute(currentRouteId) &&
                policy.separatesPluginPane(currentRouteId),
          )
          .firstOrNull;
      if (currentPolicy != null) {
        owner = currentPolicy.pluginPaneOwner;
        _activePluginPanes[stateKey] = owner;
      }
    }

    if (owner != null) {
      final staysInPane =
          isExtension &&
          policies.any(
            (policy) =>
                policy.pluginPaneOwner == owner &&
                policy.ownsPluginPaneRoute(routeId) &&
                policy.separatesPluginPane(routeId),
          );
      if (staysInPane) return _coldPluginPanes.remove(stateKey);
      _deactivatePluginPane(owner, notifyAndHydrate: false);
    }

    final targetPolicy = isExtension
        ? policies
              .where(
                (policy) =>
                    policy.ownsPluginPaneRoute(routeId) &&
                    policy.separatesPluginPane(routeId),
              )
              .firstOrNull
        : null;
    if (targetPolicy != null) {
      activatePluginPane(targetPolicy.pluginPaneOwner);
      return _coldPluginPanes.remove(stateKey);
    }
    return false;
  }

  void _restorePluginPaneTab(
    DiscourseInstance instance,
    ForumTab tab, {
    bool notifyAndHydrate = true,
  }) {
    _shell._setForumContentRoot();
    replaceActiveTab(tab);
    _shell._mobilePane = MobilePane.content;
    _shell._syncTopicChannels();
    if (notifyAndHydrate) {
      _shell._notify();
      _shell._hydrateActiveTab(instance);
    }
  }

  List<ForumTab> get recentlyClosed {
    final workspace = _shell.currentWorkspace;
    if (workspace == null) return const [];
    final openIds = {for (final tab in workspace.tabs) tab.id};
    return List.unmodifiable([
      for (final closed in _closedForumTabs.reversed)
        if (closed.siteUrl == workspace.siteUrl &&
            closed.accountIdentity == workspace.accountIdentity &&
            !openIds.contains(closed.tab.id))
          closed.tab,
    ]);
  }
}
