part of 'shell_controller.dart';

@immutable
final class _DismissNewTopicsScope {
  const _DismissNewTopicsScope({
    required this.instance,
    required this.route,
    required this.mode,
    required this.tagName,
  });

  final DiscourseInstance instance;
  final ContentRoute route;
  final TopicListMode mode;
  final String? tagName;

  bool get dismissTopics => mode != TopicListMode.newReplies;
  bool get dismissPosts =>
      instance.user?.unifiedNewEnabled == true &&
      mode != TopicListMode.newTopics;
}

enum _DismissNewTopicsFailure { reconnect, failed }

final class _AccountNewTopicDismissals {
  _AccountNewTopicDismissals(this._shell, this._session);

  final ShellController _shell;
  final AccountRequestSession _session;
  bool _busy = false;

  bool get isBusy => _session.lease.isCurrent && _busy;

  Future<_DismissNewTopicsFailure?> dismiss(
    _DismissNewTopicsScope scope,
  ) async {
    final siteUrl = _session.siteUrl;
    final lease = _session.lease;
    if (!lease.isCurrent || _shell._tabContextDisposed || _busy) return null;
    _busy = true;
    _shell._notify();
    final route = scope.route;
    final topics = scope.dismissTopics;
    final posts = scope.dismissPosts;
    try {
      final credential = await _session.credentials(_shell.credentials);
      if (credential.apiKey == null || !lease.isCurrent) {
        return _DismissNewTopicsFailure.reconnect;
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
            () => _shell.api.topicFeeds.topicList(
              siteUrl: siteUrl,
              path: requestPath,
              apiKey: credential.apiKey,
              clientId: credential.clientId,
            ),
          );
          if (!lease.isCurrent || _shell._tabContextDisposed) return null;
          topicIds.addAll(page.topics.map((topic) => topic.id));
          path = page.nextPagePath;
        }
        if (path != null) {
          throw StateError('Could not load all matching topics.');
        }
      }
      if (!lease.isCurrent || _shell._tabContextDisposed) return null;
      final ids = await credential.run(
        () => _shell.api.topicFeeds.dismissNewTopics(
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
      if (!lease.isCurrent || _shell._tabContextDisposed) return null;
      for (final type in [
        if (topics) 'dismiss_new',
        if (posts) 'dismiss_new_posts',
      ]) {
        _shell._applyTopicTrackingMessage(siteUrl, {
          'message_type': type,
          'payload': {'topic_ids': ids},
        });
      }
      await _shell.topicFeeds.load(
        instance: scope.instance,
        destinationId: route.id,
        path: route.feedPath!,
        incoming: _shell._liveSessions.trackerFor(siteUrl)?.incoming,
        force: true,
      );
      return null;
    } catch (error) {
      if (!lease.isCurrent || _shell._tabContextDisposed) return null;

      return _DismissNewTopicsFailure.failed;
    } finally {
      _busy = false;
      if (!_shell._tabContextDisposed) _shell._notify();
    }
  }
}
