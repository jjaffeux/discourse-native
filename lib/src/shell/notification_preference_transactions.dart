part of 'shell_controller.dart';

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

final class _CategoryNotificationAccount {
  _CategoryNotificationAccount(this.siteUrl, this.lease);

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

  bool finish(
    _CategoryNotificationQueue queue,
    _QueuedCategoryNotification write,
    Future<void> tail,
  ) {
    if (_retired ||
        !identical(_categories[queue.categoryId], queue) ||
        !queue._finish(write, tail)) {
      return false;
    }
    _categories.remove(queue.categoryId);
    if (identical(_tail, tail)) _tail = null;
    return _tail == null && _categories.isEmpty;
  }

  void retire() {
    _retired = true;
    _categories.clear();
    _tail = null;
  }
}

final class _CategoryNotificationQueue {
  _CategoryNotificationQueue(this.account, this.categoryId, this._confirmed);

  final _CategoryNotificationAccount account;
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
