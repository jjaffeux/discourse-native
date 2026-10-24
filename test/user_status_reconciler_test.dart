import 'package:discourse_native/src/data/current_user_reconciler.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/user_status_reconciler.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/user_status_overrides.dart';
import 'package:flutter_test/flutter_test.dart';

const _old = UserStatus(description: 'Old', emoji: 'clock1');
const _fresh = UserStatus(description: 'Fresh', emoji: 'house');

void main() {
  test('a repeated live value advances authority without a visual change', () {
    final statuses = UserStatusReconciler(capacity: 3);
    statuses.record(7, _old);
    final read = statuses.beginSnapshot();
    expect(statuses.record(7, _old), isFalse);
    expect(statuses.acceptSnapshot(read, 7, _fresh), isNull);
    expect(statuses.read(7), _old);
  });

  test('later dispatched accepted snapshot wins regardless of completion', () {
    final statuses = UserStatusReconciler(capacity: 3);
    final first = statuses.beginSnapshot();
    final second = statuses.beginSnapshot();
    expect(statuses.acceptSnapshot(second, 7, null)?.status, isNull);
    expect(statuses.contains(7), isTrue);
    expect(statuses.acceptSnapshot(first, 7, _old), isNull);
    expect(statuses.read(7), isNull);
    expect(
      statuses.acceptSnapshot(statuses.beginSnapshot(), 7, _fresh)?.status,
      _fresh,
    );
  });

  test('later snapshot replaces an earlier response that completed first', () {
    final statuses = UserStatusReconciler(capacity: 3);
    final first = statuses.beginSnapshot();
    final second = statuses.beginSnapshot();
    expect(statuses.acceptSnapshot(first, 7, _old)?.status, _old);
    expect(statuses.acceptSnapshot(second, 7, _fresh)?.status, _fresh);
    expect(statuses.read(7), _fresh);
  });

  test('a later failed read does not suppress an earlier successful read', () {
    final statuses = UserStatusReconciler(capacity: 3);
    final first = statuses.beginSnapshot();
    statuses.beginSnapshot();
    expect(statuses.acceptSnapshot(first, 7, _fresh)?.status, _fresh);
  });

  test('eviction fences old reads without retaining unbounded tombstones', () {
    final statuses = UserStatusReconciler(capacity: 1);
    final oldRead = statuses.beginSnapshot();
    statuses.record(7, null);
    statuses.record(8, _fresh);
    expect(statuses.contains(7), isFalse);
    expect(statuses.acceptSnapshot(oldRead, 7, _old), isNull);
    expect(statuses.contains(7), isFalse);
    expect(
      statuses.acceptSnapshot(statuses.beginSnapshot(), 7, _fresh)?.status,
      _fresh,
    );
    expect(statuses.contains(8), isFalse);
  });

  test('evicted live authority cannot resurrect from an in-flight card', () {
    final statuses = UserStatusOverrides(capacity: 1);
    addTearDown(statuses.dispose);
    final read = statuses.beginSnapshot('site');
    statuses.record('site', 7, null);
    statuses.record('site', 8, _fresh);
    expect(statuses.acceptSnapshot('site', read, 7, _old), isNull);
    expect(statuses.statusFor('site', 7, null), isNull);
    final freshRead = statuses.beginSnapshot('site');
    expect(statuses.acceptSnapshot('site', freshRead, 7, _fresh), _fresh);
  });

  test('forget invalidates tickets even when a site owner is recreated', () {
    final statuses = UserStatusOverrides();
    addTearDown(statuses.dispose);
    final old = statuses.beginSnapshot('site');
    statuses.forget('site');
    statuses.record('site', 7, _fresh);
    expect(statuses.acceptSnapshot('site', old, 7, _old), _fresh);
    expect(statuses.statusFor('site', 7, null), _fresh);
  });

  for (final clear in [false, true]) {
    test(
      'current-user refresh can recover a later ${clear ? 'clear' : 'status'}',
      () {
        final lifecycle = SiteLifecycle();
        final statuses = UserStatusReconciler(capacity: 1);
        final users = CurrentUserReconciler(
          lease: lifecycle.capture('site'),
          models: const DiscourseModelCodec.core(),
          statuses: statuses,
        );
        final stale = users.beginSnapshot();
        statuses.record(7, _fresh);
        final accepted = users.reconcile(
          stale,
          previous: const DiscourseUser(id: 7, username: 'sam', status: _fresh),
          incoming: const DiscourseUser(id: 7, username: 'sam', status: _old),
        )!;
        expect(accepted.user.status, _fresh);
        final later = users.reconcile(
          users.beginSnapshot(),
          previous: accepted.user,
          incoming: DiscourseUser(
            id: 7,
            username: 'sam',
            status: clear ? null : _old,
          ),
        )!;
        expect(later.user.status, clear ? null : _old);
        expect(statuses.contains(7), isTrue);
        expect(statuses.read(7), later.user.status);
      },
    );
  }

  test('canonical own status survives eviction when an old read finishes', () {
    final lifecycle = SiteLifecycle();
    final statuses = UserStatusReconciler(capacity: 1);
    final users = CurrentUserReconciler(
      lease: lifecycle.capture('site'),
      models: const DiscourseModelCodec.core(),
      statuses: statuses,
    );
    final stale = users.beginSnapshot();
    statuses.record(7, _fresh);
    statuses.record(8, null);
    final accepted = users.reconcile(
      stale,
      previous: const DiscourseUser(id: 7, username: 'sam', status: _fresh),
      incoming: const DiscourseUser(id: 7, username: 'sam', status: _old),
    )!;
    expect(accepted.user.status, _fresh);
    expect(statuses.contains(7), isFalse);
  });

  test(
    'account replacement preserves newer status for the incoming identity',
    () {
      final lifecycle = SiteLifecycle();
      final statuses = UserStatusReconciler(capacity: 3);
      final users = CurrentUserReconciler(
        lease: lifecycle.capture('site'),
        models: const DiscourseModelCodec.core(),
        statuses: statuses,
      );
      final snapshot = users.beginSnapshot();
      statuses.record(8, _old);
      final accepted = users.reconcile(
        snapshot,
        previous: const DiscourseUser(id: 7, username: 'sam'),
        incoming: const DiscourseUser(id: 8, username: 'next', status: _fresh),
      )!;
      expect(accepted.accountChanged, isTrue);
      expect(accepted.user.status, _old);
      expect(statuses.read(8), _old);
      users.retire();
      expect(
        users.reconcile(
          users.beginSnapshot(),
          previous: accepted.user,
          incoming: const DiscourseUser(id: 8, username: 'next'),
        ),
        isNull,
      );
    },
  );
  test(
    'replacement does not inherit previous-account status after eviction',
    () {
      final lifecycle = SiteLifecycle();
      final statuses = UserStatusReconciler(capacity: 1);
      final users = CurrentUserReconciler(
        lease: lifecycle.capture('site'),
        models: const DiscourseModelCodec.core(),
        statuses: statuses,
      );
      final snapshot = users.beginSnapshot();
      statuses.record(8, null);
      statuses.record(9, _old);
      final accepted = users.reconcile(
        snapshot,
        previous: const DiscourseUser(id: 7, username: 'sam', status: _old),
        incoming: const DiscourseUser(id: 8, username: 'next', status: _fresh),
      )!;
      expect(accepted.accountChanged, isTrue);
      expect(accepted.user.status, _fresh);
      expect(statuses.contains(8), isFalse);
    },
  );
  test('a current user with no id keeps the incoming snapshot status', () {
    final lifecycle = SiteLifecycle();
    final statuses = UserStatusReconciler(capacity: 1);
    final users = CurrentUserReconciler(
      lease: lifecycle.capture('site'),
      models: const DiscourseModelCodec.core(),
      statuses: statuses,
    );
    statuses.record(7, _old);
    final accepted = users.reconcile(
      users.beginSnapshot(),
      previous: const DiscourseUser(username: 'sam', status: _old),
      incoming: const DiscourseUser(username: 'sam', status: _fresh),
    )!;
    expect(accepted.user.status, _fresh);
    expect(statuses.read(7), _old);
  });
}
