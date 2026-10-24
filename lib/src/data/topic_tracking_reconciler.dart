import '../models/discourse_user.dart';
import '../models/json.dart';
import '../models/sidebar.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../models/topic_tracking_message_filter.dart';
import '../models/topic_tracking_state.dart';

enum TopicTrackingPhase { unseeded, loading, live, retrying }

/// Reconciles reports, accepted events and local intentions for one account.
/// Transport, write serialization and publication remain with the caller.
final class TopicTrackingReconciler {
  TopicTrackingReconciler({
    bool Function()? isCurrent,
    DateTime Function()? clock,
  }) : _isCurrent = isCurrent ?? _alwaysCurrent,
       _filter = TopicTrackingMessageFilter(clock: clock);

  static bool _alwaysCurrent() => true;

  final bool Function() _isCurrent;
  final TopicTrackingMessageFilter _filter;
  TopicTrackingState _state = TopicTrackingState();
  TopicTrackingSnapshot? _load;
  TopicTrackingSnapshot? _bootstrap;
  final List<Object?> _events = [];
  final Map<int, int> _localReads = {};
  final Map<int, TopicTrackingChoice> _choices = {};
  final Map<int, _NotificationAuthority> _notificationAuthorities = {};
  bool _retired = false;
  bool _hasSnapshot = false;
  bool _retrying = false;
  int _revision = 0;

  bool get _current => !_retired && _isCurrent();
  bool get hasSnapshot => _hasSnapshot;
  int get revision => _revision;
  TopicTrackingPhase get phase => _load != null
      ? TopicTrackingPhase.loading
      : _retrying
      ? TopicTrackingPhase.retrying
      : _hasSnapshot
      ? TopicTrackingPhase.live
      : TopicTrackingPhase.unseeded;

  TrackedTopicState? topic(int id) => _state.topic(id);
  Iterable<TrackedTopicState> get topics => _state.topics;
  ({int newTopics, int newReplies}) get newActivityCounts =>
      _state.newActivityCounts;

  ({int newTopics, int newReplies}) newActivityCountsFor({
    int? categoryId,
    Iterable<TopicCategory> categories = const [],
    Set<int> tagIds = const {},
  }) => _state.newActivityCountsFor(
    categoryId: categoryId,
    categories: categories,
    tagIds: tagIds,
  );

  SidebarBadge categoryBadge({
    required int categoryId,
    required Iterable<TopicCategory> categories,
    required bool unifiedNew,
    required bool showCount,
  }) => _state.categoryBadge(
    categoryId: categoryId,
    categories: categories,
    unifiedNew: unifiedNew,
    showCount: showCount,
  );

  SidebarBadge tagBadge({
    required int tagId,
    required bool unifiedNew,
    required bool showCount,
  }) => _state.tagBadge(
    tagId: tagId,
    unifiedNew: unifiedNew,
    showCount: showCount,
  );

  /// Opens capture before bootstrap IO without displacing a report in flight.
  TopicTrackingSnapshot beginBootstrap() {
    if (_hasSnapshot && _load == null) _events.clear();
    return _bootstrap = TopicTrackingSnapshot._(this);
  }

  bool completeBootstrap(
    TopicTrackingSnapshot ticket,
    TopicTrackingState report,
  ) {
    if (!_current || !identical(_bootstrap, ticket) || _load != null) {
      return false;
    }
    _install(report);
    return true;
  }

  void cancelBootstrap(TopicTrackingSnapshot ticket) {
    if (identical(_bootstrap, ticket)) _bootstrap = null;
  }

  /// A category refresh replaces older loads. Ordinary reads share an active
  /// load. Unseeded native choices survive the first report's dispatch.
  TopicTrackingSnapshot? beginSnapshot({bool replace = false}) {
    if (!_current || (_load != null && !replace)) return null;
    _bootstrap = null;
    if (_hasSnapshot || replace) _events.clear();
    _retrying = false;
    return _load = TopicTrackingSnapshot._(this);
  }

  bool owns(TopicTrackingSnapshot ticket) =>
      _current && identical(_load, ticket);

  /// The authoritative preference read precedes the report. Earlier bus
  /// observations no longer describe its category policy; local overlays do.
  bool preferencesReady(TopicTrackingSnapshot ticket) {
    if (!owns(ticket)) return false;
    _events.clear();
    return true;
  }

  bool completeSnapshot(
    TopicTrackingSnapshot ticket,
    TopicTrackingState report,
  ) {
    if (!owns(ticket)) return false;
    _install(report);
    return true;
  }

  void _install(TopicTrackingState report) {
    final complete = report.topics.length < TopicTrackingState.maxReportTopics;
    for (final event in _events) {
      report.applyMessage(event);
    }
    for (final topic in report.topics.toList()) {
      _overlay(report, topic.topicId);
    }
    report.keepOmitted(_state, complete: complete);
    _state = report;
    for (final entry in _notificationAuthorities.entries) {
      final level = report.topic(entry.key)?.notificationLevel;
      if (level != null) {
        entry.value.level = TopicNotificationLevel.fromJson(level);
      }
    }
    _hasSnapshot = true;
    _load = null;
    _bootstrap = null;
    _retrying = false;
    _events.clear();
    _revision++;
  }

  bool failSnapshot(TopicTrackingSnapshot ticket) {
    if (!owns(ticket)) return false;
    _load = null;
    _events.clear();
    _retrying = true;
    return true;
  }

  void cancelSnapshot(TopicTrackingSnapshot ticket) {
    if (!owns(ticket)) return;
    _load = null;
    _events.clear();
  }

  bool admitsIncoming(
    Object? data, {
    DiscourseUser? user,
    SiteConfig config = const SiteConfig.unknown(),
  }) => _current && _filter.admitsIncoming(data, user: user, config: config);

  /// Null means rejected. A false value is an admitted event with no row
  /// change; dismissals still need publication to loaded list records.
  bool? accept(
    Object? data, {
    DiscourseUser? user,
    SiteConfig config = const SiteConfig.unknown(),
  }) {
    if (!_current || !_filter.accepts(data, user: user, config: config)) {
      return null;
    }
    final topicId = data is Map ? jsonIntOrNull(data['topic_id']) : null;
    if (topicId != null &&
        topicId > 0 &&
        data is Map &&
        data['message_type'] == 'notification_level_change') {
      final level = jsonObject(data['payload'])['notification_level'];
      if (level is int && level >= 0 && level <= 3) {
        final before = _revision;
        observeNotificationLevel(
          topicId,
          TopicNotificationLevel.fromJson(level),
        );
        return before != _revision;
      }
    }
    _capture(data);
    var changed = _state.applyMessage(data);
    if (topicId != null) changed = _overlay(_state, topicId) || changed;
    if (changed) _revision++;
    return changed;
  }

  void _capture(Object? event) {
    if (!_hasSnapshot || _load != null || _bootstrap != null) {
      _events.add(event);
    }
  }

  bool _overlay(TopicTrackingState state, int topicId) {
    var changed = false;
    final read = _localReads[topicId];
    if (read != null) changed = state.markRead(topicId, read);
    final choice = _choices[topicId];
    if (choice != null && choice._pending) {
      changed =
          state.applyMessage(_levelMessage(topicId, choice.level)) || changed;
    }
    return changed;
  }

  bool markRead(int topicId, int position) {
    if (!_current) return false;
    final held = _localReads[topicId] ?? 0;
    if (position > held) _localReads[topicId] = position;
    final changed = _state.markRead(topicId, _localReads[topicId] ?? position);
    if (changed) _revision++;
    return changed;
  }

  void markLastPostUnread(int topicId, int position) {
    if (!_current) return;
    _localReads.remove(topicId);
    _state.markLastPostUnread(topicId, position);
    _revision++;
  }

  TopicNotificationLevel? notificationLevel(int topicId) {
    final choice = _choices[topicId];
    if (choice != null && choice._pending) return choice.level;
    final level = _state.topic(topicId)?.notificationLevel;
    return level == null
        ? _notificationAuthorities[topicId]?.level
        : TopicNotificationLevel.fromJson(level);
  }

  TopicNotificationRead beginNotificationRead(int topicId) {
    final authority = _notificationAuthorities.putIfAbsent(
      topicId,
      _NotificationAuthority.new,
    );
    return TopicNotificationRead._(this, topicId, authority.revision);
  }

  TopicNotificationLevel? _notificationLevelFromRead(
    TopicNotificationRead read,
    TopicNotificationLevel incoming,
  ) {
    if (!_current) return null;
    final authority = _notificationAuthorities[read.topicId]!;
    if (authority.revision != read._revision) {
      return notificationLevel(read.topicId) ?? incoming;
    }
    return _observeLevel(read.topicId, incoming);
  }

  void _advanceNotificationAuthority(int topicId) {
    _notificationAuthorities
        .putIfAbsent(topicId, _NotificationAuthority.new)
        .revision++;
  }

  TopicTrackingChoice chooseNotificationLevel(
    int topicId,
    TopicNotificationLevel level, {
    required TopicNotificationLevel confirmed,
  }) {
    final choice = TopicTrackingChoice._(
      this,
      topicId,
      level,
      _choices[topicId]?._confirmed ?? confirmed,
    );
    if (!_current) return choice;
    _choices[topicId] = choice;
    _advanceNotificationAuthority(topicId);
    _setLevel(topicId, level);
    return choice;
  }

  /// Older serialized successes advance the rollback baseline, while only the
  /// latest choice may settle its overlay or produce a detail projection.
  TopicNotificationLevel? settleNotificationLevel(
    TopicTrackingChoice choice, {
    required bool succeeded,
  }) {
    if (!_current || !identical(choice._owner, this)) return null;
    final latest = _choices[choice.topicId];
    if (latest == null) return null;
    if (succeeded) {
      latest._confirmed = choice.level;
      _advanceNotificationAuthority(choice.topicId);
    }
    if (!identical(latest, choice)) return null;
    if (!succeeded) _advanceNotificationAuthority(choice.topicId);
    latest._pending = false;
    final level = succeeded ? latest.level : latest._confirmed;
    _setLevel(choice.topicId, level);
    return level;
  }

  TopicNotificationLevel observeNotificationLevel(
    int topicId,
    TopicNotificationLevel level,
  ) {
    if (!_current) return level;
    _advanceNotificationAuthority(topicId);
    return _observeLevel(topicId, level);
  }

  TopicNotificationLevel _observeLevel(
    int topicId,
    TopicNotificationLevel level,
  ) {
    final choice = _choices[topicId];
    if (choice != null && choice._pending) {
      choice._confirmed = level;
      level = choice.level;
    }
    _setLevel(topicId, level);
    return level;
  }

  void releaseNotificationChoice(TopicTrackingChoice choice) {
    if (identical(_choices[choice.topicId], choice)) {
      _choices.remove(choice.topicId);
    }
  }

  void _setLevel(int topicId, TopicNotificationLevel level) {
    _notificationAuthorities
            .putIfAbsent(topicId, _NotificationAuthority.new)
            .level =
        level;
    final message = _levelMessage(topicId, level);
    _capture(message);
    if (_state.applyMessage(message)) _revision++;
  }

  static Map<String, Object?> _levelMessage(
    int topicId,
    TopicNotificationLevel level,
  ) => {
    'topic_id': topicId,
    'message_type': 'notification_level_change',
    'payload': {'notification_level': level.value},
  };

  void retire() {
    _retired = true;
    _load = null;
    _bootstrap = null;
    _events.clear();
    _choices.clear();
    _notificationAuthorities.clear();
    _localReads.clear();
  }
}

final class TopicTrackingSnapshot {
  TopicTrackingSnapshot._(this._owner);
  final TopicTrackingReconciler _owner;

  bool get isCurrent =>
      _owner._current &&
      (identical(_owner._load, this) || identical(_owner._bootstrap, this));
}

final class TopicTrackingChoice {
  TopicTrackingChoice._(this._owner, this.topicId, this.level, this._confirmed);
  final TopicTrackingReconciler _owner;
  final int topicId;
  final TopicNotificationLevel level;
  TopicNotificationLevel _confirmed;
  bool _pending = true;
}

final class _NotificationAuthority {
  int revision = 0;
  TopicNotificationLevel? level;
}

final class TopicNotificationRead {
  TopicNotificationRead._(this._owner, this.topicId, this._revision);

  final TopicTrackingReconciler _owner;
  final int topicId;
  final int _revision;

  bool get isCurrent => _owner._current;

  TopicNotificationLevel? reconcile(TopicNotificationLevel incoming) =>
      _owner._notificationLevelFromRead(this, incoming);
}
