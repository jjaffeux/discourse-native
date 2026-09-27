import '../foundation/bounded_lru_cache.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/user_status.dart';

/// Live custom statuses from each site's `/user-status` channel, folded over
/// the status snapshot a surface was serialized with.
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
  final Map<String, BoundedLruCache<int, UserStatus?>> _bySite = {};

  /// The status to draw for [userId]: the latest live one when the channel
  /// has delivered any, otherwise [snapshot]; null once it has expired.
  UserStatus? statusFor(String siteUrl, int? userId, UserStatus? snapshot) {
    final overrides = _bySite[siteUrl];
    final status = userId != null && (overrides?.containsKey(userId) ?? false)
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
    final overrides = _bySite.putIfAbsent(
      siteUrl,
      () => BoundedLruCache(capacity),
    );
    var changed = false;
    for (final MapEntry(key: userId, value: status) in statuses.entries) {
      if (!overrides.containsKey(userId) || overrides.read(userId) != status) {
        changed = true;
      }
      overrides.put(userId, status);
    }
    if (changed) notifySafely();
  }

  void forget(String siteUrl) {
    if (_bySite.remove(siteUrl) != null) notifySafely();
  }

  @override
  void dispose() {
    _bySite.clear();
    super.dispose();
  }
}
