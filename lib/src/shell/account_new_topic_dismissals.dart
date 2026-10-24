import 'package:flutter/foundation.dart' show immutable;

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';

@immutable
final class DismissNewTopicsCommand {
  const DismissNewTopicsCommand({
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

enum DismissNewTopicsFailure { reconnect, failed }

final class NewTopicDismissals {
  NewTopicDismissals({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.acceptTracking,
    required this.reloadSource,
    required this.changed,
  });

  final TopicFeedsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final void Function(String siteUrl, SiteLease lease, Object? message)
  acceptTracking;
  final Future<void> Function(DismissNewTopicsCommand command, SiteLease lease)
  reloadSource;
  final void Function() changed;
  final Map<String, _AccountNewTopicDismissals> _accounts = {};
  bool _disposed = false;

  bool isBusy(String? siteUrl) => _accounts[siteUrl]?.isBusy ?? false;

  _AccountNewTopicDismissals _account(String siteUrl) {
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent) return held;
    held?.retire();
    final account = _AccountNewTopicDismissals(
      AccountRequestSession(siteUrl, lifecycle.capture(siteUrl)),
    );
    _accounts[siteUrl] = account;
    account.detach = account.request.lease.onRetire(() {
      account.retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
    });
    return account;
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?.retire();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final account in _accounts.values) {
      account.retire();
    }
    _accounts.clear();
  }

  Future<DismissNewTopicsFailure?> dismiss(
    DismissNewTopicsCommand scope,
  ) async {
    if (_disposed) return null;
    final account = _account(scope.instance.url);
    final siteUrl = account.request.siteUrl;
    final lease = account.request.lease;
    if (!account.isCurrent || account.busy) return null;
    account.busy = true;
    changed();
    final route = scope.route;
    final topics = scope.dismissTopics;
    final posts = scope.dismissPosts;
    try {
      final credential = await account.request.credentials(credentials);
      if (!account.isCurrent) return null;
      if (credential.apiKey == null) {
        return DismissNewTopicsFailure.reconnect;
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
            () => api.topicList(
              siteUrl: siteUrl,
              path: requestPath,
              apiKey: credential.apiKey,
              clientId: credential.clientId,
            ),
          );
          if (!account.isCurrent) return null;
          topicIds.addAll(page.topics.map((topic) => topic.id));
          path = page.nextPagePath;
        }
        if (path != null) {
          throw StateError('Could not load all matching topics.');
        }
      }
      if (!account.isCurrent) return null;
      final ids = await credential.run(
        () => api.dismissNewTopics(
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
      if (!account.isCurrent) return null;
      for (final type in [
        if (topics) 'dismiss_new',
        if (posts) 'dismiss_new_posts',
      ]) {
        if (!account.isCurrent) return null;
        acceptTracking(siteUrl, lease, {
          'message_type': type,
          'payload': {'topic_ids': ids},
        });
      }
      if (!account.isCurrent) return null;
      await reloadSource(scope, lease);
      return null;
    } catch (error) {
      if (!account.isCurrent) return null;

      return DismissNewTopicsFailure.failed;
    } finally {
      account.busy = false;
      if (account.isCurrent) changed();
    }
  }
}

final class _AccountNewTopicDismissals {
  _AccountNewTopicDismissals(this.request);

  final AccountRequestSession request;
  bool busy = false;
  bool _retired = false;
  void Function()? detach;

  bool get isCurrent => !_retired && request.lease.isCurrent;
  bool get isBusy => isCurrent && busy;

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
  }
}
