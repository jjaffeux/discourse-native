import '../models/content_route.dart';
import 'global_search_models.dart';

enum PageLoad {
  feed,
  rootFeed,
  pathFeed,
  topic,
  badge,
  categories,
  tags,
  users,
  drafts,
  summary,
  activity,
  bookmarks,
  preferences,
  extension,
  extensionRoot,
}

enum CoreUrlPolicy { specialized, direct, registeredHomepage }

enum PageRetry { feature, unavailableExtension }

enum PageHeader { none, title, searchOnly }

enum _PageTitle { shell, page, connectedPage }

enum _ShellHeader { standard, none, desktopHidden, connectedHidden }

final class ContentPageContract {
  const ContentPageContract._({
    this.rootLoad,
    this.currentLoad,
    this.loadCurrentAtRoot = false,
    this.urlLoad,
    this.selectionLoad,
    this.reselectionLoad,
    this.refreshLoad,
    this.coreUrl = CoreUrlPolicy.specialized,
    this.retry = PageRetry.feature,
    this.searchScope,
    this._title = _PageTitle.shell,
    this._header = _ShellHeader.standard,
    this.showSearchWords = true,
    this.allowsTopicCreation = true,
  });

  final PageLoad? rootLoad;
  final PageLoad? currentLoad;
  final bool loadCurrentAtRoot;
  final PageLoad? urlLoad;
  final PageLoad? selectionLoad;
  final PageLoad? reselectionLoad;
  final PageLoad? refreshLoad;
  final CoreUrlPolicy coreUrl;
  final PageRetry retry;
  final GlobalSearchScope? searchScope;
  final _PageTitle _title;
  final _ShellHeader _header;
  final bool showSearchWords;
  final bool allowsTopicCreation;

  PageLoad? loadOnSelection({required bool refresh}) =>
      refresh ? reselectionLoad ?? selectionLoad : selectionLoad;

  PageHeader headerFor({
    required bool hasSite,
    required bool connected,
    required bool touch,
    required bool canPop,
    required bool mobileNavigation,
    required bool nativeTitleBar,
    required bool pluginOwnsChrome,
    bool? pluginPageTitle,
  }) {
    final pageTitle =
        hasSite &&
        (pluginPageTitle ??
            switch (_title) {
              _PageTitle.shell => false,
              _PageTitle.page => true,
              _PageTitle.connectedPage => connected,
            });
    if (pluginOwnsChrome ||
        _header == _ShellHeader.none ||
        (_header == _ShellHeader.desktopHidden && !touch) ||
        (_header == _ShellHeader.connectedHidden && connected) ||
        (pageTitle && !canPop && (mobileNavigation || nativeTitleBar))) {
      return PageHeader.none;
    }
    return pageTitle ? PageHeader.searchOnly : PageHeader.title;
  }

  static ContentPageContract resolve(ContentRoute route) =>
      switch (route.destination) {
        TopicDestination() => const ContentPageContract._(
          currentLoad: PageLoad.topic,
          loadCurrentAtRoot: true,
          refreshLoad: PageLoad.topic,
          searchScope: GlobalSearchScope.forum,
          header: _ShellHeader.none,
          allowsTopicCreation: false,
        ),
        FeedDestination(:final mode) => ContentPageContract._(
          rootLoad: PageLoad.feed,
          currentLoad: PageLoad.feed,
          urlLoad: PageLoad.feed,
          selectionLoad: PageLoad.feed,
          refreshLoad: PageLoad.feed,
          coreUrl: mode == null
              ? CoreUrlPolicy.specialized
              : CoreUrlPolicy.direct,
          searchScope: GlobalSearchScope.forum,
        ),
        MessagesDestination() => const ContentPageContract._(
          rootLoad: PageLoad.feed,
          currentLoad: PageLoad.feed,
          urlLoad: PageLoad.feed,
          selectionLoad: PageLoad.feed,
          refreshLoad: PageLoad.feed,
          coreUrl: CoreUrlPolicy.direct,
          searchScope: GlobalSearchScope.messages,
        ),
        GroupDestination(route: final group) => ContentPageContract._(
          rootLoad: PageLoad.rootFeed,
          currentLoad: PageLoad.pathFeed,
          selectionLoad: PageLoad.feed,
          refreshLoad: PageLoad.feed,
          searchScope: group.isDirectory ? GlobalSearchScope.groups : null,
          title: group.isDirectory ? _PageTitle.page : _PageTitle.shell,
          header: group.isDirectory ? _ShellHeader.none : _ShellHeader.standard,
        ),
        BadgeDestination(route: final badge) => ContentPageContract._(
          currentLoad: PageLoad.badge,
          loadCurrentAtRoot: true,
          selectionLoad: PageLoad.badge,
          refreshLoad: PageLoad.badge,
          title: badge.isDirectory ? _PageTitle.page : _PageTitle.shell,
          header: _ShellHeader.none,
          allowsTopicCreation: false,
        ),
        PageDestination(:final page) => switch (page) {
          CorePage.start => const ContentPageContract._(),
          CorePage.categories => const ContentPageContract._(
            rootLoad: PageLoad.categories,
            urlLoad: PageLoad.categories,
            selectionLoad: PageLoad.categories,
            refreshLoad: PageLoad.categories,
            coreUrl: CoreUrlPolicy.direct,
            searchScope: GlobalSearchScope.categories,
            title: _PageTitle.page,
            header: _ShellHeader.none,
            showSearchWords: false,
          ),
          CorePage.tags => const ContentPageContract._(
            urlLoad: PageLoad.tags,
            reselectionLoad: PageLoad.tags,
            refreshLoad: PageLoad.tags,
            coreUrl: CoreUrlPolicy.direct,
            searchScope: GlobalSearchScope.tags,
            title: _PageTitle.page,
            header: _ShellHeader.none,
          ),
          CorePage.users => const ContentPageContract._(
            rootLoad: PageLoad.users,
            currentLoad: PageLoad.users,
            urlLoad: PageLoad.users,
            selectionLoad: PageLoad.users,
            refreshLoad: PageLoad.users,
            coreUrl: CoreUrlPolicy.direct,
            searchScope: GlobalSearchScope.users,
            title: _PageTitle.page,
            header: _ShellHeader.desktopHidden,
            allowsTopicCreation: false,
          ),
          CorePage.drafts => const ContentPageContract._(
            refreshLoad: PageLoad.drafts,
            title: _PageTitle.page,
            header: _ShellHeader.none,
          ),
          CorePage.summary => const ContentPageContract._(
            refreshLoad: PageLoad.summary,
            header: _ShellHeader.desktopHidden,
          ),
          CorePage.bookmarks => const ContentPageContract._(
            selectionLoad: PageLoad.bookmarks,
            refreshLoad: PageLoad.bookmarks,
            title: _PageTitle.connectedPage,
            header: _ShellHeader.connectedHidden,
          ),
          CorePage.activity => const ContentPageContract._(
            refreshLoad: PageLoad.activity,
            header: _ShellHeader.none,
            allowsTopicCreation: false,
          ),
          CorePage.preferences => const ContentPageContract._(
            refreshLoad: PageLoad.preferences,
            header: _ShellHeader.none,
          ),
          CorePage.appearance => const ContentPageContract._(
            title: _PageTitle.page,
            header: _ShellHeader.desktopHidden,
          ),
          CorePage.dashboard => const ContentPageContract._(
            coreUrl: CoreUrlPolicy.direct,
            title: _PageTitle.page,
            header: _ShellHeader.none,
            allowsTopicCreation: false,
            showSearchWords: false,
          ),
          CorePage.forumAbout => const ContentPageContract._(
            coreUrl: CoreUrlPolicy.direct,
            title: _PageTitle.page,
            allowsTopicCreation: false,
          ),
        },
        ExtensionDestination() => const ContentPageContract._(
          rootLoad: PageLoad.extensionRoot,
          currentLoad: PageLoad.extension,
          loadCurrentAtRoot: true,
          urlLoad: PageLoad.feed,
          selectionLoad: PageLoad.extensionRoot,
          refreshLoad: PageLoad.extension,
          coreUrl: CoreUrlPolicy.registeredHomepage,
          retry: PageRetry.unavailableExtension,
        ),
      };
}
