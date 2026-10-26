part of 'shell_controller.dart';

final class _CategoryNotificationAuthority {
  int revision = 0;
  bool pending = false;
}

final class _CategoryRead {
  _CategoryRead(this.site)
    : revisions = {
        for (final entry in site.categoryNotificationAuthorities.entries)
          entry.key: entry.value.revision,
      };

  final _TaxonomySite site;
  final Map<int, int> revisions;
}

final class _CategoryIdRequest {
  _CategoryIdRequest(this.ids, this.notificationRead);

  final _CategoryRead notificationRead;

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
  final Map<int, _CategoryNotificationAuthority>
  categoryNotificationAuthorities = {};
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
  _TagSearchEntriesCache? tagSearchEntriesCache;
  _KnownTagIndex? knownTagIndex;
}

final class _TaxonomyDirectoryController
    implements NotificationPreferenceTaxonomy {
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
  @override
  void invalidateCategorySidebar(String siteUrl) {
    final site = _sites[siteUrl];
    if (site != null) site.categorySidebarCache = null;
  }

  @override
  void projectNotificationLevel(
    String siteUrl,
    int categoryId,
    CategoryNotificationLevel level,
    SiteLease lease, {
    required bool pending,
  }) {
    final site = _sites[siteUrl];
    if (site == null ||
        !identical(site.lease.session, lease.session) ||
        !lease.isCurrent ||
        !site.lease.isCurrent) {
      return;
    }
    final authority = site.categoryNotificationAuthorities.putIfAbsent(
      categoryId,
      _CategoryNotificationAuthority.new,
    );
    authority.revision++;
    authority.pending = pending;
    final held =
        _shell.store.read<TopicCategory>(siteUrl, categoryId) ??
        site.categories
            ?.where((category) => category.id == categoryId)
            .firstOrNull;
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

  _TopicListFilterTagSources _topicListFilterTagSourcesFor(String siteUrl) {
    final user = _shell._instanceAt(siteUrl)?.user;
    return (
      account: (user?.id, user?.username),
      personal: user?.sidebarTags ?? const <SidebarTag>[],
      siteTop: _sites[siteUrl]?.siteTopTags ?? const <SidebarTag>[],
      anonymousDefaults:
          _sites[siteUrl]?.anonymousDefaultTags ?? const <SidebarTag>[],
      directory: tagDirectoryFeedFor(siteUrl).tags,
    );
  }

  List<SidebarTag> topicListFilterTagsFor(String siteUrl) {
    final instance = _shell._instanceAt(siteUrl);
    if (instance == null) return const [];
    final sources = _topicListFilterTagSourcesFor(siteUrl);
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
    final site = _site(siteUrl);
    final lease = site.lease;
    final notificationRead = _CategoryRead(site);
    if (!lease.isCurrent) return const [];
    final categories = await _shell._filterLookup(
      siteUrl,

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
      mergeCategories(siteUrl, categories, notificationRead: notificationRead);
      if (!listEquals(previous, categoriesFor(siteUrl))) _shell._notify();
    }
    if (_shell.accountSessionDisposed || !lease.isCurrent) return const [];
    final canonical = {
      for (final category in site.categories ?? const <TopicCategory>[])
        category.id: category,
    };
    return [
      for (final category in categories) canonical[category.id] ?? category,
    ];
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
    final byName = <String, _TagSearchEntry>{};
    for (final tag in remote) {
      final name = tag.name.toLowerCase();
      byName[name] = (
        nameKey: name,
        rank: int.tryParse(tag.description ?? '') ?? 0,
        value: tag,
      );
    }
    if (categoryId == null) {
      final query = term.toLowerCase();
      for (final entry in _localTagSearchEntriesFor(siteUrl)) {
        if (entry.nameKey.contains(query)) {
          byName.putIfAbsent(entry.nameKey, () => entry);
        }
      }
    }
    final entries = byName.values.toList()
      ..sort((a, b) {
        final rank = b.rank.compareTo(a.rank);
        return rank != 0 ? rank : a.nameKey.compareTo(b.nameKey);
      });
    return [for (final entry in entries) entry.value];
  }

  List<_TagSearchEntry> _localTagSearchEntriesFor(String siteUrl) {
    final tags = topicListFilterTagsFor(siteUrl);
    final site = _sites[siteUrl];
    final held = site?.tagSearchEntriesCache;
    if (held != null && identical(held.tags, tags)) return held.entries;
    final entries = List<_TagSearchEntry>.unmodifiable([
      for (final tag in tags)
        (
          nameKey: tag.name.toLowerCase(),
          rank: tag.count,
          value: TopicFilterLookupValue(
            name: tag.name,
            description: '${tag.count}',
          ),
        ),
    ]);
    if (site != null) {
      site.tagSearchEntriesCache = (tags: tags, entries: entries);
    }
    return entries;
  }

  _KnownTagIndex _knownTagIndexFor(String siteUrl) {
    final sources = _topicListFilterTagSourcesFor(siteUrl);
    final site = _sites[siteUrl];
    final held = site?.knownTagIndex;
    if (held != null && held.sources == sources) return held;
    final index = _KnownTagIndex(sources);
    if (site != null) site.knownTagIndex = index;
    return index;
  }

  SidebarTag? knownTopicTag(String siteUrl, TopicTag topicTag) =>
      _knownTagIndexFor(siteUrl).forTopicTag(topicTag);

  SidebarTag? knownTopicListTag(String siteUrl, String name) =>
      _knownTagIndexFor(siteUrl).forTopicListTag(name);

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
    final site = _site(siteUrl);
    final lease = site.lease;
    final notificationRead = _CategoryRead(site);
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
      mergeCategories(siteUrl, categories, notificationRead: notificationRead);
      _shell._notify();
    });
    if (_shell.accountSessionDisposed || !lease.isCurrent) return const [];
    final canonical = {
      for (final category in site.categories ?? const <TopicCategory>[])
        category.id: category,
    };
    return [
      for (final category in categories) canonical[category.id] ?? category,
    ];
  }

  Future<void> loadCategories(String siteUrl, {bool force = false}) async {
    final site = _site(siteUrl);
    final instance = _shell._instanceAt(siteUrl);
    if (!site.lease.isCurrent) return;
    if (instance != null) await ensureCategoriesFor(instance, force: force);
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
    } catch (error) {
      if (_shell.accountSessionDisposed || !lease.isCurrent) return;

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
          final request = _CategoryIdRequest(batch, _CategoryRead(site));
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
                  notificationRead: request.notificationRead,
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
    } catch (error) {
      if (!requestIsCurrent()) return;
    }
  }

  Future<void> ensureCategoriesFor(
    DiscourseInstance instance, {
    int? categoryId,
    bool force = false,
  }) async {
    final site = _site(instance.url);
    if (instance.loginRequired && !instance.isConnected) return;

    final lease = site.lease;
    if (!lease.isCurrent) return;
    try {
      await _ensureCategories(instance, force: force);
      if (lease.isCurrent && categoryId != null) {
        await ensureCategoryIds(instance, [categoryId]);
      }
    } catch (error) {
      if (_shell.accountSessionDisposed || !lease.isCurrent) return;

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
    DiscourseInstance instance, {
    bool force = false,
  }) {
    final site = _site(instance.url);
    if (!site.lease.isCurrent) return Future<void>.value();
    final active = site.categoryRequest;
    if (!force && active != null) return active.join();
    if (!force && site.categorised) return Future<void>.value();
    final existingFeed = site.categoryFeed;
    if (force) site.categoryPageRequest = null;
    site.categorised = true;
    late final RequestIntentOperation<void> request;
    bool requestIsCurrent() =>
        !_shell.accountSessionDisposed &&
        site.lease.isCurrent &&
        identical(_sites[instance.url], site) &&
        identical(site.categoryRequest, request);
    request = RequestIntentOperation(
      () =>
          Future<void>.microtask(
            () => _loadCategories(
              instance,
              site,
              existingFeed: existingFeed,
              replace: force,
              isCurrent: requestIsCurrent,
            ),
          ).whenComplete(() {
            if (identical(site.categoryRequest, request)) {
              site.categoryRequest = null;
            }
          }),
    );
    site.categoryRequest = request;
    site.categoryFeed = existingFeed.refreshing();
    _shell._notify();
    return request.future;
  }

  Future<void> _loadCategories(
    DiscourseInstance instance,
    _TaxonomySite site, {
    required CategoryFeed existingFeed,
    required bool replace,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    final session = site.lease;
    final notificationRead = _CategoryRead(site);
    try {
      final requestSession = AccountRequestSession(instance.url, session);
      final credential = instance.isConnected
          ? await requestSession.credentials(_shell.credentials)
          : requestSession.anonymousCredentials();
      if (!isCurrent()) return;
      final result = await credential.run(
        () => _shell.api.categories.loadCategories(
          siteUrl: instance.url,
          apiKey: credential.apiKey,
          clientId: credential.clientId,
        ),
      );
      if (!isCurrent()) return;
      await _shell._presentation.ensureConfig(instance.url);
      if (!isCurrent()) return;
      session.commit(() {
        mergeCategories(
          instance.url,
          result.categories,
          isCurrent: isCurrent,
          notificationRead: notificationRead,
        );
        if (!isCurrent()) return;

        final held = site.categoryFeed;
        final roots = <int>{
          ...result.rootCategoryIds,
          if (!replace) ...held.categoryIds,
        };
        final nextPage =
            !replace && existingFeed.loaded && existingFeed.error == null
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
        if (result.anonymousSearchAllowed case final allowed?) {
          _shell.search.allowAnonymousSearch(instance.url, allowed);
        }
        if (!result.complete) site.categorised = false;
        _shell._notify();
      });
    } catch (error) {
      if (!isCurrent()) return;

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

  void Function(List<TopicCategory>) captureCategoryRead(String siteUrl) {
    final read = _CategoryRead(_site(siteUrl));
    return (categories) =>
        mergeCategories(siteUrl, categories, notificationRead: read);
  }

  void mergeCategories(
    String siteUrl,
    Iterable<TopicCategory> incoming, {
    bool Function()? isCurrent,
    _CategoryRead? notificationRead,
  }) {
    if (_shell.accountSessionDisposed || isCurrent?.call() == false) return;
    final site = _site(siteUrl);
    bool canMerge() =>
        !_shell.accountSessionDisposed &&
        site.lease.isCurrent &&
        identical(_sites[siteUrl], site) &&
        (notificationRead == null || identical(notificationRead.site, site)) &&
        (isCurrent?.call() ?? true);
    if (!canMerge()) return;
    final stored = <TopicCategory>[];
    for (final category in incoming) {
      if (!canMerge()) return;
      final held =
          _shell.store.read<TopicCategory>(siteUrl, category.id) ??
          site.categories?.where((held) => held.id == category.id).firstOrNull;
      final authority = site.categoryNotificationAuthorities[category.id];
      final preserveLevel =
          notificationRead == null ||
          authority?.pending == true ||
          (notificationRead.revisions[category.id] ?? 0) !=
              (authority?.revision ?? 0);
      final incoming = held != null && preserveLevel
          ? category.withNotificationLevel(held.notificationLevel)
          : category;
      stored.add(_shell.store.put(siteUrl, incoming));
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
        feed.loading ||
        feed.loadingMore ||
        !site.lease.isCurrent) {
      return;
    }
    if (site.categoryPageRequest != null) return;

    final lease = site.lease;
    final request = Object();
    final notificationRead = _CategoryRead(site);
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
        mergeCategories(
          siteUrl,
          result.categories,
          isCurrent: requestIsCurrent,
          notificationRead: notificationRead,
        );
        if (!requestIsCurrent()) return;
        site.categoryPageRequest = null;
        final held = site.categoryFeed;
        site.categoryFeed = held.withPage(
          result.rootCategoryIds,
          hasMore: result.rootCategoryIds.isNotEmpty,
        );
        _shell._notify();
      });
    } catch (error) {
      if (!requestIsCurrent()) return;

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

typedef _TagSearchEntry = ({
  String nameKey,
  int rank,
  TopicFilterLookupValue value,
});
typedef _TagSearchEntriesCache = ({
  List<SidebarTag> tags,
  List<_TagSearchEntry> entries,
});

typedef _KnownTagMatch = ({int ordinal, SidebarTag tag});

final class _KnownTagIndex {
  _KnownTagIndex(this.sources) {
    var ordinal = 0;
    for (final tags in [
      sources.personal,
      sources.siteTop,
      sources.anonymousDefaults,
      sources.directory,
    ]) {
      for (final tag in tags) {
        final match = (ordinal: ordinal++, tag: tag);
        _byId.putIfAbsent(tag.id, () => match);
        _byTrimmedName.putIfAbsent(tag.name.trim().toLowerCase(), () => match);
        _byNameOrSlug.putIfAbsent(tag.name.toLowerCase(), () => tag);
        _byNameOrSlug.putIfAbsent(tag.slug.toLowerCase(), () => tag);
      }
    }
  }

  final _TopicListFilterTagSources sources;
  final _byId = <int, _KnownTagMatch>{};
  final _byTrimmedName = <String, _KnownTagMatch>{};
  final _byNameOrSlug = <String, SidebarTag>{};

  SidebarTag? forTopicTag(TopicTag topicTag) {
    final id = topicTag.id;
    final byId = id != null && id > 0 ? _byId[id] : null;
    final byName = _byTrimmedName[topicTag.name.trim().toLowerCase()];
    if (byName == null) return byId?.tag;
    if (byId == null || byName.ordinal < byId.ordinal) return byName.tag;
    return byId.tag;
  }

  SidebarTag? forTopicListTag(String name) => _byNameOrSlug[name.toLowerCase()];
}
