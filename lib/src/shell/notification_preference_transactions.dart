import 'dart:async';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/current_user_reconciler.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../data/topic_tracking_reconciler.dart';
import '../models/discourse_user.dart';
import '../models/post.dart';
import '../models/topic.dart';

final class NotificationPreferenceCurrentUsers {
  const NotificationPreferenceCurrentUsers({
    required this.read,
    required this.reconcilerFor,
    required this.publish,
  });

  final DiscourseUser? Function(String siteUrl) read;
  final CurrentUserReconciler Function(String siteUrl) reconcilerFor;
  final void Function(String siteUrl, SiteLease lease, DiscourseUser user)
  publish;
}

abstract interface class NotificationPreferenceTaxonomy {
  void projectNotificationLevel(
    String siteUrl,
    int categoryId,
    CategoryNotificationLevel level,
    SiteLease lease,
  );
  void invalidateCategorySidebar(String siteUrl);
}

final class NotificationPreferenceTracking {
  const NotificationPreferenceTracking({
    required this.forSite,
    required this.refresh,
  });

  final TopicTrackingReconciler? Function(String siteUrl) forSite;
  final Future<void> Function({
    required String siteUrl,
    required String username,
    required SiteLease lease,
    required TopicTrackingReconciler tracking,
    required TopicTrackingSnapshot ticket,
    required AccountRequestCredentials requestCredentials,
    Future<void> Function()? refreshCategoryPreferences,
  })
  refresh;
}

final class NotificationPreferenceTransactions {
  NotificationPreferenceTransactions({
    required this.store,
    required this.credentials,
    required this.lifecycle,
    required this.topics,
    required this.categories,
    required this.site,
    required this.currentUsers,
    required this.taxonomy,
    required this.trackingEffects,
    required this.topicChanged,
    required this.changed,
  });

  final Store store;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final TopicMutationsApi topics;
  final CategoryMutationsApi categories;
  final ShellSiteApi site;
  final NotificationPreferenceCurrentUsers currentUsers;
  final NotificationPreferenceTaxonomy taxonomy;
  final NotificationPreferenceTracking trackingEffects;
  final void Function(String siteUrl) topicChanged;
  final void Function() changed;
  final Map<String, _NotificationPreferenceSession> _sessions = {};
  bool _disposed = false;

  _NotificationPreferenceSession? _session(String siteUrl) {
    final tracking = trackingEffects.forSite(siteUrl);
    if (tracking == null) return null;
    final held = _sessions[siteUrl];
    if (held != null && held.isCurrent && identical(held.tracking, tracking)) {
      return held;
    }
    held?.retire();
    final account = _NotificationPreferenceSession(
      siteUrl,
      lifecycle.capture(siteUrl),
      tracking,
      currentUsers.reconcilerFor(siteUrl),
    );
    _sessions[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      account.retire();
      if (identical(_sessions[siteUrl], account)) _sessions.remove(siteUrl);
    });
    return account;
  }

  void forget(String siteUrl) => _sessions.remove(siteUrl)?.retire();

  void dispose() {
    _disposed = true;
    for (final account in _sessions.values.toList()) {
      account.retire();
    }
    _sessions.clear();
  }

  Future<bool> updateTopic(
    String siteUrl,
    int topicId,
    TopicNotificationLevel level,
  ) {
    if (_disposed || topicId <= 0) return Future.value(false);
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null) return Future.value(false);

    final account = _session(siteUrl);
    if (account == null) return Future.value(false);
    final key = topicId;
    final tracking = account.tracking;
    final confirmed =
        tracking.notificationLevel(topicId) ?? held.notificationLevel;
    if (confirmed == level && !account.topics.containsKey(key)) {
      if (held.notificationLevel != level) {
        _setTopicNotificationLevel(siteUrl, topicId, level, account.lease);
      }
      return Future.value(account.isCurrent);
    }
    final choice = tracking.chooseNotificationLevel(
      topicId,
      level,
      confirmed: confirmed,
    );
    final heldQueue = account.topics[key];
    final queue = heldQueue != null && heldQueue.isCurrent
        ? heldQueue
        : _TopicNotificationQueue(siteUrl, topicId, account.lease);
    final write = _QueuedTopicNotification(
      level: level,
      tracking: tracking,
      choice: choice,
    );
    late final Future<void> tail;
    tail = queue.tail
        .catchError((_) {})
        .then((_) => _performTopicNotificationWrite(queue, write))
        .whenComplete(() {
          if (!identical(account.topics[key], queue) ||
              !queue.finish(write, tail)) {
            return;
          }
          final _ = account.topics.remove(key);
          write.tracking.releaseNotificationChoice(write.choice);
        });
    queue.admit(write, tail);
    account.topics[key] = queue;
    unawaited(tail);
    _projectTopicNotificationLevel(queue, write, level);
    return write.result.future;
  }

  bool _isLatestTopicNotification(
    _TopicNotificationQueue queue,
    _QueuedTopicNotification write,
  ) => queue.owns(write) && !_disposed;

  Future<void> _performTopicNotificationWrite(
    _TopicNotificationQueue queue,
    _QueuedTopicNotification write,
  ) async {
    bool isLatest() => _isLatestTopicNotification(queue, write);

    if (!isLatest()) {
      write.complete(false);
      return;
    }

    try {
      final credential = await AccountRequestSession(
        queue.siteUrl,
        queue.lease,
      ).credentials(credentials);
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (credential.apiKey == null) {
        _rollbackTopicNotification(queue, write);
        write.complete(false);
        return;
      }
      final clientId = credential.clientId;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      await credential.run(
        () => topics.updateTopicNotificationLevel(
          siteUrl: queue.siteUrl,
          apiKey: credential.apiKey!,
          topicId: queue.topicId,
          notificationLevel: write.level,
          clientId: clientId,
        ),
      );
      if (!queue.isCurrent || _disposed) {
        write.complete(false);
        return;
      }
      final visible = write.tracking.settleNotificationLevel(
        write.choice,
        succeeded: true,
      );
      if (visible != null) {
        _projectTopicNotificationLevel(queue, write, visible);
      }
      write.complete(true);
    } catch (error) {
      if (queue.isCurrent && !_disposed) {
        if (isLatest()) _rollbackTopicNotification(queue, write);
      }
      write.complete(false);
    }
  }

  void _rollbackTopicNotification(
    _TopicNotificationQueue queue,
    _QueuedTopicNotification write,
  ) {
    final visible = write.tracking.settleNotificationLevel(
      write.choice,
      succeeded: false,
    );
    if (visible != null) _projectTopicNotificationLevel(queue, write, visible);
  }

  void _projectTopicNotificationLevel(
    _TopicNotificationQueue queue,
    _QueuedTopicNotification write,
    TopicNotificationLevel level,
  ) {
    if (!_isLatestTopicNotification(queue, write)) return;
    _setTopicNotificationLevel(
      queue.siteUrl,
      queue.topicId,
      level,
      queue.lease,
    );
  }

  void observeTopicMessage(
    String siteUrl,
    int topicId,
    Object? data,
    SiteLease lease,
  ) {
    if (_disposed || !lease.isCurrent || data is! Map) return;
    final value = data['notification_level_change'];
    if (value is! int || value < 0 || value > 3) return;
    final level = TopicNotificationLevel.fromJson(value);
    final account = _session(siteUrl);
    if (account == null || !identical(account.lease.session, lease.session)) {
      return;
    }
    final visible = account.tracking.observeNotificationLevel(topicId, level);
    _setTopicNotificationLevel(siteUrl, topicId, visible, lease);
  }

  void _setTopicNotificationLevel(
    String siteUrl,
    int topicId,
    TopicNotificationLevel level,
    SiteLease lease,
  ) {
    if (!lease.isCurrent || _disposed) return;
    store.update<TopicDetail>(
      siteUrl,
      topicId,
      (topic) => topic.withNotificationLevel(level),
    );
    if (lease.isCurrent && !_disposed) topicChanged(siteUrl);
  }

  Future<bool> updateCategory(
    String siteUrl,
    int categoryId,
    CategoryNotificationLevel level,
  ) {
    if (_disposed || categoryId <= 0) return Future.value(false);
    final held = store.read<TopicCategory>(siteUrl, categoryId);
    if (held == null) return Future.value(false);

    final account = _session(siteUrl);
    if (account == null) return Future.value(false);
    if (held.notificationLevel == level &&
        account.category(categoryId) == null) {
      return Future.value(true);
    }
    final queue =
        account.category(categoryId) ??
        _CategoryNotificationQueue(account, categoryId, held.notificationLevel);
    final write = _QueuedCategoryNotification(level: level);
    // The response includes a site-wide inherited mute list. Serialize category
    // writes across the account so an older response cannot undo another edit.
    late final Future<void> tail;
    tail = account.tail
        .catchError((_) {})
        .then((_) => _performCategoryNotificationWrite(queue, write))
        .whenComplete(() {
          account.finish(queue, write, tail);
        });
    account.admit(queue, write, tail);
    unawaited(tail);
    _projectCategoryNotificationLevel(queue, write, level);
    return write.result.future;
  }

  bool _isLatestCategoryNotification(
    _CategoryNotificationQueue queue,
    _QueuedCategoryNotification write,
  ) => queue.owns(write) && !_disposed;

  Future<void> _performCategoryNotificationWrite(
    _CategoryNotificationQueue queue,
    _QueuedCategoryNotification write,
  ) async {
    bool isLatest() => _isLatestCategoryNotification(queue, write);

    if (!isLatest()) {
      write.complete(false);
      return;
    }

    late final String apiKey;
    late final String clientId;
    late final AccountRequestCredentials requestCredentials;
    final List<int>? indirectlyMuted;
    try {
      final credential = await AccountRequestSession(
        queue.account.siteUrl,
        queue.account.lease,
      ).credentials(credentials);
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      if (credential.apiKey == null) {
        _rollbackCategoryNotification(queue, write);
        write.complete(false);
        return;
      }
      apiKey = credential.apiKey!;
      clientId = credential.clientId;
      requestCredentials = credential;
      if (!isLatest()) {
        write.complete(false);
        return;
      }
      indirectlyMuted = await credential.run(
        () => categories.updateCategoryNotificationLevel(
          siteUrl: queue.account.siteUrl,
          apiKey: apiKey,
          categoryId: queue.categoryId,
          notificationLevel: write.level,
          clientId: clientId,
        ),
      );
    } catch (error) {
      if (queue.account.isCurrent && !_disposed) {
        if (isLatest()) _rollbackCategoryNotification(queue, write);
      }
      write.complete(false);
      return;
    }

    if (!queue.account.isCurrent || _disposed) {
      write.complete(false);
      return;
    }
    queue.confirm(write.level);
    try {
      final currentUserOwner = queue.account.currentUser;
      final categoryTicket = currentUserOwner.categoryPreferencesChanged();
      final user = currentUsers.read(queue.account.siteUrl);
      if (user != null) {
        List<int>? membership(
          List<int>? ids,
          CategoryNotificationLevel level,
        ) => ids == null
            ? null
            : List.unmodifiable({
                for (final id in ids)
                  if (id != queue.categoryId) id,
                if (write.level == level) queue.categoryId,
              });
        _commitCategoryNotificationPreferences(
          queue.account,
          user.withCategoryNotificationPreferences(
            trackedCategoryIds: membership(
              user.trackedCategoryIds,
              CategoryNotificationLevel.tracking,
            ),
            watchedCategoryIds: membership(
              user.watchedCategoryIds,
              CategoryNotificationLevel.watching,
            ),
            watchedFirstPostCategoryIds: membership(
              user.watchedFirstPostCategoryIds,
              CategoryNotificationLevel.watchingFirstPost,
            ),
            mutedCategoryIds: membership(
              user.mutedCategoryIds,
              CategoryNotificationLevel.muted,
            ),
            indirectlyMutedCategoryIds:
                indirectlyMuted ?? user.indirectlyMutedCategoryIds,
          ),
        );
      }
      _projectCategoryNotificationLevel(queue, write, write.level);
      if (!queue.account.isCurrent || _disposed) return;
      final username = currentUsers.read(queue.account.siteUrl)?.username;
      if (username == null) return;
      final tracking = queue.account.tracking;
      final ticket = tracking.beginSnapshot(replace: true);
      if (ticket == null) return;
      trackingEffects
          .refresh(
            siteUrl: queue.account.siteUrl,
            username: username,
            lease: queue.account.lease,
            tracking: tracking,
            ticket: ticket,
            requestCredentials: requestCredentials,
            refreshCategoryPreferences:
                indirectlyMuted == null ||
                    user?.followedCategoryIds == null ||
                    user?.mutedCategoryIds == null
                ? () async {
                    final response = await requestCredentials.run(
                      () => site.currentUser(
                        siteUrl: queue.account.siteUrl,
                        apiKey: apiKey,
                        clientId: clientId,
                      ),
                    );
                    if (!queue.account.isCurrent || _disposed) return;
                    final held = currentUsers.read(queue.account.siteUrl);
                    if (!currentUserOwner.acceptsCategoryPreferences(
                      categoryTicket,
                      previous: held,
                      incoming: response,
                    )) {
                      return;
                    }
                    _commitCategoryNotificationPreferences(
                      queue.account,
                      response,
                    );
                  }
                : null,
          )
          .ignore();
      changed();
    } catch (_) {
    } finally {
      write.complete(true);
    }
  }

  void _commitCategoryNotificationPreferences(
    _NotificationPreferenceSession account,
    DiscourseUser preferences,
  ) {
    if (!account.isCurrent) return;
    final siteUrl = account.siteUrl;
    final user = currentUsers.read(siteUrl);
    if (user == null) return;
    final updated = user.withCategoryNotificationPreferences(
      trackedCategoryIds:
          preferences.trackedCategoryIds ?? user.trackedCategoryIds,
      watchedCategoryIds:
          preferences.watchedCategoryIds ?? user.watchedCategoryIds,
      watchedFirstPostCategoryIds:
          preferences.watchedFirstPostCategoryIds ??
          user.watchedFirstPostCategoryIds,
      mutedCategoryIds: preferences.mutedCategoryIds ?? user.mutedCategoryIds,
      indirectlyMutedCategoryIds:
          preferences.indirectlyMutedCategoryIds ??
          user.indirectlyMutedCategoryIds,
    );
    currentUsers.publish(siteUrl, account.lease, updated);
    if (account.isCurrent) taxonomy.invalidateCategorySidebar(siteUrl);
  }

  void _rollbackCategoryNotification(
    _CategoryNotificationQueue queue,
    _QueuedCategoryNotification write,
  ) {
    _projectCategoryNotificationLevel(queue, write, queue.confirmed);
  }

  void _projectCategoryNotificationLevel(
    _CategoryNotificationQueue queue,
    _QueuedCategoryNotification write,
    CategoryNotificationLevel level,
  ) {
    if (!_isLatestCategoryNotification(queue, write)) return;
    taxonomy.projectNotificationLevel(
      queue.account.siteUrl,
      queue.categoryId,
      level,
      queue.account.lease,
    );
  }
}

final class _TopicNotificationQueue {
  _TopicNotificationQueue(this.siteUrl, this.topicId, this.lease);

  final String siteUrl;
  final int topicId;
  final SiteLease lease;
  _QueuedTopicNotification? _latest;
  Future<void>? _tail;
  bool _retired = false;

  bool get isCurrent => !_retired && lease.isCurrent;
  Future<void> get tail => _tail ?? Future.value();

  bool owns(_QueuedTopicNotification write) =>
      isCurrent && identical(_latest, write);

  void admit(_QueuedTopicNotification write, Future<void> tail) {
    _latest = write;
    _tail = tail;
  }

  bool finish(_QueuedTopicNotification write, Future<void> tail) {
    if (_retired || !identical(_latest, write) || !identical(_tail, tail)) {
      return false;
    }
    _latest = null;
    _tail = null;
    return true;
  }

  void retire() {
    _retired = true;
    _latest = null;
    _tail = null;
  }
}

final class _NotificationPreferenceSession {
  _NotificationPreferenceSession(
    this.siteUrl,
    this.lease,
    this.tracking,
    this.currentUser,
  );

  final TopicTrackingReconciler tracking;
  final CurrentUserReconciler currentUser;
  final Map<int, _TopicNotificationQueue> topics = {};
  void Function()? detach;

  final String siteUrl;
  final SiteLease lease;
  final Map<int, _CategoryNotificationQueue> _categories = {};
  Future<void>? _tail;
  bool _retired = false;

  bool get isCurrent => !_retired && lease.isCurrent;
  Future<void> get tail => _tail ?? Future.value();

  _CategoryNotificationQueue? category(int categoryId) =>
      _categories[categoryId];

  bool owns(_CategoryNotificationQueue queue) =>
      isCurrent && identical(_categories[queue.categoryId], queue);

  void admit(
    _CategoryNotificationQueue queue,
    _QueuedCategoryNotification write,
    Future<void> tail,
  ) {
    queue._admit(write, tail);
    _categories[queue.categoryId] = queue;
    _tail = tail;
  }

  void finish(
    _CategoryNotificationQueue queue,
    _QueuedCategoryNotification write,
    Future<void> tail,
  ) {
    if (_retired ||
        !identical(_categories[queue.categoryId], queue) ||
        !queue._finish(write, tail)) {
      return;
    }
    _categories.remove(queue.categoryId);
    if (identical(_tail, tail)) _tail = null;
  }

  void retire() {
    _retired = true;
    detach?.call();
    detach = null;
    for (final queue in topics.values) {
      queue.retire();
    }
    topics.clear();
    _categories.clear();
    _tail = null;
  }
}

final class _CategoryNotificationQueue {
  _CategoryNotificationQueue(this.account, this.categoryId, this._confirmed);

  final _NotificationPreferenceSession account;
  final int categoryId;
  CategoryNotificationLevel _confirmed;
  _QueuedCategoryNotification? _latest;
  Future<void>? _tail;

  CategoryNotificationLevel get confirmed => _confirmed;

  bool owns(_QueuedCategoryNotification write) =>
      account.owns(this) && identical(_latest, write);

  void confirm(CategoryNotificationLevel level) {
    _confirmed = level;
  }

  void _admit(_QueuedCategoryNotification write, Future<void> tail) {
    _latest = write;
    _tail = tail;
  }

  bool _finish(_QueuedCategoryNotification write, Future<void> tail) {
    if (!identical(_latest, write) || !identical(_tail, tail)) {
      return false;
    }
    _latest = null;
    _tail = null;
    return true;
  }
}

final class _QueuedTopicNotification {
  _QueuedTopicNotification({
    required this.level,
    required this.tracking,
    required this.choice,
  });

  final TopicNotificationLevel level;
  final TopicTrackingReconciler tracking;
  final TopicTrackingChoice choice;
  final Completer<bool> result = Completer<bool>();

  void complete(bool succeeded) {
    if (!result.isCompleted) result.complete(succeeded);
  }
}

final class _QueuedCategoryNotification {
  _QueuedCategoryNotification({required this.level});

  final CategoryNotificationLevel level;
  final Completer<bool> result = Completer<bool>();

  void complete(bool succeeded) {
    if (!result.isCompleted) result.complete(succeeded);
  }
}
