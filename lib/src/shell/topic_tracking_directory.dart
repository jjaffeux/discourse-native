import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../data/topic_tracking_reconciler.dart';
import '../models/discourse_user.dart';
import '../models/json.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../plugin_api/discourse_model_codec.dart';

abstract interface class TopicTrackingAdmission {
  bool get isCurrent;
  bool belongsTo(DiscourseUser? user);
  void accept(Object? message);
}

/// Owns tracking identity and canonical row effects independently of transport.
final class TopicTrackingDirectory {
  TopicTrackingDirectory({
    required this.lifecycle,
    required this.store,
    required this.models,
    required this.userFor,
    required this.configFor,
    required this.changed,
    this.retryBeforeAccept,
    this.clock,
  });

  final SiteLifecycle lifecycle;
  final Store store;
  final DiscourseModelCodec models;
  final DiscourseUser? Function(String siteUrl) userFor;
  final SiteConfig Function(String siteUrl) configFor;
  final void Function(String siteUrl) changed;
  final void Function(String siteUrl)? retryBeforeAccept;
  final DateTime Function()? clock;
  final Map<String, TopicTrackingAccount> _accounts = {};
  final Map<String, Object> _transitions = {};
  bool _disposed = false;

  TopicTrackingAccount? existing(String siteUrl) {
    final account = _accounts[siteUrl];
    return account?.isCurrent == true ? account : null;
  }

  TopicTrackingAccount? capture(String siteUrl, {SiteLease? lease}) {
    if (_disposed || _transitions.containsKey(siteUrl)) return null;
    final session = lease ?? lifecycle.capture(siteUrl);
    if (!session.isCurrent) return null;
    final held = existing(siteUrl);
    if (held != null && identical(held.lease.session, session.session)) {
      return held;
    }
    forget(siteUrl);
    final account = TopicTrackingAccount._(
      this,
      siteUrl,
      session,
      userFor(siteUrl),
    );
    _accounts[siteUrl] = account;
    account._detach = session.onRetire(() {
      account._retire();
      if (identical(_accounts[siteUrl], account)) _accounts.remove(siteUrl);
    });
    return account;
  }

  TopicTrackingAccount? matching(
    String siteUrl,
    SiteLease lease,
    TopicTrackingReconciler reconciler,
  ) {
    final account = existing(siteUrl);
    return account != null &&
            identical(account.lease.session, lease.session) &&
            identical(account.reconciler, reconciler)
        ? account
        : null;
  }

  /// Blocks account admission across synchronous current-user publication.
  void Function() beginAccountChange(String siteUrl) {
    final transition = Object();
    _transitions[siteUrl] = transition;
    forget(siteUrl);
    return () {
      if (identical(_transitions[siteUrl], transition)) {
        _transitions.remove(siteUrl);
      }
    };
  }

  void forget(String siteUrl) => _accounts.remove(siteUrl)?._retire();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final account in _accounts.values.toList()) {
      account._retire();
    }
    _accounts.clear();
    _transitions.clear();
  }
}

final class TopicTrackingAccount implements TopicTrackingAdmission {
  TopicTrackingAccount._(this._owner, this.siteUrl, this.lease, this._user) {
    reconciler = TopicTrackingReconciler(
      isCurrent: () => isCurrent,
      clock: _owner.clock,
    );
  }

  final TopicTrackingDirectory _owner;
  final String siteUrl;
  final SiteLease lease;
  final DiscourseUser? _user;
  late final TopicTrackingReconciler reconciler;
  void Function()? _detach;
  bool _retired = false;

  @override
  bool get isCurrent {
    if (_retired ||
        _owner._disposed ||
        !lease.isCurrent ||
        _owner._transitions.containsKey(siteUrl) ||
        !identical(_owner._accounts[siteUrl], this)) {
      return false;
    }
    return belongsTo(_owner.userFor(siteUrl));
  }

  @override
  bool belongsTo(DiscourseUser? user) {
    final original = _user;
    return original == null
        ? user == null
        : user != null && _owner.models.sameCurrentUserAccount(original, user);
  }

  bool owns(TopicTrackingSnapshot ticket) =>
      isCurrent && reconciler.owns(ticket);

  bool admitsIncoming(Object? message) =>
      isCurrent &&
      reconciler.admitsIncoming(
        message,
        user: _owner.userFor(siteUrl),
        config: _owner.configFor(siteUrl),
      );

  @override
  void accept(Object? message, {void Function()? retryBeforeAccept}) {
    if (!isCurrent) return;
    if (retryBeforeAccept != null) {
      retryBeforeAccept();
    } else {
      _owner.retryBeforeAccept?.call(siteUrl);
    }
    if (!isCurrent) return;
    final changed = reconciler.accept(
      message,
      user: _owner.userFor(siteUrl),
      config: _owner.configFor(siteUrl),
    );
    if (changed == null) return;
    _applyDismissal(message);
    if (isCurrent && changed) _owner.changed(siteUrl);
  }

  void _applyDismissal(Object? message) {
    if (message is! Map) return;
    final type = message['message_type'];
    if (type != 'dismiss_new' && type != 'dismiss_new_posts') return;
    for (final value in jsonArray(
      jsonObject(message['payload'])['topic_ids'],
    )) {
      if (!isCurrent) return;
      final topicId = jsonIntOrNull(value);
      if (topicId == null) continue;
      _owner.store.update<Topic>(siteUrl, topicId, (row) {
        if (type == 'dismiss_new') {
          return row.seen ? row : row.copyWith(seen: true);
        }
        if (row.lastReadPostNumber == null) return row;
        final tracked = reconciler.topic(topicId)?.highestPostNumber ?? 0;
        return _readThrough(
          row,
          tracked > row.highestPostNumber ? tracked : row.highestPostNumber,
        );
      });
    }
  }

  Topic project(Topic incoming) {
    final tracked = isCurrent ? reconciler.topic(incoming.id) : null;
    if (tracked == null) return incoming;
    var row = incoming;
    if (!row.listReadStateKnown &&
        row.lastReadPostNumber == null &&
        tracked.isNew &&
        row.seen) {
      row = row.copyWith(seen: false);
    }
    if (tracked.isSeen && !row.seen) row = row.copyWith(seen: true);
    final position = tracked.lastReadPostNumber;
    final held = row.lastReadPostNumber;
    if (position != null &&
        held != null &&
        position > held &&
        row.highestPostNumber > 0 &&
        position >= row.highestPostNumber) {
      row = _readThrough(row, position);
    }
    return row;
  }

  void markRead(int topicId, int position) {
    if (isCurrent) reconciler.markRead(topicId, position);
  }

  void markLastPostUnread(int topicId, int position) {
    if (isCurrent) reconciler.markLastPostUnread(topicId, position);
  }

  static Topic _readThrough(Topic row, int position) {
    final read = row.copyWith(
      lastReadPostNumber: position > (row.lastReadPostNumber ?? 0)
          ? position
          : null,
      highestPostNumber: position > row.highestPostNumber ? position : null,
      unreadPosts: 0,
      newPosts: 0,
    );
    return read == row ? row : read;
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    reconciler.retire();
  }
}
