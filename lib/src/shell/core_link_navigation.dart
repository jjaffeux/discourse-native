part of 'shell_controller.dart';

typedef _ResolvedCoreLink = ({ContentRoute route, String siteUrl});

enum _CoreLinkIntent { ordinary, notification }

extension _CoreLinkNavigation on ShellController {
  bool _isCorePageLink(ContentRoute route) =>
      switch (ContentPageContract.resolve(route).coreUrl) {
        CoreUrlPolicy.direct => true,
        CoreUrlPolicy.registeredHomepage =>
          plugins.registry.homepage(route.id) != null,
        CoreUrlPolicy.specialized => false,
      };

  bool _openResolvedCoreLink(
    _ResolvedCoreLink destination,
    _CoreLinkIntent intent,
  ) {
    final route = destination.route;
    final corePage = _isCorePageLink(route);
    if (!corePage &&
        route.destination is! BadgeDestination &&
        route.destination is! GroupDestination &&
        route.destination is! TopicDestination &&
        !route.isTaxonomyList) {
      return false;
    }
    final index = _instances.indexWhere(
      (instance) => instance.url == destination.siteUrl,
    );
    if (index < 0) return false;
    final instance = _instances[index];
    if (index != _instanceIndex) selectInstance(index);
    final rootChanged = _setForumContentRoot();
    final refresh = intent == _CoreLinkIntent.notification;

    if (corePage) {
      if (route.sameDestinationAs(currentContent)) {
        _workspace.consumeHomepage(activeTabId);
        if (rootChanged) _notify();
        return true;
      }
      pushContent(route);
      unawaited(
        _loadPage(
          focusedTabContext,
          route,
          ContentPageContract.resolve(route).urlLoad,
        ),
      );
      return true;
    }

    switch (route.destination) {
      case BadgeDestination(route: final badge):
        if (currentContent?.badgeRoute != badge) {
          pushContent(route);
        } else if (rootChanged) {
          _notify();
        }
        unawaited(badges.load(instance, badge, refresh: refresh));
      case GroupDestination(route: final group):
        if (currentContent?.groupRoute == group) {
          if (rootChanged) _notify();
          return true;
        }
        pushContent(route);
        if (route.feedPath != null) unawaited(loadFeed(route.id));
      case TopicDestination(:final topicId, :final slug, :final postNumber):
        if (currentContent?.topicId == topicId) {
          final targetPost = refresh ? postNumber ?? 1 : postNumber;
          if (targetPost != null) {
            openCurrentTopicPost(targetPost, loadAroundPost: refresh);
          } else if (rootChanged) {
            _notify();
          }
          return true;
        }
        _openTopic(
          topicId,
          slug ?? '',
          route.title,
          postNumber: postNumber,
          force: refresh,
          resetScrollPosition: postNumber != null,
        );
      case FeedDestination():
        if (route.sameDestinationAs(currentContent)) {
          if (rootChanged) _notify();
          return true;
        }
        pushContent(route);
        unawaited(loadFeed(route.id));
      default:
        return false;
    }
    return true;
  }
}
