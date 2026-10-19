part of 'shell_controller.dart';

final class ShellTabContext {
  ShellTabContext._(this.shell, this.tabId)
    : siteUrl = shell.currentInstance?.url,
      accountIdentity = shell.currentAccountIdentity,
      lease = shell.currentInstance == null
          ? null
          : shell.lifecycle.capture(shell.currentInstance!.url);

  final ShellController shell;
  final String? tabId;
  final String? siteUrl;
  final String? accountIdentity;
  final SiteLease? lease;

  bool get isCurrent =>
      !shell._tabContextDisposed &&
      tabId != null &&
      shell.currentInstance?.url == siteUrl &&
      shell.currentAccountIdentity == accountIdentity &&
      lease?.isCurrent == true &&
      shell.currentWorkspace?.tabById(tabId!) != null;
  ForumTab? get tab =>
      isCurrent ? shell.currentWorkspace?.tabById(tabId!) : null;
  ForumTab? get activeTab => tab;
  String? get activeTabId => tab?.id;
  DiscourseInstance? get _instance => isCurrent ? shell.currentInstance : null;

  ContentRoute? get currentContent => activeTab?.currentContent;

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
        tracking: shell._topicTrackingBySite[instance.url]?.topic(id),
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
        shell._topicTrackingBySite[instance.url]?.hasSnapshot != true) {
      return (all: 0, topics: 0, replies: 0);
    }
    final tracking = shell._topicTrackingBySite[instance.url];
    if (tracking == null) return (all: 0, topics: 0, replies: 0);

    final tagIds = <int>{};
    for (final name in tagNames) {
      final normalized = name.toLowerCase();
      final tag = shell
          ._knownTagsFor(instance.url)
          .where(
            (tag) =>
                tag.name.toLowerCase() == normalized ||
                tag.slug.toLowerCase() == normalized,
          )
          .firstOrNull;
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
    return shell._topicStream(instance.url, detail);
  }

  bool get currentTopicSummary {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._topicSummaryStreams.containsKey(
      ShellController._topicKey(instance.url, topicId),
    );
  }

  bool get currentTopicSummaryLoading {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._topicSummariesLoading.contains(
      ShellController._topicKey(instance.url, topicId),
    );
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
    return shell._topicsLoading.contains(
      ShellController._topicKey(instance.url, topicId),
    );
  }

  bool get loadingMorePosts {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._postsLoading.contains(
      ShellController._topicKey(instance.url, topicId),
    );
  }

  bool get loadingEarlierPosts {
    final instance = _instance;
    final topicId = currentContent?.topicId;
    if (instance == null || topicId == null) return false;
    return shell._earlierPostsLoading.contains(
      ShellController._topicKey(instance.url, topicId),
    );
  }

  int get topicNavigationRevision =>
      shell._topicNavigationRevisions[activeTabId] ?? 0;

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

  _PostWindow _currentPostWindow() {
    final instance = _instance;
    final detail = currentTopic;
    if (instance == null || detail == null) {
      return ShellController._emptyPostWindow;
    }
    final stream = shell._topicStream(instance.url, detail);
    final key = (
      instance.url,
      detail,
      stream,
      currentContent?.postNumber,
      shell.store.generationOf<Post>(instance.url),
    );
    final cacheId = (instance.url, activeTabId);
    final cachedKey = shell._postWindowCacheKeys[cacheId];
    if (cachedKey != null &&
        cachedKey.$1 == key.$1 &&
        identical(cachedKey.$2, key.$2) &&
        identical(cachedKey.$3, key.$3) &&
        cachedKey.$4 == key.$4 &&
        cachedKey.$5 == key.$5) {
      return shell._postWindowCaches[cacheId]!;
    }
    final range = _loadedPostRange(instance.url, detail, stream: stream);
    shell._postWindowCacheKeys[cacheId] = key;
    return shell._postWindowCaches[cacheId] = (
      stream: stream,
      range: range,
      ids: range == null
          ? const []
          : [for (final id in stream.sublist(range.$1, range.$2 + 1)) id],
    );
  }

  (int, int)? _loadedPostRange(
    String siteUrl,
    TopicDetail detail, {
    List<int>? stream,
  }) {
    final effectiveStream = stream ?? shell._topicStream(siteUrl, detail);
    if (effectiveStream.isEmpty) return null;

    final target = currentContent?.postNumber;
    var anchor = -1;
    if (target != null) {
      for (var i = 0; i < effectiveStream.length; i++) {
        final post = shell.store.read<Post>(siteUrl, effectiveStream[i]);
        if (post != null && post.postNumber >= target) {
          anchor = i;
          break;
        }
      }
    } else {
      anchor = effectiveStream.indexWhere(
        (id) => shell.store.read<Post>(siteUrl, id) != null,
      );
    }
    // A stale cache or a deliberately minimal test payload may not contain
    // the requested post yet. Keep showing the contiguous data in hand until
    // the around-post request lands instead of flashing an empty topic.
    if (anchor < 0 && target != null) {
      anchor = effectiveStream.indexWhere(
        (id) => shell.store.read<Post>(siteUrl, id) != null,
      );
    }
    if (anchor < 0) return null;

    var first = anchor;
    while (first > 0 &&
        shell.store.read<Post>(siteUrl, effectiveStream[first - 1]) != null) {
      first--;
    }
    var last = anchor;
    while (last + 1 < effectiveStream.length &&
        shell.store.read<Post>(siteUrl, effectiveStream[last + 1]) != null) {
      last++;
    }
    return (first, last);
  }

  List<int> _pendingEarlierPostIds(
    String siteUrl,
    TopicDetail detail,
    int batchSize,
  ) {
    final stream = shell._topicStream(siteUrl, detail);
    final range = _loadedPostRange(siteUrl, detail, stream: stream);
    if (range == null || range.$1 == 0) return const [];
    final start = range.$1 > batchSize ? range.$1 - batchSize : 0;
    return [
      for (final id in stream.sublist(start, range.$1))
        if (shell.store.read<Post>(siteUrl, id) == null) id,
    ];
  }

  Post? _currentMegaTopicEdge({required bool newer}) {
    final instance = _instance;
    final detail = currentTopic;
    if (instance == null || detail == null || !detail.isMegaTopic) return null;
    final window = _currentPostWindow();
    final stream = window.stream;
    final range = window.range;
    if (range == null || !identical(stream, detail.stream)) return null;
    if (newer) {
      if (range.$2 + 1 < stream.length ||
          stream[range.$2] == detail.lastPostId) {
        return null;
      }
      return shell.store.read<Post>(instance.url, stream[range.$2]);
    }
    if (range.$1 > 0) return null;
    final first = shell.store.read<Post>(instance.url, stream.first);
    return first != null && first.postNumber > 1 ? first : null;
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
  }) async {
    final instance = _instance;
    final user = instance?.user;
    final tab = activeTab;
    final currentMode = currentTopicListMode;
    if (instance == null || tab == null || currentMode == null) return;
    if (user == null &&
        (mode.isNew ||
            mode == TopicListMode.unread ||
            mode == TopicListMode.unseen)) {
      return;
    }
    if (mode.isSubset && user?.unifiedNewEnabled != true) return;
    if (mode == currentMode &&
        topicListContent?.isAdvancedTopicFilter != true) {
      return;
    }

    final source = topicListContent;
    final tags = shell._topicListFilterTagNames(instance.url, source);
    final route = shell
        ._topicListFilterRoute(
          siteUrl: instance.url,
          mode: mode,
          category: shell.categoryFor(source?.categoryId),
          tagName: tags.firstOrNull,
          tags: tags,
        )
        .withTopicListQueryFrom(
          source?.isAdvancedTopicFilter == true ? null : source,
        );
    _replaceTopicListContent(route, keepTopicOpen: keepTopicOpen);
    shell._mobilePane = MobilePane.content;
    shell._syncTopicChannels();
    shell._notify();
    await loadFeed(route.id);
  }

  Future<void> sortTopicList(String column) async {
    final source = topicListContent;
    if (_instance == null ||
        source?.canSortTopicList != true ||
        !ContentRoute.topicListSortColumns.contains(column)) {
      return;
    }
    final same = source!.topicListOrder == column;
    final route = source.withTopicListSort(
      same && source.topicListAscending ? null : column,
      ascending: same && !source.topicListAscending,
    );
    _replaceTopicListContent(route, keepTopicOpen: true);
    shell._syncTopicChannels();
    shell._notify();
    await loadFeed(route.id);
  }

  void selectTopicListCategory(
    TopicCategory? category, {
    bool keepTopicOpen = false,
  }) {
    final route = topicListContent;
    final siteUrl = _instance?.url;
    if (route?.isTopicListFilter != true || siteUrl == null) return;
    final tags = shell._topicListFilterTagNames(siteUrl, route);
    _selectTopicListFilter(
      category: category,
      tagName: tags.firstOrNull,
      tags: tags,
      keepTopicOpen: keepTopicOpen,
    );
  }

  void selectTopicListTag(String? tagName, {bool keepTopicOpen = false}) {
    final route = topicListContent;
    if (route?.isTopicListFilter != true) return;
    _selectTopicListFilter(
      category: shell.categoryFor(route!.categoryId),
      tagName: tagName,
      keepTopicOpen: keepTopicOpen,
    );
  }

  void selectTopicListTags(List<String> tags, {bool keepTopicOpen = false}) {
    final route = topicListContent;
    if (route?.isTopicListFilter != true) return;
    _selectTopicListFilter(
      category: shell.categoryFor(route!.categoryId),
      tagName: tags.firstOrNull,
      tags: tags,
      keepTopicOpen: keepTopicOpen,
    );
  }

  void _selectTopicListFilter({
    required TopicCategory? category,
    required String? tagName,
    List<String>? tags,
    bool keepTopicOpen = false,
  }) {
    final instance = _instance;
    final tab = activeTab;
    if (instance == null || tab == null) return;

    final normalizedTag = switch (tagName?.trim()) {
      final value? when value.isNotEmpty => value,
      _ => null,
    };
    final route = shell
        ._topicListFilterRoute(
          siteUrl: instance.url,
          category: category,
          tagName: normalizedTag,
          tags: tags,
          mode: currentTopicListMode ?? TopicListMode.latest,
        )
        .withTopicListQueryFrom(topicListContent);
    if (route.sameDestinationAs(topicListContent)) {
      return;
    }

    _replaceTopicListContent(route, keepTopicOpen: keepTopicOpen);
    shell._mobilePane = MobilePane.content;
    shell._syncTopicChannels();
    shell._notify();
    unawaited(loadFeed(route.id));
  }

  void _replaceTopicListContent(
    ContentRoute route, {
    required bool keepTopicOpen,
  }) {
    final tab = activeTab;
    if (tab == null) return;
    final sourceIndex = tab.contentStack.lastIndexWhere(
      (item) => !item.isTopic,
    );
    final retainReader =
        !shell.desktopPanelsEnabled &&
        keepTopicOpen &&
        tab.currentContent.isTopic &&
        sourceIndex >= 0 &&
        tab.contentStack[sourceIndex].isTopicList;
    shell._workspace.consumeHomepage(tab.id);
    shell._workspace.replaceTab(
      siteUrl!,
      tab.navigate(
        rootDestinationId: route.isMessages ? 'messages' : 'latest',
        contentStack: retainReader
            ? [
                ...tab.contentStack.take(sourceIndex),
                route,
                ...tab.contentStack.skip(sourceIndex + 1),
              ]
            : [route],
      ),
    );
    if (shell.mobileNavigationEnabled && tab.currentContent.isTopicList) {
      shell.mobileNavigation.replaceCurrent(
        tab
            .navigate(
              rootDestinationId: route.isMessages ? "messages" : "latest",
              contentStack: [route],
            )
            .location,
      );
    }
  }

  Future<void> applyTopicListFilterQuery(String query) async {
    final instance = _instance;
    if (instance == null) return;
    final scope = parseTopicFilterScope(
      query,
      shell.filterCategoriesFor(instance.url),
    );
    final tags = <String>[?scope.tag];
    final remainder = <String>[];
    for (final clause in splitTopicFilterQuery(scope.query)) {
      final match = RegExp(r'^tags?:(.*)$').firstMatch(clause);
      var value = match?.group(1) ?? '';
      if (value.length > 1 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      final conjunction = value.split('+');
      if (match != null &&
          !value.contains(',') &&
          conjunction.length > 1 &&
          conjunction.every((tag) => tag.trim().isNotEmpty)) {
        // Include-all tags are ordinary feed scope, so changing the feed
        // retains them just as it retains a single category or tag.
        tags.addAll(conjunction);
      } else {
        remainder.add(clause);
      }
    }
    final source = topicListContent;
    final route = remainder.isEmpty
        ? shell
              ._topicListFilterRoute(
                siteUrl: instance.url,
                category: shell.categoryFor(scope.categoryId),
                tagName: tags.firstOrNull,
                tags: tags,
                mode:
                    TopicListMode.fromRoute(sidebarFilterRoute) ??
                    TopicListMode.latest,
              )
              .withTopicListQueryFrom(
                source?.isAdvancedTopicFilter == true ? null : source,
              )
        : ContentRoute.topicFilter(
            remainder.join(' '),
            categoryId: scope.categoryId,
            tags: tags,
          );
    shell._showMobileScopeList();
    _replaceTopicListContent(
      route,
      keepTopicOpen: currentContent?.isTopic == true,
    );
    shell._syncTopicChannels();
    shell._notify();
    await loadFeed(route.id);
  }

  Future<String?> dismissNewTopics() async {
    final instance = _instance;
    final route = topicListContent;
    final mode = currentTopicListMode;
    final scope = _dismissNewScope;
    if (instance == null ||
        route == null ||
        mode == null ||
        scope == null ||
        shell.dismissingNewTopics) {
      return null;
    }
    final siteUrl = instance.url;
    final lease = shell.lifecycle.capture(siteUrl);
    final key = (siteUrl, lease.session);
    shell._dismissingNew.add(key);
    shell._notify();
    final topics = mode != TopicListMode.newReplies;
    final posts =
        instance.user?.unifiedNewEnabled == true &&
        mode != TopicListMode.newTopics;
    try {
      final credential = await AccountRequestSession(
        siteUrl,
        lease,
      ).credentials(shell.credentials);
      if (credential.apiKey == null || !lease.isCurrent) {
        return appL10n.reconnectToDismissNewTopics;
      }
      // Core accepts one tag. Resolve the full intersection before a bulk
      // write when this app's list has multiple tags.
      List<int>? topicIds;
      if (route.tagNames.length > 1) {
        topicIds = [];
        String? path = route.feedPath;
        final visited = <String>{};
        while (path != null && visited.add(path)) {
          final requestPath = path;
          final page = await credential.run(
            () => shell.api.topicFeeds.topicList(
              siteUrl: siteUrl,
              path: requestPath,
              apiKey: credential.apiKey,
              clientId: credential.clientId,
            ),
          );
          if (!lease.isCurrent || shell._tabContextDisposed) return null;
          topicIds.addAll(page.topics.map((topic) => topic.id));
          path = page.nextPagePath;
        }
        if (path != null) {
          throw StateError('Could not load all matching topics.');
        }
      }
      if (!lease.isCurrent || shell._tabContextDisposed) return null;
      final ids = await credential.run(
        () => shell.api.topicFeeds.dismissNewTopics(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          clientId: credential.clientId,
          dismissTopics: topics,
          dismissPosts: posts,
          categoryId: route.categoryId,
          tagName: scope.tagName,
          topicIds: topicIds,
        ),
      );
      if (!lease.isCurrent || shell._tabContextDisposed) return null;
      for (final type in [
        if (topics) 'dismiss_new',
        if (posts) 'dismiss_new_posts',
      ]) {
        shell._applyTopicTrackingMessage(siteUrl, {
          'message_type': type,
          'payload': {'topic_ids': ids},
        });
      }
      await shell.topicFeeds.load(
        instance: instance,
        destinationId: route.id,
        path: route.feedPath!,
        incoming: shell._trackers[siteUrl]?.incoming,
        force: true,
      );
      return null;
    } catch (error, stackTrace) {
      if (!lease.isCurrent || shell._tabContextDisposed) return null;
      shell._reportOperationalError(error, stackTrace, 'topics.dismissNew');
      return appL10n.couldNotDismissNewTopicsPleaseTryAgain;
    } finally {
      shell._dismissingNew.remove(key);
      if (!shell._tabContextDisposed) shell._notify();
    }
  }

  bool get canDismissNewTopics => _dismissNewScope != null;

  ({String? tagName})? get _dismissNewScope {
    final instance = _instance;
    final mode = currentTopicListMode;
    final feed = currentFeed;
    if (instance == null ||
        !instance.isConnected ||
        (mode != TopicListMode.newActivity &&
            mode != TopicListMode.newTopics &&
            mode != TopicListMode.newReplies) ||
        feed == null ||
        feed.topicIds.isEmpty) {
      return null;
    }
    final requested = topicListContent?.tagNames.firstOrNull?.toLowerCase();
    if (requested == null) return (tagName: null);
    for (final id in feed.topicIds) {
      final topic = shell.store.read<Topic>(instance.url, id);
      for (final tag in topic?.tags ?? const <TopicTag>[]) {
        if (tag.name.toLowerCase() == requested) return (tagName: tag.name);
      }
    }
    return null;
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
    } catch (error, stackTrace) {
      shell._reportOperationalError(error, stackTrace, 'tab.refresh');
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
