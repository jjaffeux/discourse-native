part of 'shell_controller.dart';

final class _CategoryIdRequest {
  _CategoryIdRequest(this.ids);

  final List<int> ids;
  final completion = Completer<List<TopicCategory>>();
  int consumers = 0;
}

final class _TaxonomySite {
  _TaxonomySite(this.lease);

  final SiteLease lease;
  bool categorised = false;
  RequestIntentOperation<void>? categoryRequest;
  List<TopicCategory>? categories;
  CategoryFeed categoryFeed = const CategoryFeed();
  final Map<int, _CategoryIdRequest> categoryIdRequests = {};
  Object? categoryPageRequest;
  TagDirectoryFeed tagDirectoryFeed = const TagDirectoryFeed();
  Object? tagDirectoryRequest;
  List<SidebarTag> siteTopTags = const [];
  List<SidebarTag> anonymousDefaultTags = const [];
  final Map<int, List<TopicFilterLookupValue>> scopedSidebarTags = {};
  final Map<int, Object> scopedSidebarTagRequests = {};
  _CategorySidebarCache? categorySidebarCache;
  _TagSidebarCache? tagSidebarCache;
  _TopicListFilterTagsCache? topicListFilterTagsCache;
}

final class _TaxonomyDirectoryController {
  _TaxonomyDirectoryController(this._shell);

  final ShellController _shell;
  final Map<String, _TaxonomySite> _sites = {};

  _TaxonomySite _site(String siteUrl) => _sites.putIfAbsent(
    siteUrl,
    () => _TaxonomySite(_shell.lifecycle.capture(siteUrl)),
  );

  void bind(String siteUrl) {
    _site(siteUrl);
  }

  void forget(String siteUrl) {
    _sites.remove(siteUrl);
  }

  void dispose() => _sites.clear();

  bool needsCategoryLoad(String siteUrl) =>
      !(_sites[siteUrl]?.categorised ?? false);
  List<TopicCategory> categoriesFor(String siteUrl) =>
      _sites[siteUrl]?.categories ?? const [];
  bool isPrivateSidebarTag(String siteUrl, int tagId) {
    final site = _sites[siteUrl];
    return <SidebarTag>[
      ...?_shell._instanceAt(siteUrl)?.user?.sidebarTags,
      ...?site?.siteTopTags,
      ...?site?.anonymousDefaultTags,
    ].any((tag) => tag.id == tagId && tag.pmOnly);
  }

  CategoryFeed categoryFeedFor(String siteUrl) =>
      _sites[siteUrl]?.categoryFeed ?? const CategoryFeed();
  TagDirectoryFeed tagDirectoryFeedFor(String siteUrl) =>
      _sites[siteUrl]?.tagDirectoryFeed ?? const TagDirectoryFeed();
  void invalidateCategorySidebar(String siteUrl) {
    final site = _sites[siteUrl];
    if (site != null) site.categorySidebarCache = null;
  }

  void projectNotificationLevel(
    String siteUrl,
    int categoryId,
    CategoryNotificationLevel level,
    SiteLease lease,
  ) {
    final site = _sites[siteUrl];
    if (site == null ||
        !identical(site.lease.session, lease.session) ||
        !lease.isCurrent ||
        !site.lease.isCurrent) {
      return;
    }
    final held = _shell.store.read<TopicCategory>(siteUrl, categoryId);
    if (held == null || held.notificationLevel == level) return;
    final category = held.withNotificationLevel(level);
    final byId = <int, TopicCategory>{
      for (final previous in site.categories ?? const <TopicCategory>[])
        previous.id: previous,
      category.id: category,
    };
    site.categories = List.unmodifiable(byId.values);
    site.categorySidebarCache = null;
    _shell.store.put(siteUrl, category);
    if (lease.isCurrent && !_shell.accountSessionDisposed) _shell._notify();
  }

  Future<void> ensureScopedSidebarTags(String siteUrl, int? categoryId) async {
    if (categoryId == null || !_shell.siteConfigFor(siteUrl).taggingEnabled) {
      return;
    }
    final site = _site(siteUrl);
    if (!site.lease.isCurrent) return;
    final key = categoryId;
    if (site.scopedSidebarTags.containsKey(key) ||
        site.scopedSidebarTagRequests.containsKey(key)) {
      return;
    }
    final lease = site.lease;
    final request = Object();
    site.scopedSidebarTagRequests[key] = request;
    try {
      final tags = await searchFilterTags(
        siteUrl: siteUrl,
        term: '',
        categoryId: categoryId,
      );
      if (!lease.isCurrent || _shell.accountSessionDisposed) return;
      site.scopedSidebarTags[key] = tags;
      _shell._notify();
    } finally {
      if (identical(site.scopedSidebarTagRequests[key], request)) {
        site.scopedSidebarTagRequests.remove(key);
      }
    }
  }

  SidebarSection? categorySidebarSectionFor(String siteUrl) {
    if (_sites[siteUrl]?.categories == null) return null;
    final categories = categoriesFor(siteUrl);
    final user = _shell._instanceAt(siteUrl)?.user;
    final config = _shell.siteConfigFor(siteUrl);
    if (_shell.sidebarFilterRoute?.categoryId case final id?) {
      return buildCategorySidebarSection(
        categories: categories,
        connected: user != null,
        levelNavigation: true,
        scopeCategoryId: id,
        allowUncategorizedTopics: config.allowUncategorizedTopics,
      );
    }
    final site = _sites[siteUrl]!;
    final held = site.categorySidebarCache;
    if (held != null &&
        identical(held.categories, categories) &&
        identical(held.user, user) &&
        held.config == config) {
      return held.section;
    }

    final section = buildCategorySidebarSection(
      categories: categories,
      connected: user != null,
      preferredCategoryIds: user?.sidebarCategoryIds ?? const [],
      defaultCategoryIds: config.defaultNavigationMenuCategoryIds,
      fixedCategoryPositions: config.fixedCategoryPositions,
      allowUncategorizedTopics: config.allowUncategorizedTopics,
      levelNavigation: true,
    );
    site.categorySidebarCache = (
      categories: categories,
      user: user,
      config: config,
      section: section,
    );
    return section;
  }

  SidebarSection? tagSidebarSectionFor(String siteUrl) {
    final instance = _shell._instanceAt(siteUrl);
    if (instance == null || !_shell.siteConfigFor(siteUrl).taggingEnabled) {
      return null;
    }

    final user = instance.user;
    final selectedTag = _shell.sidebarTagName;
    if (_shell.sidebarFilterRoute?.categoryId case final id?) {
      if (user != null && !user.displaySidebarTags && selectedTag == null) {
        return null;
      }
      final tags = _sites[siteUrl]?.scopedSidebarTags[id];
      return SidebarSection(
        id: 'tags',
        title: appL10n.tags,
        loading: tags == null && selectedTag == null,
        collapsible: selectedTag == null,
        destinations: [
          if (user == null || user.displaySidebarTags)
            for (final tag in tags ?? const <TopicFilterLookupValue>[])
              ?buildTopicTagDestination(TopicTag(name: tag.name)),
          if (selectedTag != null &&
              (user?.displaySidebarTags == false ||
                  !(tags?.any(
                        (tag) =>
                            tag.name.toLowerCase() == selectedTag.toLowerCase(),
                      ) ??
                      false)))
            ?buildTopicTagDestination(TopicTag(name: selectedTag)),
          allTagsDestination,
        ],
      );
    }
    final siteTop = _sites[siteUrl]?.siteTopTags ?? const <SidebarTag>[];
    final anonymousDefaults =
        _sites[siteUrl]?.anonymousDefaultTags ?? const <SidebarTag>[];
    final tags = user == null
        ? (anonymousDefaults.isNotEmpty ? anonymousDefaults : siteTop)
        : (user.sidebarTags.isNotEmpty ? user.sidebarTags : siteTop);
    final display = user == null ? tags.isNotEmpty : user.displaySidebarTags;

    if (selectedTag != null) {
      return SidebarSection(
        id: 'tags',
        title: appL10n.tags,
        collapsible: false,
        destinations: [
          if (display)
            for (final tag in tags)
              ?buildTagDestination(tag, username: user?.username),
          if (!display ||
              !tags.any(
                (tag) => tag.name.toLowerCase() == selectedTag.toLowerCase(),
              ))
            ?buildTopicTagDestination(TopicTag(name: selectedTag)),
          allTagsDestination,
        ],
      );
    }
    final site = _sites[siteUrl];
    final held = site?.tagSidebarCache;
    if (held != null &&
        identical(held.tags, tags) &&
        held.display == display &&
        held.username == user?.username) {
      return held.section;
    }

    final section = buildTagSidebarSection(
      tags: tags,
      display: display,
      username: user?.username,
    );
    if (section == null) {
      if (site != null) site.tagSidebarCache = null;
      return null;
    }
    if (site != null) {
      site.tagSidebarCache = (
        tags: tags,
        display: display,
        username: user?.username,
        section: section,
      );
    }
    return section;
  }

  List<SidebarTag> topicListFilterTagsFor(String siteUrl) {
    final instance = _shell._instanceAt(siteUrl);
    if (instance == null) return const [];
    final user = instance.user;
    final sources = (
      account: (user?.id, user?.username),
      personal: user?.sidebarTags ?? const <SidebarTag>[],
      siteTop: _sites[siteUrl]?.siteTopTags ?? const <SidebarTag>[],
      anonymousDefaults:
          _sites[siteUrl]?.anonymousDefaultTags ?? const <SidebarTag>[],
      directory: tagDirectoryFeedFor(siteUrl).tags,
    );
    final site = _sites[siteUrl];
    final held = site?.topicListFilterTagsCache;
    if (held != null && held.sources == sources) return held.tags;

    final byName = <String, SidebarTag>{};
    for (final tag in knownTagsFor(siteUrl)) {
      if (tag.pmOnly) continue;
      byName.putIfAbsent(tag.name.toLowerCase(), () => tag);
    }
    final tags = List<SidebarTag>.unmodifiable(byName.values);
    final snapshot =
        held != null &&
            held.sources.account == sources.account &&
            listEquals(held.tags, tags)
        ? held.tags
        : tags;
    if (site != null) {
      site.topicListFilterTagsCache = (sources: sources, tags: snapshot);
    }
    return snapshot;
  }

  Future<List<TopicCategory>> searchFilterCategories({
    required String siteUrl,
    required String term,
  }) async {
    final lease = _site(siteUrl).lease;
    if (!lease.isCurrent) return const [];
    final categories = await _shell._filterLookup(
      siteUrl,
      'topics.filter.categories',
      (apiKey, clientId) => apiKey == null
          ? Future.value(const <TopicCategory>[])
          : _shell.api.categories.searchCategories(
              siteUrl: siteUrl,
              term: term,
              apiKey: apiKey,
              includeAncestors: true,
              clientId: clientId,
            ),
    );
    if (_shell.accountSessionDisposed || !lease.isCurrent) return const [];
    if (categories.isNotEmpty) {
      final previous = categoriesFor(siteUrl);
      mergeCategories(siteUrl, categories);
      if (!listEquals(previous, categoriesFor(siteUrl))) _shell._notify();
    }
    return categories;
  }

  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int? categoryId,
  }) async {
    final lease = _site(siteUrl).lease;
    if (!lease.isCurrent) return const [];
    final remote = await _shell._filterLookup(
      siteUrl,
      'topics.filter.tags',
      (apiKey, clientId) => _shell.api.lookups.searchFilterTags(
        siteUrl: siteUrl,
        term: term,
        categoryId: categoryId,
        limit: _shell
            .siteConfigFor(siteUrl)
            .maxTagSearchResults
            .clamp(1, TopicTagSearch.maximumResults),
        apiKey: apiKey,
        clientId: clientId,
      ),
    );
    if (_shell.accountSessionDisposed || !lease.isCurrent) return const [];
    final byName = <String, TopicFilterLookupValue>{
      for (final tag in remote) tag.name.toLowerCase(): tag,
    };
    if (categoryId == null) {
      for (final tag in topicListFilterTagsFor(siteUrl)) {
        if (tag.name.toLowerCase().contains(term.toLowerCase())) {
          byName.putIfAbsent(
            tag.name.toLowerCase(),
            () => TopicFilterLookupValue(
              name: tag.name,
              description: '${tag.count}',
            ),
          );
        }
      }
    }
    return byName.values.toList()..sort((a, b) {
      final count = (int.tryParse(b.description ?? '') ?? 0).compareTo(
        int.tryParse(a.description ?? '') ?? 0,
      );
      return count != 0
          ? count
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  SidebarTag? knownTopicTag(String siteUrl, TopicTag topicTag) {
    final topicTagId = topicTag.id;
    final topicTagName = topicTag.name.trim().toLowerCase();
    for (final tag in knownTagsFor(siteUrl)) {
      if ((topicTagId != null && topicTagId > 0 && tag.id == topicTagId) ||
          tag.name.trim().toLowerCase() == topicTagName) {
        return tag;
      }
    }
    return null;
  }

  Iterable<SidebarTag> knownTagsFor(String siteUrl) sync* {
    yield* _shell._instanceAt(siteUrl)?.user?.sidebarTags ?? const [];
    yield* _sites[siteUrl]?.siteTopTags ?? const [];
    yield* _sites[siteUrl]?.anonymousDefaultTags ?? const [];
    yield* tagDirectoryFeedFor(siteUrl).tags;
  }

  Future<List<TopicCategory>> searchTopicCategoriesForEditor({
    required String siteUrl,
    required String term,
  }) async {
    final lease = _site(siteUrl).lease;
    if (!lease.isCurrent) return const [];
    final held = await _shell._credentialForWrite(siteUrl, lease: lease);
    if (!lease.isCurrent) return const [];
    if (held.failure case final failure?) throw failure;

    final categories = await held.request!.run(
      () => _shell.api.categories.searchCategories(
        siteUrl: siteUrl,
        apiKey: held.apiKey!,
        term: term,
        includeUncategorized: _shell
            .siteConfigFor(siteUrl)
            .allowUncategorizedTopics,
      ),
    );
    if (!lease.isCurrent) return const [];
    lease.commit(() {
      mergeCategories(siteUrl, categories);
      _shell._notify();
    });
    return categories;
  }

  Future<void> loadCategories(String siteUrl, {bool force = false}) async {
    final site = _site(siteUrl);
    final instance = _shell._instanceAt(siteUrl);
    if (!site.lease.isCurrent) return;
    if (force && !site.categoryFeed.loading) {
      site.categorised = false;
    }
    if (instance != null) await ensureCategoriesFor(instance);
  }

  Future<void> loadTags(String siteUrl, {bool force = false}) async {
    final site = _site(siteUrl);
    final instance = _shell._instanceAt(siteUrl);
    if (!site.lease.isCurrent ||
        instance == null ||
        (instance.loginRequired && !instance.isConnected)) {
      return;
    }
    if (!_shell.siteConfigFor(siteUrl).taggingEnabled) {
      final held = site.tagDirectoryFeed;
      if (!held.loaded || held.tags.isNotEmpty || held.error != null) {
        site.tagDirectoryFeed = const TagDirectoryFeed(loaded: true);
        _shell._notify();
      }
      return;
    }
    final held = site.tagDirectoryFeed;
    if (!force && held.loaded) return;
    if (site.tagDirectoryRequest != null) return;
    final request = Object();
    site.tagDirectoryRequest = request;

    final lease = site.lease;
    site.tagDirectoryFeed = held.refreshing();
    _shell._notify();
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = instance.isConnected
          ? await session.credentials(_shell.credentials)
          : session.anonymousCredentials();
      if (!lease.isCurrent) return;
      final tags = await credential.run(
        () => _shell.api.tags.tags(
          siteUrl: siteUrl,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      final visibleTags = instance.user == null
          ? tags.where((tag) => !tag.pmOnly)
          : tags;
      lease.commit(() {
        site.tagDirectoryFeed = held.withTags(visibleTags);
        _shell._notify();
      });
    } catch (error, stackTrace) {
      if (_shell.accountSessionDisposed || !lease.isCurrent) return;
      _shell._reportOperationalError(
        error,
        stackTrace,
        'tags.load',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        site.tagDirectoryFeed = held.withError(
          appL10n.couldnTLoadTagsFrom((instance.host).toString()),
        );
        _shell._notify();
      });
    } finally {
      if (identical(site.tagDirectoryRequest, request)) {
        site.tagDirectoryRequest = null;
      }
    }
  }

  Future<void> ensureCategoryIds(
    DiscourseInstance instance,
    Iterable<int> categoryIds, {
    bool Function()? isCurrent,
  }) async {
    if (_shell.accountSessionDisposed || isCurrent?.call() == false) return;
    final site = _site(instance.url);
    if (instance.loginRequired && !instance.isConnected) return;
    final lease = site.lease;
    bool requestIsCurrent() =>
        !_shell.accountSessionDisposed &&
        lease.isCurrent &&
        identical(_sites[instance.url], site) &&
        (isCurrent?.call() ?? true);
    if (!requestIsCurrent()) return;
    try {
      final requestSession = AccountRequestSession(instance.url, lease);
      Future<AccountRequestCredentials>? credentialRead;
      Future<AccountRequestCredentials> readCredentials() =>
          credentialRead ??= instance.isConnected
          ? requestSession.credentials(_shell.credentials)
          : Future.value(requestSession.anonymousCredentials());
      var pending = categoryIds.toSet();
      final visited = <int>{};
      while (pending.isNotEmpty) {
        if (!requestIsCurrent()) return;
        final cached = [
          for (final id in pending)
            ?_shell.store.read<TopicCategory>(instance.url, id),
        ];
        if (cached.isNotEmpty) {
          pending.removeAll(cached.map((category) => category.id));
          visited.addAll(cached.map((category) => category.id));
          pending.addAll([
            for (final category in cached)
              if (category.parentCategoryId case final parentId?
                  when !visited.contains(parentId))
                parentId,
          ]);
          continue;
        }
        final batch = <int>[];
        final requested = <int>{};
        final requests = <_CategoryIdRequest>{};
        for (final id in pending) {
          if (batch.length == 100) break;
          requested.add(id);
          final active = site.categoryIdRequests[id];
          if (active == null) {
            batch.add(id);
          } else {
            requests.add(active);
          }
        }
        if (batch.isNotEmpty) {
          final request = _CategoryIdRequest(batch);
          for (final id in batch) {
            site.categoryIdRequests[id] = request;
          }
          requests.add(request);
          unawaited(() async {
            try {
              if (_shell.accountSessionDisposed || !lease.isCurrent) {
                request.completion.complete(const []);
                return;
              }
              final credential = await readCredentials();
              final found = await credential.run(
                () => _shell.api.categories.findCategories(
                  siteUrl: instance.url,
                  ids: batch,
                  apiKey: credential.apiKey,
                  clientId: credential.clientId,
                ),
              );
              request.completion.complete(found);
            } catch (error, stackTrace) {
              request.completion.completeError(error, stackTrace);
            }
          }());
        }
        final found = (await Future.wait(
          requests.map((request) async {
            request.consumers++;
            try {
              final found = await request.completion.future;
              if (!requestIsCurrent()) return const <TopicCategory>[];
              final changed = [
                for (final category in found)
                  if (_shell.store.read<TopicCategory>(
                        instance.url,
                        category.id,
                      ) !=
                      category)
                    category,
              ];
              if (changed.isNotEmpty) {
                mergeCategories(
                  instance.url,
                  changed,
                  isCurrent: requestIsCurrent,
                );
                if (requestIsCurrent()) _shell._notify();
              }
              return found;
            } finally {
              request.consumers--;
              if (request.consumers == 0) {
                for (final id in request.ids) {
                  if (identical(site.categoryIdRequests[id], request)) {
                    site.categoryIdRequests.remove(id);
                  }
                }
              }
            }
          }),
        )).expand((batch) => batch).toList();
        if (!requestIsCurrent()) return;
        pending.removeAll(requested);
        visited.addAll(requested);
        pending.addAll([
          for (final category in found)
            if (category.parentCategoryId case final parentId?
                when !visited.contains(parentId))
              parentId,
        ]);
      }
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _shell._reportOperationalError(
        error,
        stackTrace,
        'categories.find',
        severity: DiagnosticSeverity.warning,
      );
    }
  }

  Future<void> ensureCategoriesFor(
    DiscourseInstance instance, {
    int? categoryId,
  }) async {
    final site = _site(instance.url);
    if (instance.loginRequired && !instance.isConnected) return;

    final lease = site.lease;
    if (!lease.isCurrent) return;
    try {
      final requestSession = AccountRequestSession(instance.url, lease);
      final credential = instance.isConnected
          ? await requestSession.credentials(_shell.credentials)
          : requestSession.anonymousCredentials();
      if (!lease.isCurrent) return;
      await _ensureCategories(instance, credential, lease: lease);
      if (lease.isCurrent && categoryId != null) {
        await ensureCategoryIds(instance, [categoryId]);
      }
    } catch (error, stackTrace) {
      if (_shell.accountSessionDisposed || !lease.isCurrent) return;
      _shell._reportOperationalError(
        error,
        stackTrace,
        'categories.readCredentials',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        final held = site.categoryFeed;
        site.categoryFeed = held.withError(
          appL10n.couldnTLoadCategoriesFrom((instance.host).toString()),
        );
        _shell._notify();
      });
    }
  }

  Future<void> _ensureCategories(
    DiscourseInstance instance,
    AccountRequestCredentials credential, {
    SiteLease? lease,
  }) {
    final site = _site(instance.url);
    if (!site.lease.isCurrent) return Future<void>.value();
    final active = site.categoryRequest;
    if (active != null) return active.join();
    late final RequestIntentOperation<void> request;
    request = RequestIntentOperation(
      () => _loadCategories(instance, credential, site, lease: lease)
          .whenComplete(() {
            if (identical(site.categoryRequest, request)) {
              site.categoryRequest = null;
            }
          }),
    );
    site.categoryRequest = request;
    return request.future;
  }

  Future<void> _loadCategories(
    DiscourseInstance instance,
    AccountRequestCredentials credential,
    _TaxonomySite site, {
    SiteLease? lease,
  }) async {
    final session = lease ?? site.lease;
    if (!session.isCurrent || site.categorised) return;
    site.categorised = true;
    final existingFeed = site.categoryFeed;
    site.categoryFeed = existingFeed.refreshing();
    _shell._notify();

    try {
      final result = await credential.run(
        () => _shell.api.categories.loadCategories(
          siteUrl: instance.url,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      if (_shell.accountSessionDisposed || !session.isCurrent) return;
      await _shell._presentation.ensureConfig(instance.url);
      if (_shell.accountSessionDisposed || !session.isCurrent) return;
      session.commit(() {
        mergeCategories(instance.url, result.categories);
        if (!session.isCurrent) return;

        final held = site.categoryFeed;
        final roots = <int>{...result.rootCategoryIds, ...held.categoryIds};
        final nextPage = existingFeed.loaded && existingFeed.error == null
            ? held.nextPage
            : result.rootCategoryIds.isNotEmpty
            ? 2
            : null;
        site.categoryFeed = CategoryFeed(
          categoryIds: List.unmodifiable(roots),
          loaded: true,
          nextPage: nextPage,
          canCreateTopic: result.canCreateTopic,
        );
        if (result.postActionCatalog case final catalog?) {
          _shell._postActionCatalogs[instance.url] = catalog;
        }
        if (result.siteTopTags case final tags?) {
          site.siteTopTags = tags;
          site.tagSidebarCache = null;
        }
        if (result.anonymousDefaultTags case final tags?) {
          site.anonymousDefaultTags = tags;
          site.tagSidebarCache = null;
        }
        if (!result.complete) site.categorised = false;
        _shell._notify();
      });
    } catch (error, stackTrace) {
      if (_shell.accountSessionDisposed || !session.isCurrent) return;
      _shell._reportOperationalError(
        error,
        stackTrace,
        'categories.load',
        severity: DiagnosticSeverity.warning,
      );
      session.commit(() {
        site.categorised = false;
        final held = site.categoryFeed;
        site.categoryFeed = held.withError(
          appL10n.couldnTLoadCategoriesFrom((instance.host).toString()),
        );
        _shell._notify();
      });
    }
  }

  void mergeCategories(
    String siteUrl,
    Iterable<TopicCategory> incoming, {
    bool Function()? isCurrent,
  }) {
    if (_shell.accountSessionDisposed || isCurrent?.call() == false) return;
    final site = _site(siteUrl);
    bool canMerge() =>
        !_shell.accountSessionDisposed &&
        site.lease.isCurrent &&
        identical(_sites[siteUrl], site) &&
        (isCurrent?.call() ?? true);
    if (!canMerge()) return;
    final stored = <TopicCategory>[];
    for (final category in incoming) {
      if (!canMerge()) return;
      stored.add(_shell.store.put(siteUrl, category));
      if (!canMerge()) return;
    }
    final byId = <int, TopicCategory>{
      for (final category in site.categories ?? const <TopicCategory>[])
        category.id: category,
      for (final category in stored)
        category.id:
            _shell.store.read<TopicCategory>(siteUrl, category.id) ?? category,
    };
    site.categories = List.unmodifiable(byId.values);
    site.categorySidebarCache = null;
    _shell._rewriteContentRoutes(
      siteUrl,
      (route) => route.resolveCategoryLink(byId.values),
    );
  }

  Future<void> loadMoreCategories(String siteUrl) async {
    final site = _site(siteUrl);
    final instance = _shell._instanceAt(siteUrl);
    final feed = categoryFeedFor(siteUrl);
    final page = feed.nextPage;
    if (instance == null ||
        page == null ||
        feed.loadingMore ||
        !site.lease.isCurrent) {
      return;
    }
    if (site.categoryPageRequest != null) return;

    final lease = site.lease;
    final request = Object();
    site.categoryPageRequest = request;
    site.categoryFeed = feed.loadingNextPage();
    _shell._notify();

    bool requestIsCurrent() =>
        !_shell.accountSessionDisposed &&
        lease.isCurrent &&
        identical(site.categoryPageRequest, request);

    try {
      final session = AccountRequestSession(siteUrl, lease);
      final credential = instance.isConnected
          ? await session.credentials(_shell.credentials)
          : session.anonymousCredentials();
      if (!requestIsCurrent()) return;

      final result = await credential.run(
        () => _shell.api.categories.loadCategories(
          siteUrl: siteUrl,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
          page: page,
        ),
      );
      if (!requestIsCurrent()) return;

      lease.commit(() {
        if (!identical(site.categoryPageRequest, request)) return;
        mergeCategories(siteUrl, result.categories);
        if (!requestIsCurrent()) return;
        site.categoryPageRequest = null;
        final held = site.categoryFeed;
        site.categoryFeed = held.withPage(
          result.rootCategoryIds,
          hasMore: result.rootCategoryIds.isNotEmpty,
        );
        _shell._notify();
      });
    } catch (error, stackTrace) {
      if (!requestIsCurrent()) return;
      _shell._reportOperationalError(
        error,
        stackTrace,
        'categories.loadMore',
        severity: DiagnosticSeverity.warning,
      );
      lease.commit(() {
        if (!identical(site.categoryPageRequest, request)) return;
        site.categoryPageRequest = null;
        final held = site.categoryFeed;
        site.categoryFeed = held.withError(
          appL10n.couldnTLoadMoreCategoriesFrom((instance.host).toString()),
          page: true,
        );
        _shell._notify();
      });
    }
  }
}

typedef _CategorySidebarCache = ({
  List<TopicCategory> categories,
  DiscourseUser? user,
  SiteConfig config,
  SidebarSection section,
});
typedef _TagSidebarCache = ({
  List<SidebarTag> tags,
  bool display,
  String? username,
  SidebarSection section,
});
typedef _TopicListFilterTagSources = ({
  (int?, String?) account,
  List<SidebarTag> personal,
  List<SidebarTag> siteTop,
  List<SidebarTag> anonymousDefaults,
  List<SidebarTag> directory,
});
typedef _TopicListFilterTagsCache = ({
  _TopicListFilterTagSources sources,
  List<SidebarTag> tags,
});
