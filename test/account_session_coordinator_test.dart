import 'dart:async';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
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

  final List<String> events;
  final List<DiscourseInstance> _instances;

  @override
  bool accountSessionDisposed = false;

  @override
  List<DiscourseInstance> get accountSessionInstances =>
      List.unmodifiable(_instances);

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
          'instances:save:signed-out',
          'presentation:disconnecting',
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
