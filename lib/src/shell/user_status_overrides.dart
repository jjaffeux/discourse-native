import '../data/user_status_reconciler.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/user_status.dart';

/// Statuses reconciled from live deliveries, confirmed writes and fresh reads,
/// folded over the status snapshot a surface was serialized with.
///
/// Every account on a site publishes to that channel when it sets or clears a
/// status, so this state has its own notifier rather than the shell's: a busy
/// forum must not redraw the app frame for people nobody is looking at, and
/// each reader selects only its own user.
final class UserStatusOverrides extends FrameSafeNotifier {
  UserStatusOverrides({this.capacity = defaultCapacity}) : assert(capacity > 0);

  /// Overrides kept per site. Reads refresh recency and every notification
  /// re-runs each mounted reader's select, so a user on screen stays
  /// resident; what ages out is a user nobody has shown since, whose surface
  /// falls back to the snapshot it was serialized with.
  static const int defaultCapacity = 1024;

  final int capacity;
  final Map<String, UserStatusReconciler> _bySite = {};

  UserStatusReconciler reconcilerFor(String siteUrl) => _bySite.putIfAbsent(
    siteUrl,
    () => UserStatusReconciler(capacity: capacity),
  );

  UserStatusSnapshot beginSnapshot(String siteUrl) =>
      reconcilerFor(siteUrl).beginSnapshot();

  UserStatus? acceptSnapshot(
    String siteUrl,
    UserStatusSnapshot ticket,
    int userId,
    UserStatus? status, {
    void Function(UserStatus?)? onAccepted,
  }) {
    if (isDisposed) return null;
    final reconciler = reconcilerFor(siteUrl);
    final accepted = reconciler.acceptSnapshot(ticket, userId, status);
    if (accepted == null) return reconciler.read(userId);
    onAccepted?.call(accepted.status);
    if (accepted.changed) notifySafely();
    return reconciler.read(userId);
  }

  void snapshotAccepted() => notifySafely();

  /// The latest reconciled status for [userId], otherwise [snapshot].
  /// Expired statuses are hidden.
  UserStatus? statusFor(String siteUrl, int? userId, UserStatus? snapshot) {
    final overrides = _bySite[siteUrl];
    final status = userId != null && (overrides?.contains(userId) ?? false)
        ? overrides!.read(userId)
        : snapshot;
    return status?.isActiveAt(DateTime.now()) == true ? status : null;
  }

  /// Folds one channel delivery and answers the statuses it carried by user
  /// ID, null for a cleared one. Entries it cannot read are skipped.
  Map<int, UserStatus?> applyMessage(String siteUrl, Object? data) {
    if (data is! Map<Object?, Object?>) return const {};
    final statuses = <int, UserStatus?>{};
    for (final entry in data.entries) {
      final userId = switch (entry.key) {
        final int value => value,
        final String value => int.tryParse(value),
        _ => null,
      };
      if (userId == null || userId <= 0) continue;

      final UserStatus? status;
      if (entry.value == null) {
        status = null;
      } else if (entry.value case final Map<Object?, Object?> value) {
        status = UserStatus.fromJson(Map<String, dynamic>.from(value));
        if (status == null) continue;
      } else {
        continue;
      }
      statuses[userId] = status;
    }
    _record(siteUrl, statuses);
    return statuses;
  }

  /// Records the account's own status once a write is confirmed.
  void record(String siteUrl, int userId, UserStatus? status) =>
      _record(siteUrl, {userId: status});

  void _record(String siteUrl, Map<int, UserStatus?> statuses) {
    if (isDisposed || statuses.isEmpty) return;
    final reconciler = reconcilerFor(siteUrl);
    var changed = false;
    for (final MapEntry(key: userId, value: status) in statuses.entries) {
      changed = reconciler.record(userId, status) || changed;
    }
    if (changed) notifySafely();
  }

  void forget(String siteUrl) {
    final reconciler = _bySite.remove(siteUrl);
    if (reconciler == null) return;
    reconciler.retire();
    notifySafely();
  }

  @override
  void dispose() {
    for (final reconciler in _bySite.values) {
      reconciler.retire();
    }
    _bySite.clear();
    super.dispose();
  }
}
