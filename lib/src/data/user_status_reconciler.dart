import '../models/user_status.dart';

final class UserStatusReconciler {
  UserStatusReconciler({required this.capacity}) : assert(capacity > 0);

  final int capacity;
  final Map<int, _StatusEntry> _entries = {};
  int _sequence = 0;
  int _evictedThrough = 0;
  bool _retired = false;

  UserStatusSnapshot beginSnapshot() => UserStatusSnapshot._(this, ++_sequence);

  bool contains(int userId) => _entries.containsKey(userId);

  UserStatus? read(int userId) {
    final entry = _entries.remove(userId);
    if (entry == null) return null;
    _entries[userId] = entry;
    return entry.status;
  }

  bool record(int userId, UserStatus? status) {
    if (_retired) return false;
    return _put(userId, status, ++_sequence);
  }

  /// Null rejects the read; a result containing null accepts a cleared status.
  ({UserStatus? status, bool changed})? acceptSnapshot(
    UserStatusSnapshot ticket,
    int userId,
    UserStatus? status,
  ) {
    if (_retired || !identical(ticket._owner, this)) return null;
    final held = _entries[userId];
    if (held != null
        ? held.sequence > ticket._sequence
        : ticket._sequence <= _evictedThrough) {
      return null;
    }
    return (status: status, changed: _put(userId, status, ticket._sequence));
  }

  bool _put(int userId, UserStatus? status, int sequence) {
    final previous = _entries.remove(userId);
    _entries[userId] = _StatusEntry(status, sequence);
    if (_entries.length > capacity) {
      final evicted = _entries.remove(_entries.keys.first)!;
      if (evicted.sequence > _evictedThrough) {
        _evictedThrough = evicted.sequence;
      }
    }
    return previous == null || previous.status != status;
  }

  void retire() {
    _retired = true;
    _entries.clear();
  }
}

final class UserStatusSnapshot {
  const UserStatusSnapshot._(this._owner, this._sequence);

  final UserStatusReconciler _owner;
  final int _sequence;
}

final class _StatusEntry {
  const _StatusEntry(this.status, this.sequence);

  final UserStatus? status;
  final int sequence;
}
