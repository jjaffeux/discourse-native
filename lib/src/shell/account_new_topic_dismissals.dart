import 'package:flutter/foundation.dart' show immutable;

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import 'topic_tracking_directory.dart';

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

  /// Core's reset-new takes one tag and never reads the list's search, so a
  /// list narrowed further is dismissed by the topic ids it lists.
  bool get listsTopicIds =>
      route.tagNames.length > 1 || route.topicListSearch.isNotEmpty;

  /// Without a category or tag, reset-new also moves `new_since`, clearing
  /// New forum-wide whatever topic ids it is given.
  bool get widensToForum => route.categoryId == null && tagName == null;

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
    required this.trackingFor,
    required this.reloadSource,
    required this.changed,
  });

  final TopicFeedsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final TopicTrackingAdmission? Function(String siteUrl, SiteLease lease)
  trackingFor;
  final Future<void> Function(DismissNewTopicsCommand command, SiteLease lease)
  reloadSource;
  final void Function() changed;
  final Map<String, _AccountNewTopicDismissals> _accounts = {};
  bool _disposed = false;

  bool isBusy(String? siteUrl) => _accounts[siteUrl]?.isBusy ?? false;

  _AccountNewTopicDismissals? _account(DismissNewTopicsCommand scope) {
    final siteUrl = scope.instance.url;
    final lease = lifecycle.capture(siteUrl);
    final tracking = trackingFor(siteUrl, lease);
    if (tracking == null ||
        !tracking.isCurrent ||
        !tracking.belongsTo(scope.instance.user)) {
      return null;
    }
    final held = _accounts[siteUrl];
    if (held != null && held.isCurrent && identical(held.tracking, tracking)) {
      return held;
    }
    held?.retire();
    final account = _AccountNewTopicDismissals(
      AccountRequestSession(siteUrl, lease),
      tracking,
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
    final account = _account(scope);
    if (account == null) return null;
    final siteUrl = account.request.siteUrl;
    final lease = account.request.lease;
    if (!account.isCurrent || account.busy) return null;
    account.busy = true;
    changed();
    final route = scope.route;
    final topics = scope.dismissTopics;
    final posts = scope.dismissPosts;
    try {
      if (!account.isCurrent) return null;
      final credential = await account.request.credentials(credentials);
      if (!account.isCurrent) return null;
      if (credential.apiKey == null) {
        return DismissNewTopicsFailure.reconnect;
      }
      List<int>? topicIds;
      if (scope.listsTopicIds) {
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
        account.tracking.accept({
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
  _AccountNewTopicDismissals(this.request, this.tracking);

  final AccountRequestSession request;
  final TopicTrackingAdmission tracking;
  bool busy = false;
  bool _retired = false;
  void Function()? detach;

  bool get isCurrent =>
      !_retired && request.lease.isCurrent && tracking.isCurrent;
  bool get isBusy => isCurrent && busy;

  void retire() {
    if (_retired) return;
    _retired = true;
    detach?.call();
    detach = null;
  }
}
