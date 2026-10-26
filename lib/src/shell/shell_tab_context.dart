part of 'shell_controller.dart';

final class ShellTabContext {
  ShellTabContext._(this.shell, this.tabId)
    : siteUrl = shell.currentInstance?.url,
      accountIdentity = shell.currentAccountIdentity,
      lease = shell.currentInstance == null
          ? null
          : shell.lifecycle.capture(shell.currentInstance!.url) {
    _reader =
        tabId != null &&
            lease != null &&
            shell.currentWorkspace?.tabById(tabId!) != null
        ? shell._readerProjections.forTab(siteUrl!, tabId!, lease!)
        : null;
  }

  final ShellController shell;
  final String? tabId;
  final String? siteUrl;
  final String? accountIdentity;
  final SiteLease? lease;
  late final TopicReaderProjection? _reader;

  bool get isCurrent =>
      !shell._tabContextDisposed &&
      tabId != null &&
      shell.currentInstance?.url == siteUrl &&
      shell.currentAccountIdentity == accountIdentity &&
      lease?.isCurrent == true &&
      _reader?.isCurrent == true &&
      shell.currentWorkspace?.tabById(tabId!) != null;
  ForumTab? get tab =>
      isCurrent ? shell.currentWorkspace?.tabById(tabId!) : null;
  ForumTab? get activeTab => tab;
  String? get activeTabId => tab?.id;
  DiscourseInstance? get _instance => isCurrent ? shell.currentInstance : null;

  ContentRoute? get currentContent => activeTab?.currentContent;

  UserDirectoryQuery get usersQuery => siteUrl == null || !isCurrent
      ? const UserDirectoryQuery()
      : shell.search.usersQueryFor(siteUrl!, tabId);

  void setUsersSearch(String search) =>
      _replaceUsersQuery(usersQuery.copyWith(search: search));

  void setUsersPeriod(UserDirectoryPeriod period) =>
      _replaceUsersQuery(usersQuery.copyWith(period: period));

  void setUsersGroup(String? group) =>
      _replaceUsersQuery(usersQuery.copyWith(group: group));

  void setUsersOrder(String order, bool ascending) => _replaceUsersQuery(
    usersQuery.copyWith(order: order, ascending: ascending),
  );

  void _replaceUsersQuery(UserDirectoryQuery query) {
    if (!isCurrent || currentContent?.isUsers != true) return;
    if (shell.search.replaceUsersQuery(siteUrl!, tabId, query)) {
      unawaited(loadUsers());
    }
  }

  Future<void> loadUsers({bool refresh = false, bool more = false}) async {
    final instance = _instance;
    if (instance == null || !contentStack.any((route) => route.isUsers)) return;
    await shell.userDirectory.load(
      instance,
      query: usersQuery,
      refresh: refresh,
      more: more,
    );
  }

  List<ContentRoute> get contentStack => activeTab?.contentStack ?? const [];

  ForumTab? get topicListTab => activeTab;

  ContentRoute? get topicListContent {
    final routes = topicListTab?.contentStack ?? const <ContentRoute>[];
    for (final route in routes.reversed) {
      if (route.isTopic) continue;
      return route.isTopicList ? route : null;
    }
    return null;
  }

  String? get currentFeedId {
    final route = currentContent?.isTopic == true
        ? topicListContent ?? currentContent
        : currentContent;
    if (route?.isMessages == true) return route!.id;
    if (route != null &&
        (route.feedPath != null || TopicListMode.fromRoute(route) != null)) {
      return route.id;
    }
    return topicListTab?.rootDestinationId;
  }

  TopicFeed? get currentFeed {
    final instance = _instance;
    final feedId = currentFeedId;
    if (instance == null || feedId == null) return null;
    final feed = shell.topicFeeds.feedFor(instance.url, feedId);
    if (feed == null || !currentFeedIsUnread) return feed;
    // The topic being read may sit in the other desktop panel.
    return shell._unreadTopicFeed.project(
      feed,
      selectedTopicId: readingTopicId,
      isRead: (id) => UnreadTopicFeed.isRead(
        topic: shell.store.read<Topic>(instance.url, id),
        tracking: shell._topicTracking
            .existing(instance.url)
            ?.reconciler
            .topic(id),
        localReadPostNumber: shell._topicReads.lastReadPostNumberFor(
          instance.url,
          id,
        ),
      ),
    );
  }

  bool get currentFeedIsUnread {
    // Core serves personal and group Unread folders through the same unread
    // filter as /unread, so a message read here leaves them the same way.
    final route = topicListContent ?? topicListTab?.currentContent;
    if (route?.isMessages == true) {
      return route!.messageListMode == MessageListMode.unread;
    }
    return switch (currentTopicListMode) {
      TopicListMode.unread || TopicListMode.newReplies => true,
      _ => false,
    };
  }

  TopicListMode? get currentTopicListMode {
    final tab = topicListTab;
    if (tab == null) return null;

    final route = topicListContent ?? tab.currentContent;
    final mode = TopicListMode.fromRoute(route);
    if (mode != null) return mode;
    if (tab.rootDestinationId != 'latest' &&
        route.categoryId == null &&
        route.tagName == null) {
      return null;
    }
    return route.isTopicListFilter ? TopicListMode.latest : null;
  }

  int? get readingTopicId {
    if (!isCurrent) return null;
    if (!shell.desktopTopicTabs) return currentContent?.topicId;
    final source = activeTab;
    if (source?.currentContent.isTopic == true) {
      return source!.currentContent.topicId;
    }
    final other = source?.panel == ForumPanel.secondary
        ? ForumPanel.main
        : ForumPanel.secondary;
    return shell.selectedTabIn(other)?.currentContent.topicId;
  }

  ({int all, int topics, int replies}) get topicListNewCounts {
    if (!isCurrent) return (all: 0, topics: 0, replies: 0);
    final route = topicListContent ?? currentContent;
    final categoryId = route?.categoryId;
    final tagNames = route?.tagNames ?? const <String>[];
    if (categoryId == null && tagNames.isEmpty) return shell._forumNewCounts;

    final instance = _instance;
    if (instance == null ||
        instance.user == null ||
        shell._topicTracking.existing(instance.url)?.reconciler.hasSnapshot !=
            true) {
      return (all: 0, topics: 0, replies: 0);
    }
    final tracking = shell._topicTracking.existing(instance.url)?.reconciler;
    if (tracking == null) return (all: 0, topics: 0, replies: 0);

    final tagIds = <int>{};
    for (final name in tagNames) {
      final tag = shell._taxonomy.knownTopicListTag(instance.url, name);
      // An unresolved tag cannot use the unfiltered forum total.
      if (tag == null || tag.pmOnly) return (all: 0, topics: 0, replies: 0);
      tagIds.add(tag.id);
    }

    final counts = tracking.newActivityCountsFor(
      categoryId: categoryId,
      categories: shell.filterCategoriesFor(instance.url),
      tagIds: tagIds,
    );
    return (
      all:
          counts.newTopics +
          (instance.user!.unifiedNewEnabled ? counts.newReplies : 0),
      topics: counts.newTopics,
      replies: counts.newReplies,
    );
  }

  bool get canCreateTopicHere {
    if (currentContent?.isTopic != false ||
        currentContent?.isPreferences == true ||
        currentContent?.isAppearance == true ||
        currentContent?.isMessages == true) {
      return false;
    }
    final instance = _instance;
    if (currentContent?.isPage(CorePage.categories) == true &&
        instance != null) {
      return shell.categoryFeedFor(instance.url).canCreateTopic;
    }
    return currentFeed?.canCreateTopic ?? false;
  }

  bool get canCreateTopicFromList =>
      topicListContent != null && currentFeed?.canCreateTopic == true;

  bool get canPopContent =>
      isCurrent &&
      (shell.mobileNavigationEnabled
          ? shell.mobileNavigation.canGoBack
          : activeTab?.canGoBack ?? false);

  bool get canReplyHere => currentTopic?.canCreatePost ?? false;

  TopicDetail? get currentTopic {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return null;
    return shell.store.read<TopicDetail>(instance.url, topicId);
  }

  List<int> get currentPostIds => _currentPostWindow().ids;

  List<int> get currentTopicStreamIds {
    final instance = _instance;
    final detail = currentTopic;
    if (instance == null || detail == null) return const [];
    return shell._topicData.forSite(instance.url).streamFor(detail);
  }

  /// The current topic's last read post, including reads this session has
  /// credited since its detail was fetched.
  int? get currentTopicLastReadPostNumber {
    final instance = _instance;
    final detail = currentTopic;
    if (instance == null || detail == null) return null;
    return detail.lastReadAfter(
      shell._topicReads.lastReadPostNumberFor(instance.url, detail.id),
    );
  }

  bool get currentTopicSummary {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._topicData.forSite(instance.url).showingSummary(topicId);
  }

  bool get currentTopicSummaryLoading {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._topicData.forSite(instance.url).summaryLoading(topicId);
  }

  bool get currentTopicHasMore {
    final window = _currentPostWindow();
    final range = window.range;
    return range == null
        ? window.stream.isNotEmpty
        : range.$2 + 1 < window.stream.length ||
              _currentMegaTopicEdge(newer: true) != null;
  }

  bool get currentTopicHasEarlier {
    final range = _currentPostWindow().range;
    return range != null &&
        (range.$1 > 0 || _currentMegaTopicEdge(newer: false) != null);
  }

  bool get currentTopicLoading {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._topicData.forSite(instance.url).loading(topicId);
  }

  bool get loadingMorePosts {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._topicData.forSite(instance.url).paging(topicId, newer: true);
  }

  bool get loadingEarlierPosts {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._topicData.forSite(instance.url).paging(topicId, newer: false);
  }

  int get topicNavigationRevision =>
      shell._topicNavigation.revisionFor(activeTabId);

  ContentRoute? get sidebarFilterRoute {
    if (shell.mobileNavigationEnabled && shell.mobileNavigation.atRoot) {
      return null;
    }
    final source = topicListContent;
    if (source?.isTopicListFilter != true || source?.isMessages == true) {
      return null;
    }
    return currentContent?.isTopic == true ||
            currentContent?.isTopicListFilter == true
        ? source
        : null;
  }

  TopicCategory? get sidebarCategoryBase {
    final selected = shell.categoryFor(sidebarFilterRoute?.categoryId);
    if (selected == null) return null;
    final categories = shell.filterCategoriesFor(_instance!.url);
    return categories.any((item) => item.parentCategoryId == selected.id)
        ? selected
        : shell.categoryFor(selected.parentCategoryId);
  }

  TopicReaderWindow _currentPostWindow() {
    final instance = _instance;
    final detail = currentTopic;
    if (instance == null || detail == null) {
      return TopicReaderProjection.emptyWindow;
    }
    return _reader!.project(
      shell._topicData.forSite(instance.url).streamFor(detail),
      currentContent?.postNumber,
    );
  }

  int? initialPostIndexFor(
    List<int> postIds,
    int target, {
    required bool hasEarlier,
  }) => isCurrent
      ? _reader!.initialIndex(postIds, target, hasEarlier: hasEarlier)
      : null;

  Post? _currentMegaTopicEdge({required bool newer}) {
    final detail = currentTopic;
    if (detail == null) return null;
    return _reader!.megaEdge(_currentPostWindow(), detail, newer: newer);
  }

  Future<void> loadFeed(String destinationId, {bool force = false}) async {
    if (!isCurrent) return;
    await shell.loadFeed(destinationId, force: force, context: this);
  }

  Future<void> loadMoreFeed(String destinationId) async {
    if (!isCurrent) return;
    await shell.loadMoreFeed(destinationId);
  }

  Future<void> loadTopic(
    int topicId,
    String slug, {
    bool force = false,
    int? postNumber,
  }) async {
    if (!isCurrent) return;
    await shell.loadTopic(
      topicId,
      slug,
      force: force,
      postNumber: postNumber,
      context: this,
    );
  }

  Future<void> loadMorePosts({int batchSize = 20}) async {
    if (!isCurrent) return;
    await shell.loadMorePosts(batchSize: batchSize, tabId: tabId);
  }

  Future<void> loadEarlierPosts({int batchSize = 20}) async {
    if (!isCurrent) return;
    await shell.loadEarlierPosts(batchSize: batchSize, tabId: tabId);
  }

  Future<void> ensureFeedRange(
    String destinationId, {
    required int firstRow,
    required int lastRow,
  }) async {
    final instance = _instance;
    if (instance == null) return;
    await shell.topicFeeds.ensureRange(
      instance: instance,
      destinationId: destinationId,
      firstRow: firstRow,
      lastRow: lastRow,
    );
  }

  Future<Topic?> restoreFeedTopic(String destinationId, int topicId) async {
    final instance = _instance;
    if (instance == null) return null;
    return shell.topicFeeds.restoreTopic(
      instance: instance,
      destinationId: destinationId,
      topicId: topicId,
    );
  }

  Future<void> selectTopicListMode(
    TopicListMode mode, {
    bool keepTopicOpen = false,
  }) => _transitionTopicList(
    SelectTopicListMode(mode, keepTopicOpen: keepTopicOpen),
  );

  Future<void> sortTopicList(String column) =>
      _transitionTopicList(SortTopicList(column));

  void selectTopicListCategory(
    TopicCategory? category, {
    bool keepTopicOpen = false,
  }) => unawaited(
    _transitionTopicList(
      SelectTopicListCategory(category, keepTopicOpen: keepTopicOpen),
    ),
  );

  void selectTopicListTag(String? tagName, {bool keepTopicOpen = false}) =>
      selectTopicListTags([?tagName], keepTopicOpen: keepTopicOpen);

  void selectTopicListTags(List<String> tags, {bool keepTopicOpen = false}) =>
      unawaited(
        _transitionTopicList(
          SelectTopicListTags(tags, keepTopicOpen: keepTopicOpen),
        ),
      );

  TopicListTransitions? get _topicListTransitions {
    final instance = _instance;
    final tab = activeTab;
    if (instance == null || tab == null) return null;
    final source = topicListContent;
    final categories = shell.filterCategoriesFor(instance.url);
    return TopicListTransitions(
      tab: tab,
      source: source,
      mode: currentTopicListMode,
      sidebarSource: sidebarFilterRoute,
      categories: categories,
      canonicalCategories: {
        for (final id in {
          for (final category in categories) category.id,
          ?source?.categoryId,
        })
          id: ?shell.categoryFor(id, siteUrl: instance.url),
      },
      resolvedTags: shell._topicListFilterTagNames(instance.url, source),
      signedIn: instance.user != null,
      unifiedNewEnabled: instance.user?.unifiedNewEnabled == true,
      desktopPanelsEnabled: shell.desktopPanelsEnabled,
      mobileNavigationEnabled: shell.mobileNavigationEnabled,
    );
  }

  Future<void> _transitionTopicList(TopicListCommand command) async {
    final plan = _topicListTransitions?.plan(command);
    if (plan == null) return;
    _publishTopicListTransition(plan);
    shell._syncTopicChannels();
    shell._notify();
    await loadFeed(plan.route.id);
  }

  void _publishTopicListTransition(TopicListTransition plan) {
    if (plan.presentation == TopicListPresentation.scopeList ||
        plan.presentation == TopicListPresentation.sidebar) {
      shell._showMobileScopeList();
    }
    shell._workspace.consumeHomepage(plan.replacement.id);
    shell._workspace.replaceTab(siteUrl!, plan.replacement);
    if (plan.mobileLocation case final location?) {
      shell.mobileNavigation.replaceCurrent(location);
    }
    if (plan.presentation == TopicListPresentation.content ||
        plan.presentation == TopicListPresentation.sidebar) {
      shell._mobilePane = MobilePane.content;
    }
  }

  void _replaceTopicListContent(
    ContentRoute route, {
    required bool keepTopicOpen,
  }) {
    final tab = activeTab;
    if (tab == null) return;
    _publishTopicListTransition(
      TopicListTransition.replace(
        tab: tab,
        route: route,
        keepTopicOpen: keepTopicOpen,
        desktopPanelsEnabled: shell.desktopPanelsEnabled,
        mobileNavigationEnabled: shell.mobileNavigationEnabled,
      ),
    );
  }

  Future<void> applyTopicListFilterQuery(String query) =>
      _transitionTopicList(ApplyTopicListFilterQuery(query));

  Future<void> submitTopicFilter(String query) =>
      _transitionTopicList(SubmitTopicListFilter(query));

  Future<String?> dismissNewTopics() async {
    final scope = _dismissNewScope;
    if (scope == null) return null;
    return switch (await shell._newTopicDismissals.dismiss(scope)) {
      null => null,
      DismissNewTopicsFailure.reconnect => appL10n.reconnectToDismissNewTopics,
      DismissNewTopicsFailure.failed =>
        appL10n.couldNotDismissNewTopicsPleaseTryAgain,
    };
  }

  bool get canDismissNewTopics => _dismissNewScope != null;

  DismissNewTopicsCommand? get _dismissNewScope {
    final instance = _instance;
    final route = topicListContent;
    final mode = currentTopicListMode;
    final feed = currentFeed;
    if (instance == null ||
        route == null ||
        mode == null ||
        !instance.isConnected ||
        (mode != TopicListMode.newActivity &&
            mode != TopicListMode.newTopics &&
            mode != TopicListMode.newReplies) ||
        feed == null ||
        feed.topicIds.isEmpty) {
      return null;
    }
    // Core matches reset-new's tag_name case-sensitively and widens an
    // unknown tag to the category or forum. Only a listed topic's exact
    // spelling is safe, even though the list matched case-insensitively.
    final requested = route.tagNames.firstOrNull?.toLowerCase();
    String? tagName;
    if (requested != null) {
      for (final id in feed.topicIds) {
        final topic = shell.store.read<Topic>(instance.url, id);
        for (final tag in topic?.tags ?? const <TopicTag>[]) {
          if (tag.name.toLowerCase() == requested) {
            tagName = tag.name;
            break;
          }
        }
        if (tagName != null) break;
      }
      if (tagName == null) return null;
    }
    final command = DismissNewTopicsCommand(
      instance: instance,
      route: route,
      mode: mode,
      tagName: tagName,
    );
    if (command.listsTopicIds && command.widensToForum) return null;
    return command;
  }

  TabOpenResult openTopicFromList(Topic topic, {bool revealInList = false}) {
    if (!isCurrent) return TabOpenResult.unsupported;
    final result = shell._openTopic(
      topic.id,
      topic.slug,
      topic.title,
      context: this,
      postNumber: topic.lastUnreadPostNumber,
      replace: currentContent?.isTopic == true && topicListContent != null,
    );
    if (revealInList && result == TabOpenResult.opened) {
      shell._topicListRevealRequests.add(topic.id);
    }
    return result;
  }

  bool get dismissingNewTopics => isCurrent && shell.dismissingNewTopics;

  bool get canForwardContent =>
      isCurrent &&
      (shell.mobileNavigationEnabled
          ? shell.mobileNavigation.canGoForward
          : tab?.canGoForward ?? false);

  bool get canRefreshCurrentTab =>
      isCurrent &&
      shell.loaded &&
      (!shell.currentInstance!.loginRequired ||
          shell.currentInstance!.isConnected);

  (ShellRootMode, String?, String?, String?) get _refreshKey =>
      (shell.rootMode, siteUrl, accountIdentity, tabId);

  bool get refreshingCurrentTab =>
      isCurrent && shell._refreshingTabs.contains(_refreshKey);

  Future<void> refreshTab() async {
    if (!canRefreshCurrentTab) return;
    final key = _refreshKey;
    if (!shell._refreshingTabs.add(key)) return;
    shell._notify();
    try {
      await (shell._contentRefreshers[tabId]?.call() ??
          shell._refreshCurrentContent(this));
    } catch (_) {
    } finally {
      shell._refreshingTabs.remove(key);
      if (!shell._tabContextDisposed) shell._notify();
    }
  }

  bool handleBack({bool canReturnToSidebar = true}) {
    if (!isCurrent) return false;
    if (shell.mobileNavigationEnabled) {
      if (shell.mobileNavigation.closeSidebar()) {
        shell._notify();
        return true;
      }
      if (!shell.mobileNavigation.goBack()) return false;
      shell._restoreMobileLocation();
      return true;
    }
    if (canPopContent) {
      final tab = activeTab!;
      shell._workspace.replaceTab(siteUrl!, tab.goBack());
      shell._syncTopicChannels();
      shell._notify();
      if (_instance case final instance?) shell._hydrateTab(instance, this);
      return true;
    }
    if (canReturnToSidebar && shell._mobilePane == MobilePane.content) {
      shell._mobilePane = MobilePane.sidebar;
      shell._notify();
      return true;
    }
    return false;
  }

  bool handleForward() {
    if (!isCurrent) return false;
    if (shell.mobileNavigationEnabled) {
      if (!shell.mobileNavigation.goForward()) {
        return false;
      }
      shell._restoreMobileLocation();
      return true;
    }
    final tab = activeTab;
    if (shell._rootMode != ShellRootMode.forum || tab?.canGoForward != true) {
      return false;
    }
    shell._workspace.replaceTab(siteUrl!, tab!.goForward());
    shell._mobilePane = MobilePane.content;
    shell._syncTopicChannels();
    shell._notify();
    if (_instance case final instance?) shell._hydrateTab(instance, this);
    return true;
  }

  void openReply({
    int? replyToPostNumber,
    String? replyToUsername,
    bool? replyingToWhisper,
  }) {
    shell.openReply(
      context: this,
      replyToPostNumber: replyToPostNumber,
      replyToUsername: replyToUsername,
      replyingToWhisper: replyingToWhisper,
    );
  }

  Future<void> openQuote(Post post, String quote) =>
      shell.openQuote(post, quote, context: this);

  void openEdit(Post post, {String? focusText}) =>
      shell.openEdit(post, focusText: focusText, context: this);

  void openTagsEdit() => shell.openTagsEdit(context: this);

  void closeTopicListReader() {
    if (!isCurrent) return;
    if (shell.mobileNavigationEnabled) {
      if (currentContent?.isTopic == true) handleBack();
      return;
    }
    final active = activeTab;
    if (active != null && shell._readerClosesTab(active)) {
      shell.closeTab(active.id);
      return;
    }
    if (active == null ||
        topicListContent == null ||
        !active.currentContent.isTopic) {
      return;
    }
    shell._workspace.replaceTab(siteUrl!, shell._closeTopicRoute(active));
    shell._syncTopicChannels();
    shell._notify();
    if (_instance case final instance?) shell._hydrateTab(instance, this);
  }

  void selectMessageInbox(String? groupName, {bool keepTopicOpen = false}) {
    final instance = _instance;
    final route = topicListContent ?? currentContent;
    final user = instance?.user;
    if (instance == null || user == null || route?.isMessages != true) return;

    final group = groupName?.trim();
    if (group != null && !user.messageGroupNames.contains(group)) return;

    final mode = route!.messageListMode;
    final replacement = ContentRoute.messages(
      groupName: group,
      mode: group == null || mode.supportsGroup ? mode : MessageListMode.inbox,
    );
    if (route.sameDestinationAs(replacement)) return;
    _replaceTopicListContent(replacement, keepTopicOpen: keepTopicOpen);
    shell._syncTopicChannels();
    shell._notify();
    unawaited(loadFeed(replacement.id));
  }
}
