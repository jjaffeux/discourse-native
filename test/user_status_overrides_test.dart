// Pure `test` only: the shell constructs this notifier from pure-Dart entry
// points too, so it must keep working with no Flutter binding.
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/shell/user_status_overrides.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://discuss.example.com';
const _snapshot = UserStatus(description: 'Snapshot', emoji: 'clock1');

Map<String, Object?> _status(String description) => {
  'description': description,
  'emoji': 'house',
};

void main() {
  test('folds live statuses and clears over the serialized snapshot', () {
    final overrides = UserStatusOverrides();
    addTearDown(overrides.dispose);

    expect(overrides.statusFor(_site, 42, _snapshot), _snapshot);

    expect(overrides.applyMessage(_site, {'42': _status('At lunch')}), {
      42: const UserStatus(description: 'At lunch', emoji: 'house'),
    });
    expect(overrides.statusFor(_site, 42, _snapshot)?.description, 'At lunch');
    expect(overrides.statusFor(_otherSite, 42, _snapshot), _snapshot);
    expect(overrides.statusFor(_site, null, _snapshot), _snapshot);

    expect(overrides.applyMessage(_site, const {'42': null}), {42: null});
    expect(overrides.statusFor(_site, 42, _snapshot), isNull);

    overrides.record(
      _site,
      42,
      const UserStatus(description: 'Pairing', emoji: 'busts_in_silhouette'),
    );
    expect(overrides.statusFor(_site, 42, _snapshot)?.description, 'Pairing');
  });

  test('skips entries it cannot read without dropping the rest', () {
    final overrides = UserStatusOverrides();
    addTearDown(overrides.dispose);
    var notifications = 0;
    overrides.addListener(() => notifications++);

    expect(overrides.applyMessage(_site, 'not a map'), isEmpty);
    expect(
      overrides.applyMessage(_site, {
        'abc': _status('Bad key'),
        '0': _status('Zero'),
        '-3': _status('Negative'),
        '5': 'not a status',
        '6': {'description': '', 'emoji': 'house'},
        7: _status('Integer key'),
      }),
      {7: const UserStatus(description: 'Integer key', emoji: 'house')},
    );
    expect(notifications, 1);
  });

  test('notifies only when a delivery changes a recorded status', () {
    final overrides = UserStatusOverrides();
    addTearDown(overrides.dispose);
    var notifications = 0;
    overrides.addListener(() => notifications++);

    overrides.applyMessage(_site, {'42': _status('At lunch')});
    overrides.applyMessage(_site, {'42': _status('At lunch')});
    expect(notifications, 1);

    overrides.applyMessage(_site, const {'42': null});
    overrides.applyMessage(_site, const {'42': null});
    expect(notifications, 2);

    overrides.forget(_otherSite);
    expect(notifications, 2);
    overrides.forget(_site);
    expect(notifications, 3);
    expect(overrides.statusFor(_site, 42, _snapshot), _snapshot);
  });

  test('retains only the most recently delivered or read users per site', () {
    final overrides = UserStatusOverrides(capacity: 3);
    addTearDown(overrides.dispose);

    for (final userId in [1, 2, 3]) {
      overrides.applyMessage(_site, {'$userId': _status('User $userId')});
    }
    overrides.applyMessage(_otherSite, {'1': _status('Elsewhere')});
    // A reader drawing user 1 keeps it resident.
    expect(overrides.statusFor(_site, 1, _snapshot)?.description, 'User 1');
    overrides.applyMessage(_site, {'4': _status('User 4')});

    expect(overrides.statusFor(_site, 2, _snapshot), _snapshot);
    for (final userId in [1, 3, 4]) {
      expect(
        overrides.statusFor(_site, userId, _snapshot)?.description,
        'User $userId',
      );
    }
    expect(
      overrides.statusFor(_otherSite, 1, _snapshot)?.description,
      'Elsewhere',
    );
  });

  test('stays bounded under a busy site where every account changes', () {
    final overrides = UserStatusOverrides();
    addTearDown(overrides.dispose);
    const capacity = UserStatusOverrides.defaultCapacity;
    const users = capacity * 4;

    for (var userId = 1; userId <= users; userId++) {
      overrides.applyMessage(_site, {'$userId': _status('User $userId')});
    }

    expect(overrides.statusFor(_site, 1, _snapshot), _snapshot);
    expect(overrides.statusFor(_site, users - capacity, _snapshot), _snapshot);
    for (final userId in [users - capacity + 1, users]) {
      expect(
        overrides.statusFor(_site, userId, _snapshot)?.description,
        'User $userId',
      );
    }
  });
}
