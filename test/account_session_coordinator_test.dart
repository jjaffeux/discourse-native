import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _otherSiteUrl = 'https://other.discourse.org';
const _oldKey = 'account-a-key';
const _newKey = 'account-b-key';
const _accountA = DiscourseUser(id: 1, username: 'account-a');
const _accountB = DiscourseUser(id: 2, username: 'account-b');
const _newCredentials = UserApiCredentials(
  key: _newKey,
  apiVersion: 4,
  push: false,
);

enum _Failure {
  readCredential,
  authorize,
  clearDrafts,
  lookup,
  persistCredential,
  revokeOld,
  revokeIssued,
  deleteCredential,
}

final class _SessionAuthenticator extends FakeAuthenticator {
  _SessionAuthenticator(this.events, this.failures)
    : super(credentials: _newCredentials) {
    keys[_siteUrl] = _oldKey;
  }

  final List<String> events;
  final Set<_Failure> failures;
  Completer<void>? authorizeGate;
  final authorizeStarted = Completer<void>();
  void Function(String siteUrl)? beforeDisconnect;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    events.add('credential:read');
    if (failures.contains(_Failure.readCredential)) {
      throw StateError('credential read failed');
    }
    return keys[siteUrl];
  }

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    events.add('credential:authorize');
    if (!authorizeStarted.isCompleted) authorizeStarted.complete();
    await authorizeGate?.future;
    if (failures.contains(_Failure.authorize)) {
      throw const UserApiAuthException(UserApiAuthFailure.launchFailed);
    }
    return _newCredentials;
  }

  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    events.add('credential:persist');
    if (failures.contains(_Failure.persistCredential)) {
      throw StateError('credential write failed');
    }
    keys[siteUrl] = credentials.key;
  }

  @override
  Future<void> disconnect(String siteUrl) async {
    events.add('credential:delete');
    beforeDisconnect?.call(siteUrl);
    if (failures.contains(_Failure.deleteCredential)) {
      throw StateError('credential delete failed');
    }
    keys.remove(siteUrl);
  }
}

final class _SessionDraftStore extends FakeDraftStore {
  _SessionDraftStore(this._recordedEvents, this.failures);

  final List<String> _recordedEvents;
  final Set<_Failure> failures;

  @override
  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    _recordedEvents.add('drafts:clear');
    if (failures.contains(_Failure.clearDrafts)) {
      throw StateError('draft blocker failed');
    }
  }
}

final class _SessionInstanceStore extends FakeInstanceStore {
  _SessionInstanceStore(
    super.instances,
    this.events, {
    this.failingSaveCalls = const {},
  });

  final List<String> events;
  final Set<int> failingSaveCalls;
  int attempts = 0;
  final List<List<DiscourseInstance>> attemptedSnapshots = [];

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    attempts++;
    attemptedSnapshots.add(List.of(instances));
    final user = instances.single.user?.username ?? 'signed-out';
    events.add('instances:save:$user');
    if (failingSaveCalls.contains(attempts)) {
      throw StateError('instance save $attempts failed');
    }
    await super.save(instances);
  }
}

final class _SessionApi extends FakeDiscourseApi {
  _SessionApi(this.events, this.failures) : super(user: _accountB);

  final List<String> events;
  final Set<_Failure> failures;
  Completer<void>? lookupGate;
  Completer<void>? firstRevocationGate;
  final lookupStarted = Completer<void>();
  final firstRevocationStarted = Completer<void>();
  int revocationCount = 0;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    events.add('account:lookup');
    if (!lookupStarted.isCompleted) lookupStarted.complete();
    await lookupGate?.future;
    if (failures.contains(_Failure.lookup)) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return _accountB;
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    revocationCount++;
    events.add('credential:revoke:$apiKey');
    if (revocationCount == 1 && firstRevocationGate != null) {
      firstRevocationStarted.complete();
      await firstRevocationGate!.future;
    }
    if (apiKey == _oldKey && failures.contains(_Failure.revokeOld)) {
      throw StateError('old revocation failed');
    }
    if (apiKey == _newKey && failures.contains(_Failure.revokeIssued)) {
      throw StateError('issued revocation failed');
    }
  }
}

final class _SessionHost implements AccountSessionHost {
  _SessionHost(DiscourseInstance instance, this.events)
    : _instances = [instance];

  _SessionHost.multiple(List<DiscourseInstance> instances, this.events)
    : _instances = List.of(instances);

  final List<String> events;
  final List<DiscourseInstance> _instances;
  Completer<void>? _snapshotCaptured;

  Future<void> get nextSnapshot =>
      (_snapshotCaptured = Completer<void>()).future;

  @override
  bool accountSessionDisposed = false;

  @override
  List<DiscourseInstance> get accountSessionInstances {
    // The waiter resumes after the caller has synchronously accepted the
    // snapshot into the real InstanceStore's coalescing writer.
    _snapshotCaptured?.complete();
    _snapshotCaptured = null;
    return List.unmodifiable(_instances);
  }

  @override
  DiscourseInstance? accountSessionInstance(String siteUrl) {
    for (final instance in _instances) {
      if (instance.url == siteUrl) return instance;
    }
    return null;
  }

  @override
  void clearAccountSessionState(String siteUrl) {
    events.add('lifecycle:clear');
  }

  @override
  DiscourseInstance? applyAccountSessionInstance(
    DiscourseInstance replacement,
    AccountSessionPhase phase,
  ) {
    final index = _instances.indexWhere((item) => item.url == replacement.url);
    if (index < 0) return null;
    events.add('presentation:${phase.name}');
    _instances[index] = replacement;
    return replacement;
  }
}

final class _Fixture {
  _Fixture({this.failures = const {}, Set<int> failingSaveCalls = const {}}) {
    const initial = DiscourseInstance(
      url: _siteUrl,
      title: 'Meta',
      user: _accountA,
    );
    authenticator = _SessionAuthenticator(events, failures);
    drafts = _SessionDraftStore(events, failures);
    instances = _SessionInstanceStore(
      [initial],
      events,
      failingSaveCalls: failingSaveCalls,
    );
    api = _SessionApi(events, failures);
    host = _SessionHost(initial, events);
    coordinator = AccountSessionCoordinator(
      authenticator: authenticator,
      instances: instances,
      drafts: drafts,
      lifecycle: lifecycle,
      api: api,
      host: host,
      reportError: (error, stackTrace, operation, {required bool warning}) {
        reportedOperations.add(operation);
      },
    );
  }

  final Set<_Failure> failures;
  final List<String> events = [];
  final List<String> reportedOperations = [];
  final SiteLifecycle lifecycle = SiteLifecycle();
  late final _SessionAuthenticator authenticator;
  late final _SessionDraftStore drafts;
  late final _SessionInstanceStore instances;
  late final _SessionApi api;
  late final _SessionHost host;
  late final AccountSessionCoordinator coordinator;

  DiscourseInstance get current => host.accountSessionInstances.single;

  Future<DiscourseInstance> get durable async =>
      (await instances.load()).single;

  void expectPrivateStateIsCoherent() {
    final username = current.user?.username;
    final key = authenticator.keys[_siteUrl];
    if (username == _accountA.username) expect(key, _oldKey);
    if (username == _accountB.username) expect(key, _newKey);
  }
}

final class _GatedInstancePersistence implements InstancePersistence {
  final gates = <int, Completer<void>>{};
  final _started = <int, Completer<void>>{};
  final failingWrites = <int>{};
  int writeCount = 0;
  String? stored;

  Future<void> waitForWrite(int attempt) =>
      _started.putIfAbsent(attempt, Completer<void>.new).future;

  List<DiscourseInstance> get durable => [
    for (final entry in jsonDecode(stored!) as List<dynamic>)
      DiscourseInstance.fromJson(entry as Map<String, dynamic>),
  ];

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String value) async {
    final attempt = ++writeCount;
    _started.putIfAbsent(attempt, Completer<void>.new).complete();
    await gates[attempt]?.future;
    if (failingWrites.contains(attempt)) {
      throw StateError('instance write $attempt failed');
    }
    stored = value;
  }
}

final class _RealStoreFixture {
  _RealStoreFixture({Set<_Failure> failures = const {}}) {
    authenticator = _SessionAuthenticator(events, failures);
    authenticator.keys[_otherSiteUrl] = 'other-site-key';
    authenticator.beforeDisconnect = (siteUrl) {
      snapshotsAtDeletion[siteUrl] = persistence.durable;
    };
    instances = InstanceStore(persistence: persistence);
    api = _SessionApi(events, failures);
    host = _SessionHost.multiple(const [
      DiscourseInstance(
        url: _siteUrl,
        title: 'Meta',
        user: _accountA,
        notificationTotals: NotificationTotals(unreadNotifications: 3),
        config: SiteConfig(userStatusEnabled: true),
      ),
      DiscourseInstance(url: _otherSiteUrl, title: 'Other', user: _accountB),
    ], events);
    coordinator = AccountSessionCoordinator(
      authenticator: authenticator,
      instances: instances,
      drafts: _SessionDraftStore(events, failures),
      lifecycle: lifecycle,
      api: api,
      host: host,
      reportError: (error, stackTrace, operation, {required bool warning}) {
        reports.add((operation: operation, warning: warning));
      },
    );
  }

  final List<String> events = [];
  final reports = <({String operation, bool warning})>[];
  final snapshotsAtDeletion = <String, List<DiscourseInstance>>{};
  final persistence = _GatedInstancePersistence();
  final lifecycle = SiteLifecycle();
  late final _SessionAuthenticator authenticator;
  late final InstanceStore instances;
  late final _SessionApi api;
  late final _SessionHost host;
  late final AccountSessionCoordinator coordinator;

  static Future<_RealStoreFixture> create({
    Set<_Failure> failures = const {},
  }) async {
    final fixture = _RealStoreFixture(failures: failures);
    await fixture.instances.save(fixture.host.accountSessionInstances);
    return fixture;
  }
}

void main() {
  group('AccountSessionCoordinator connect', () {
    test('commits the replacement account in durable privacy order', () async {
      final fixture = _Fixture();

      final result = await fixture.coordinator.connect(_siteUrl);

      expect(result.outcome, AccountConnectionOutcome.connected);
      expect(fixture.current.user, _accountB);
      expect((await fixture.durable).user, _accountB);
      expect(fixture.authenticator.keys[_siteUrl], _newKey);
      expect(fixture.events, [
        'credential:read',
        'credential:authorize',
        'drafts:clear',
        'lifecycle:clear',
        'presentation:connecting',
        'instances:save:signed-out',
        'account:lookup',
        'credential:persist',
        'credential:revoke:$_oldKey',
        'lifecycle:clear',
        'presentation:connected',
        'instances:save:account-b',
      ]);
    });

    for (final failure in [_Failure.readCredential, _Failure.authorize]) {
      test(
        'leaves the existing account intact when ${failure.name} fails',
        () async {
          final fixture = _Fixture(failures: {failure});

          final result = await fixture.coordinator.connect(_siteUrl);

          expect(result.outcome, AccountConnectionOutcome.failed);
          expect(fixture.current.user, _accountA);
          expect((await fixture.durable).user, _accountA);
          fixture.expectPrivateStateIsCoherent();
        },
      );
    }

    test('revokes an issued key when durable draft cleanup fails', () async {
      final fixture = _Fixture(failures: {_Failure.clearDrafts});

      final result = await fixture.coordinator.connect(_siteUrl);

      expect(result.outcome, AccountConnectionOutcome.failed);
      expect(fixture.current.user, _accountA);
      expect((await fixture.durable).user, _accountA);
      expect(fixture.events, contains('credential:revoke:$_newKey'));
      fixture.expectPrivateStateIsCoherent();
    });

    test(
      'restores the old account when the signed-out snapshot fails',
      () async {
        final fixture = _Fixture(failingSaveCalls: {1});

        final result = await fixture.coordinator.connect(_siteUrl);

        expect(result.outcome, AccountConnectionOutcome.failed);
        expect(fixture.current.user, _accountA);
        expect((await fixture.durable).user, _accountA);
        expect(fixture.instances.attempts, 2);
        expect(
          fixture.events,
          containsAllInOrder([
            'instances:save:signed-out',
            'presentation:restored',
            'instances:save:account-a',
            'credential:revoke:$_newKey',
          ]),
        );
        fixture.expectPrivateStateIsCoherent();
      },
    );

    for (final failure in [_Failure.lookup, _Failure.persistCredential]) {
      test('restores the old account when ${failure.name} fails', () async {
        final fixture = _Fixture(failures: {failure});

        final result = await fixture.coordinator.connect(_siteUrl);

        expect(result.outcome, AccountConnectionOutcome.failed);
        expect(fixture.current.user, _accountA);
        expect((await fixture.durable).user, _accountA);
        expect(fixture.events, contains('credential:revoke:$_newKey'));
        fixture.expectPrivateStateIsCoherent();
      });
    }

    test('tolerates failure to revoke the superseded remote key', () async {
      final fixture = _Fixture(failures: {_Failure.revokeOld});

      final result = await fixture.coordinator.connect(_siteUrl);

      expect(result.outcome, AccountConnectionOutcome.connected);
      expect(fixture.current.user, _accountB);
      expect((await fixture.durable).user, _accountB);
      fixture.expectPrivateStateIsCoherent();
      expect(
        fixture.reportedOperations,
        contains('authentication.revokePreviousKey'),
      );
    });

    test('rolls back the key when the connected snapshot fails', () async {
      final fixture = _Fixture(failingSaveCalls: {2});

      final result = await fixture.coordinator.connect(_siteUrl);

      expect(result.outcome, AccountConnectionOutcome.failed);
      expect(result.refreshSignedOutPresentation, isTrue);
      expect(fixture.current.user, isNull);
      expect((await fixture.durable).user, isNull);
      expect(fixture.authenticator.keys[_siteUrl], isNull);
      expect(
        fixture.events,
        containsAllInOrder([
          'presentation:connected',
          'instances:save:account-b',
          'presentation:rolledBack',
          'instances:save:signed-out',
          'credential:revoke:$_newKey',
          'credential:delete',
        ]),
      );
    });

    test(
      'keeps an undeletable rollback key behind signed-out metadata',
      () async {
        final fixture = _Fixture(
          failures: {_Failure.revokeIssued, _Failure.deleteCredential},
          failingSaveCalls: {2},
        );

        final result = await fixture.coordinator.connect(_siteUrl);

        expect(result.outcome, AccountConnectionOutcome.failed);
        expect(result.refreshSignedOutPresentation, isFalse);
        expect(fixture.current.user, isNull);
        expect((await fixture.durable).user, isNull);
        expect(fixture.authenticator.keys[_siteUrl], _newKey);
        fixture.expectPrivateStateIsCoherent();
      },
    );

    test(
      'retains the earlier safe snapshot when rollback saves fail',
      () async {
        final fixture = _Fixture(failingSaveCalls: {2, 3, 4});

        final result = await fixture.coordinator.connect(_siteUrl);

        expect(result.outcome, AccountConnectionOutcome.failed);
        expect(fixture.current.user, isNull);
        expect((await fixture.durable).user, isNull);
        expect(fixture.authenticator.keys[_siteUrl], isNull);
        expect(fixture.instances.attempts, 4);
      },
    );
  });

  group('AccountSessionCoordinator disconnect', () {
    test(
      'persists signed-out state before revoking and deleting the key',
      () async {
        final fixture = _Fixture();

        final result = await fixture.coordinator.disconnect(_siteUrl);

        expect(result.outcome, AccountDisconnectionOutcome.disconnected);
        expect(fixture.current.user, isNull);
        expect((await fixture.durable).user, isNull);
        expect(fixture.authenticator.keys[_siteUrl], isNull);
        expect(fixture.events, [
          'lifecycle:clear',
          'drafts:clear',
          'presentation:disconnecting',
          'instances:save:signed-out',
          'credential:read',
          'credential:revoke:$_oldKey',
          'credential:delete',
          'lifecycle:clear',
          'presentation:disconnected',
        ]);
      },
    );

    test(
      'aborts before the account boundary when draft cleanup fails',
      () async {
        final fixture = _Fixture(failures: {_Failure.clearDrafts});

        final result = await fixture.coordinator.disconnect(_siteUrl);

        expect(result.outcome, AccountDisconnectionOutcome.failed);
        expect(fixture.current.user, _accountA);
        expect((await fixture.durable).user, _accountA);
        fixture.expectPrivateStateIsCoherent();
      },
    );

    test(
      'aborts before key deletion when both snapshot attempts fail',
      () async {
        final fixture = _Fixture(failingSaveCalls: {1, 2});

        final result = await fixture.coordinator.disconnect(_siteUrl);

        expect(result.outcome, AccountDisconnectionOutcome.failed);
        expect(fixture.current.user, _accountA);
        expect((await fixture.durable).user, _accountA);
        expect(fixture.authenticator.keys[_siteUrl], _oldKey);
        expect(fixture.events, isNot(contains('credential:delete')));
      },
    );

    for (final failure in [
      _Failure.readCredential,
      _Failure.revokeOld,
      _Failure.deleteCredential,
    ]) {
      test('keeps signed-out metadata when ${failure.name} fails', () async {
        final fixture = _Fixture(failures: {failure});

        final result = await fixture.coordinator.disconnect(_siteUrl);

        expect(result.outcome, AccountDisconnectionOutcome.disconnected);
        expect(fixture.current.user, isNull);
        expect((await fixture.durable).user, isNull);
        if (failure == _Failure.deleteCredential) {
          expect(fixture.authenticator.keys[_siteUrl], _oldKey);
        } else {
          expect(fixture.authenticator.keys[_siteUrl], isNull);
        }
        fixture.expectPrivateStateIsCoherent();
      });
    }

    for (final failure in [_Failure.readCredential, _Failure.revokeOld]) {
      test(
        'restores the account when required revocation fails at ${failure.name}',
        () async {
          final fixture = _Fixture(failures: {failure});

          final result = await fixture.coordinator.disconnect(
            _siteUrl,
            requireRemoteRevocation: true,
          );

          expect(result.outcome, AccountDisconnectionOutcome.failed);
          expect(fixture.current.user, _accountA);
          expect((await fixture.durable).user, _accountA);
          expect(fixture.authenticator.keys[_siteUrl], _oldKey);
          expect(fixture.events, isNot(contains('credential:delete')));
          expect(
            fixture.events,
            containsAllInOrder([
              'presentation:disconnecting',
              if (failure == _Failure.revokeOld) 'credential:revoke:$_oldKey',
              'lifecycle:clear',
              'presentation:restored',
              'instances:save:account-a',
            ]),
          );
          fixture.expectPrivateStateIsCoherent();
        },
      );
    }
  });

  group('AccountSessionCoordinator real-store disconnect', () {
    test('coalesced disconnects durably sign out both sites', () async {
      final fixture = await _RealStoreFixture.create();
      final gate = fixture.persistence.gates[2] = Completer<void>();
      final ordinarySave = fixture.instances.save(
        fixture.host.accountSessionInstances,
      );
      await fixture.persistence.waitForWrite(2);

      final firstSnapshot = fixture.host.nextSnapshot;
      final firstDisconnect = fixture.coordinator.disconnect(_siteUrl);
      await firstSnapshot;
      final secondSnapshot = fixture.host.nextSnapshot;
      final secondDisconnect = fixture.coordinator.disconnect(_otherSiteUrl);
      await secondSnapshot;

      gate.complete();
      await ordinarySave;
      final results = await Future.wait([firstDisconnect, secondDisconnect]);

      expect(
        results.map((result) => result.outcome),
        everyElement(AccountDisconnectionOutcome.disconnected),
      );
      expect(fixture.persistence.writeCount, 3);
      expect(
        fixture.snapshotsAtDeletion.keys,
        containsAll([_siteUrl, _otherSiteUrl]),
      );
      expect([
        for (final snapshot in [
          ...fixture.snapshotsAtDeletion.values,
          await fixture.instances.load(),
        ])
          for (final instance in snapshot) instance.user,
      ], everyElement(isNull));
      expect(fixture.authenticator.keys, isEmpty);
      expect(fixture.reports, isEmpty);
    });

    for (final reorder in [false, true]) {
      test(
        '${reorder ? 'reorder' : 'metadata'} saves retain a pending sign-out',
        () async {
          final fixture = await _RealStoreFixture.create();
          final gate = fixture.persistence.gates[2] = Completer<void>();
          final ordinarySave = fixture.instances.save(
            fixture.host.accountSessionInstances,
          );
          await fixture.persistence.waitForWrite(2);

          final snapshot = fixture.host.nextSnapshot;
          final disconnect = fixture.coordinator.disconnect(_siteUrl);
          await snapshot;
          final other = fixture.host._instances
              .removeAt(1)
              .copyWith(
                title: 'Updated other forum',
                notificationTotals: const NotificationTotals(
                  unreadNotifications: 7,
                ),
              );
          fixture.host._instances.insert(reorder ? 0 : 1, other);
          final metadataSave = fixture.instances.save(
            fixture.host.accountSessionInstances,
          );

          gate.complete();
          await Future.wait([ordinarySave, metadataSave]);
          final result = await disconnect;
          final durable = await fixture.instances.load();

          expect(result.outcome, AccountDisconnectionOutcome.disconnected);
          expect(fixture.persistence.writeCount, 3);
          expect([
            fixture.snapshotsAtDeletion[_siteUrl]!
                .singleWhere((item) => item.url == _siteUrl)
                .user,
            durable.singleWhere((item) => item.url == _siteUrl).user,
          ], everyElement(isNull));
          expect(
            durable.map((item) => item.url),
            reorder ? [_otherSiteUrl, _siteUrl] : [_siteUrl, _otherSiteUrl],
          );
          final durableOther = durable.singleWhere(
            (item) => item.url == _otherSiteUrl,
          );
          expect(durableOther.toJson(), other.toJson());
          expect(fixture.authenticator.keys, {_otherSiteUrl: 'other-site-key'});
        },
      );
    }

    test(
      'repairs a published sign-out after both persistence attempts fail',
      () async {
        final fixture = await _RealStoreFixture.create();
        fixture.persistence.failingWrites.addAll([2, 4]);
        final firstGate = fixture.persistence.gates[2] = Completer<void>();
        final retryGate = fixture.persistence.gates[4] = Completer<void>();
        final initial = fixture.host.accountSessionInstance(_siteUrl)!;
        final disconnect = fixture.coordinator.disconnect(_siteUrl);
        await fixture.persistence.waitForWrite(2);

        expect(fixture.host.accountSessionInstance(_siteUrl)!.user, isNull);
        expect(fixture.authenticator.keys[_siteUrl], _oldKey);
        final other = fixture.host._instances
            .removeAt(1)
            .copyWith(
              title: 'Updated other forum',
              notificationTotals: const NotificationTotals(
                unreadNotifications: 7,
              ),
            );
        fixture.host._instances.insert(0, other);
        final metadataSave = fixture.instances.save(
          fixture.host.accountSessionInstances,
        );

        firstGate.complete();
        await metadataSave;
        await fixture.persistence.waitForWrite(4);
        // An ordinary snapshot has already made the optimistic sign-out
        // durable, even though both of the disconnect's own attempts fail.
        expect(
          fixture.persistence.durable
              .singleWhere((item) => item.url == _siteUrl)
              .user,
          isNull,
        );
        retryGate.complete();
        final result = await disconnect;
        final durable = await fixture.instances.load();

        expect(result.outcome, AccountDisconnectionOutcome.failed);
        expect(fixture.persistence.writeCount, 5);
        expect(fixture.snapshotsAtDeletion, isEmpty);
        expect(fixture.authenticator.keys[_siteUrl], _oldKey);
        expect(
          fixture.host.accountSessionInstance(_siteUrl)!.toJson(),
          initial.toJson(),
        );
        expect(durable.map((item) => item.toJson()), [
          other.toJson(),
          initial.toJson(),
        ]);
        expect(
          fixture.events.where((event) => event.startsWith('presentation:')),
          ['presentation:disconnecting', 'presentation:restored'],
        );
        expect(fixture.reports, [
          (operation: 'authentication.persistSignedOut', warning: true),
          (operation: 'authentication.persistSignedOut', warning: false),
        ]);
      },
    );

    test(
      'required revocation rollback preserves an independent disconnect',
      () async {
        final fixture = await _RealStoreFixture.create(
          failures: {_Failure.revokeOld},
        );
        fixture.api.firstRevocationGate = Completer<void>();
        final firstDisconnect = fixture.coordinator.disconnect(
          _siteUrl,
          requireRemoteRevocation: true,
        );
        await fixture.api.firstRevocationStarted.future;

        final secondResult = await fixture.coordinator.disconnect(
          _otherSiteUrl,
        );
        expect(secondResult.outcome, AccountDisconnectionOutcome.disconnected);
        expect(fixture.authenticator.keys[_siteUrl], _oldKey);
        expect(fixture.authenticator.keys[_otherSiteUrl], isNull);

        fixture.api.firstRevocationGate!.complete();
        final firstResult = await firstDisconnect;
        final durable = await fixture.instances.load();

        expect(firstResult.outcome, AccountDisconnectionOutcome.failed);
        expect(durable.map((item) => item.user), [_accountA, null]);
        expect(fixture.authenticator.keys, {_siteUrl: _oldKey});
        expect(fixture.snapshotsAtDeletion.keys, [_otherSiteUrl]);
        expect(fixture.reports, [
          (operation: 'authentication.revokeKey', warning: false),
        ]);
      },
    );

    for (final failPersistence in [false, true]) {
      test(
        'a stale ${failPersistence ? 'failed' : 'successful'} save cannot undo a reconnect',
        () async {
          final fixture = await _RealStoreFixture.create();
          final gate = fixture.persistence.gates[2] = Completer<void>();
          if (failPersistence) fixture.persistence.failingWrites.add(2);
          final disconnect = fixture.coordinator.disconnect(_siteUrl);
          await fixture.persistence.waitForWrite(2);

          final nextSnapshot = fixture.host.nextSnapshot;
          final reconnect = fixture.coordinator.connect(_siteUrl);
          await nextSnapshot;
          gate.complete();
          final connected = await reconnect;
          final disconnected = await disconnect;

          expect(connected.outcome, AccountConnectionOutcome.connected);
          expect(disconnected.outcome, AccountDisconnectionOutcome.stale);
          expect(
            fixture.host.accountSessionInstance(_siteUrl)!.user,
            _accountB,
          );
          expect(
            (await fixture.instances.load())
                .singleWhere((item) => item.url == _siteUrl)
                .user,
            _accountB,
          );
          expect(fixture.authenticator.keys[_siteUrl], _newKey);
          expect(fixture.snapshotsAtDeletion, isEmpty);
          expect(fixture.events, isNot(contains('presentation:restored')));
        },
      );
    }
  });

  group('AccountSessionCoordinator stale completions', () {
    test('revokes authorization completed after disconnect', () async {
      final fixture = _Fixture();
      fixture.authenticator.authorizeGate = Completer<void>();

      final connecting = fixture.coordinator.connect(_siteUrl);
      await fixture.authenticator.authorizeStarted.future;
      final disconnected = await fixture.coordinator.disconnect(_siteUrl);
      fixture.authenticator.authorizeGate!.complete();
      final connected = await connecting;

      expect(disconnected.outcome, AccountDisconnectionOutcome.disconnected);
      expect(connected.outcome, AccountConnectionOutcome.stale);
      expect(fixture.current.user, isNull);
      expect(fixture.authenticator.keys[_siteUrl], isNull);
      expect(fixture.events, contains('credential:revoke:$_newKey'));
    });

    test('revokes an account lookup completed after disconnect', () async {
      final fixture = _Fixture();
      fixture.api.lookupGate = Completer<void>();

      final connecting = fixture.coordinator.connect(_siteUrl);
      await fixture.api.lookupStarted.future;
      final disconnected = await fixture.coordinator.disconnect(_siteUrl);
      fixture.api.lookupGate!.complete();
      final connected = await connecting;

      expect(disconnected.outcome, AccountDisconnectionOutcome.disconnected);
      expect(connected.outcome, AccountConnectionOutcome.stale);
      expect(fixture.current.user, isNull);
      expect(fixture.authenticator.keys[_siteUrl], isNull);
      expect(fixture.events, contains('credential:revoke:$_newKey'));
    });

    test('cannot let an old disconnect delete a newer account', () async {
      final fixture = _Fixture();
      fixture.api.firstRevocationGate = Completer<void>();

      final disconnecting = fixture.coordinator.disconnect(_siteUrl);
      await fixture.api.firstRevocationStarted.future;
      final connecting = await fixture.coordinator.connect(_siteUrl);
      fixture.api.firstRevocationGate!.complete();
      final disconnected = await disconnecting;

      expect(connecting.outcome, AccountConnectionOutcome.connected);
      expect(disconnected.outcome, AccountDisconnectionOutcome.stale);
      expect(fixture.current.user, _accountB);
      expect((await fixture.durable).user, _accountB);
      expect(fixture.authenticator.keys[_siteUrl], _newKey);
      fixture.expectPrivateStateIsCoherent();
    });
  });
}
