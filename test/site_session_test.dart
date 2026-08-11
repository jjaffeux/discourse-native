import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/site_appearance_fixtures.dart';

const _siteUrl = 'https://meta.discourse.org';

final class _AccountFeedApi extends FakeDiscourseApi {
  _AccountFeedApi(this.firstGate)
    : super(user: const DiscourseUser(id: 2, username: 'account-b'));

  final Completer<void> firstGate;
  int requests = 0;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    requests++;
    if (requests == 1) {
      await firstGate.future;
      return const TopicList(
        topics: [Topic(id: 1, title: 'Private to A', slug: 'private-a')],
      );
    }
    return const TopicList(
      topics: [Topic(id: 2, title: 'Visible to B', slug: 'visible-b')],
    );
  }
}

final class _GatedAuthenticator extends FakeAuthenticator {
  _GatedAuthenticator(this.gate);

  final Completer<void> gate;
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> connect(String siteUrl) async {
    connected.add(siteUrl);
    started.complete();
    await gate.future;
    const result = UserApiCredentials(
      key: 'new-account-key',
      apiVersion: 4,
      push: false,
    );
    keys[siteUrl] = result.key;
    return result;
  }
}

final class _GatedAuthFailureAuthenticator extends FakeAuthenticator {
  _GatedAuthFailureAuthenticator(this.gate);

  final Completer<void> gate;
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> connect(String siteUrl) async {
    connected.add(siteUrl);
    started.complete();
    await gate.future;
    throw const UserApiAuthException(UserApiAuthFailure.launchFailed);
  }
}

final class _GatedCurrentUserApi extends FakeDiscourseApi {
  _GatedCurrentUserApi(this.currentUserGate);

  final Completer<void> currentUserGate;
  final started = Completer<void>();
  final List<String> revokedKeys = [];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    started.complete();
    await currentUserGate.future;
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    revokedKeys.add(apiKey);
  }
}

final class _ConnectRaceAppearanceApi extends FakeDiscourseApi {
  _ConnectRaceAppearanceApi({
    required this.initialAnonymousAppearance,
    required this.racingAnonymousAppearance,
    required this.accountAppearance,
  });

  final SiteAppearance initialAnonymousAppearance;
  final SiteAppearance racingAnonymousAppearance;
  final SiteAppearance accountAppearance;
  final initialAppearanceStarted = Completer<void>();
  final currentUserStarted = Completer<void>();
  final finishCurrentUser = Completer<void>();
  final racingAppearanceStarted = Completer<void>();
  final finishRacingAppearance = Completer<void>();
  final accountAppearanceStarted = Completer<void>();
  final List<({String? apiKey, String? clientId})> targetAppearanceRequests =
      [];
  final List<String?> targetAppearanceUsernames = [];
  int _anonymousAppearanceRequests = 0;

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    if (siteUrl != _siteUrl) return null;
    targetAppearanceRequests.add((apiKey: apiKey, clientId: clientId));
    targetAppearanceUsernames.add(username);

    if (apiKey != null) {
      if (!accountAppearanceStarted.isCompleted) {
        accountAppearanceStarted.complete();
      }
      return accountAppearance;
    }

    _anonymousAppearanceRequests++;
    if (_anonymousAppearanceRequests == 1) {
      initialAppearanceStarted.complete();
      return initialAnonymousAppearance;
    }

    if (!racingAppearanceStarted.isCompleted) {
      racingAppearanceStarted.complete();
    }
    await finishRacingAppearance.future;
    return racingAnonymousAppearance;
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    currentUserStarted.complete();
    await finishCurrentUser.future;
    return const DiscourseUser(id: 2, username: 'account-b');
  }
}

final class _RollbackAppearanceApi extends FakeDiscourseApi {
  _RollbackAppearanceApi({
    required this.authenticator,
    required this.signedOutAppearance,
    required this.accountAppearance,
  });

  final FakeAuthenticator authenticator;
  final SiteAppearance signedOutAppearance;
  final SiteAppearance accountAppearance;
  final initialAppearanceStarted = Completer<void>();
  final revocationStarted = Completer<void>();
  final finishRevocation = Completer<void>();
  final List<({String? apiKey, bool credentialsDiscarded})> appearanceRequests =
      [];

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    appearanceRequests.add((
      apiKey: apiKey,
      credentialsDiscarded:
          authenticator.disconnected.contains(siteUrl) &&
          !authenticator.keys.containsKey(siteUrl),
    ));
    if (!initialAppearanceStarted.isCompleted) {
      initialAppearanceStarted.complete();
    }
    return apiKey == null ? signedOutAppearance : accountAppearance;
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (!revocationStarted.isCompleted) revocationStarted.complete();
    await finishRevocation.future;
  }
}

final class _DisconnectAppearanceApi extends FakeDiscourseApi {
  _DisconnectAppearanceApi({
    required this.signedOutAppearance,
    required this.accountAppearance,
  });

  final SiteAppearance signedOutAppearance;
  final SiteAppearance accountAppearance;
  final initialAppearanceStarted = Completer<void>();
  final signedOutAppearanceStarted = Completer<void>();
  final List<({String? apiKey, String? clientId})> appearanceRequests = [];
  final List<({String? apiKey, String? clientId})> configRequests = [];
  final List<({String? apiKey, String? clientId})> customEmojiRequests = [];

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    appearanceRequests.add((apiKey: apiKey, clientId: clientId));
    if (appearanceRequests.length == 1) {
      initialAppearanceStarted.complete();
    } else if (!signedOutAppearanceStarted.isCompleted) {
      signedOutAppearanceStarted.complete();
    }
    return apiKey == null ? signedOutAppearance : accountAppearance;
  }

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    configRequests.add((apiKey: apiKey, clientId: clientId));
    return const SiteConfig.unknown();
  }

  @override
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    customEmojiRequests.add((apiKey: apiKey, clientId: clientId));
    return const {};
  }
}

final class _DisconnectRaceAppearanceApi extends FakeDiscourseApi {
  _DisconnectRaceAppearanceApi({
    required this.initialAccountAppearance,
    required this.racingAccountAppearance,
    required this.signedOutAppearance,
  });

  final SiteAppearance initialAccountAppearance;
  final SiteAppearance racingAccountAppearance;
  final SiteAppearance signedOutAppearance;
  final initialAppearanceStarted = Completer<void>();
  final revocationStarted = Completer<void>();
  final finishRevocation = Completer<void>();
  final racingAppearanceStarted = Completer<void>();
  final finishRacingAppearance = Completer<void>();
  final signedOutAppearanceStarted = Completer<void>();
  final List<({String? apiKey, String? clientId})> targetAppearanceRequests =
      [];
  int _accountAppearanceRequests = 0;

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    if (siteUrl != _siteUrl) return null;
    targetAppearanceRequests.add((apiKey: apiKey, clientId: clientId));
    if (apiKey == null) {
      if (!signedOutAppearanceStarted.isCompleted) {
        signedOutAppearanceStarted.complete();
      }
      return signedOutAppearance;
    }

    _accountAppearanceRequests++;
    if (_accountAppearanceRequests == 1) {
      initialAppearanceStarted.complete();
      return initialAccountAppearance;
    }
    if (!racingAppearanceStarted.isCompleted) {
      racingAppearanceStarted.complete();
    }
    await finishRacingAppearance.future;
    return racingAccountAppearance;
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (!revocationStarted.isCompleted) revocationStarted.complete();
    await finishRevocation.future;
  }
}

final class _GatedRevocationApi extends FakeDiscourseApi {
  _GatedRevocationApi(this.firstGate)
    : super(user: const DiscourseUser(id: 2, username: 'account-b'));

  final Completer<void> firstGate;
  final firstStarted = Completer<void>();
  final List<String> revokedKeys = [];

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    revokedKeys.add(apiKey);
    if (revokedKeys.length != 1) return;
    firstStarted.complete();
    await firstGate.future;
  }
}

final class _GatedTopicApi extends FakeDiscourseApi {
  _GatedTopicApi(this._requestGate);

  final Completer<void> _requestGate;
  final started = Completer<void>();

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    String? apiKey,
    String? clientId,
  }) async {
    started.complete();
    await _requestGate.future;
    return topicPayload(id: id, title: 'First site title');
  }
}

final class _GatedAccountHealingApi extends FakeDiscourseApi {
  _GatedAccountHealingApi(this.accountGate);

  final Completer<void> accountGate;
  final started = Completer<void>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    started.complete();
    await accountGate.future;
    return const DiscourseUser(id: 42, username: 'account-a');
  }
}

final class _RecordingInstanceStore extends FakeInstanceStore {
  _RecordingInstanceStore(super.instances);

  final List<List<DiscourseInstance>> snapshots = [];

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    snapshots.add(List.of(instances));
    await super.save(instances);
  }
}

final class _GatedInstanceStore extends FakeInstanceStore {
  _GatedInstanceStore(super.instances, this.gate);

  final Completer<void> gate;
  final Completer<void> loadStarted = Completer<void>();
  int loadCount = 0;

  @override
  Future<List<DiscourseInstance>> load() async {
    loadCount++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    await gate.future;
    return super.load();
  }
}

final class _FailingConnectedSaveStore extends FakeInstanceStore {
  _FailingConnectedSaveStore(super.instances);

  int saveAttempts = 0;
  bool failedConnectedSnapshot = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    saveAttempts++;
    if (!failedConnectedSnapshot && instances.any((item) => item.isConnected)) {
      failedConnectedSnapshot = true;
      throw StateError('preferences unavailable');
    }
    await super.save(instances);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adding a site waits for the initial stored snapshot', () async {
    final gate = Completer<void>();
    final stored = instance('stored.example.com');
    final added = instance('added.example.com');
    final instanceStore = _GatedInstanceStore([stored], gate);
    final shell = ShellController(
      instanceStore: instanceStore,
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);

    final loading = shell.load();
    await instanceStore.loadStarted.future;
    final adding = shell.addInstance(added);
    await Future<void>.delayed(Duration.zero);

    expect(instanceStore.loadCount, 1);
    expect(instanceStore.saveCount, 0);
    expect(shell.instances, isEmpty);

    gate.complete();
    await Future.wait([loading, adding]);

    expect(shell.instances, [stored, added]);
    expect(await instanceStore.load(), [stored, added]);
  });

  test('an old account response cannot replace a new account feed', () async {
    final firstGate = Completer<void>();
    final api = _AccountFeedApi(firstGate);
    final oldAccount = instance(
      'meta.discourse.org',
    ).copyWith(user: const DiscourseUser(id: 1, username: 'account-a'));
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'account-a-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([oldAccount]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);

    await shell.load();
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, 1);

    await shell.connectCurrentInstance();
    await Future<void>.delayed(Duration.zero);
    expect(shell.currentInstance?.user?.username, 'account-b');
    expect(shell.currentFeed?.topicIds, [2]);

    firstGate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(shell.currentFeed?.topicIds, [2]);
    expect(shell.store.read<Topic>(_siteUrl, 1), isNull);
    expect(shell.store.read<Topic>(_siteUrl, 2)?.title, 'Visible to B');
  });

  test('account healing cannot persist after a reentrant disconnect', () async {
    final gate = Completer<void>();
    final api = _GatedAccountHealingApi(gate);
    final connected = instance(
      'meta.discourse.org',
    ).copyWith(user: const DiscourseUser(username: 'account-a'));
    final store = _RecordingInstanceStore([connected]);
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'account-a-key';
    final shell = ShellController(
      instanceStore: store,
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);

    var disconnectStarted = false;
    Future<void>? disconnecting;
    final listenerRan = Completer<void>();
    shell.addListener(() {
      if (disconnectStarted || shell.currentInstance?.user?.id != 42) return;
      disconnectStarted = true;
      disconnecting = shell.disconnectCurrentInstance();
      listenerRan.complete();
    });

    await shell.load();
    await api.started.future;
    gate.complete();
    await listenerRan.future;
    await disconnecting;
    await Future<void>.delayed(Duration.zero);

    expect(
      store.snapshots.where(
        (snapshot) => snapshot.any((item) => item.user?.id == 42),
      ),
      isEmpty,
    );
    expect((await store.load()).single.user, isNull);
  });

  test(
    'a failed account lookup cannot leave old metadata beside a new key',
    () async {
      final currentUserGate = Completer<void>();
      final api = _GatedCurrentUserApi(currentUserGate);
      final oldAccount = instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'account-a'));
      final store = FakeInstanceStore([oldAccount]);
      final authenticator = FakeAuthenticator(
        credentials: const UserApiCredentials(
          key: 'account-b-key',
          apiVersion: 4,
          push: false,
        ),
      )..keys[_siteUrl] = 'account-a-key';
      final shell = ShellController(
        instanceStore: store,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      final connecting = shell.connectCurrentInstance();
      await api.started.future;

      expect(shell.currentInstance?.user, isNull);
      expect((await store.load()).single.user, isNull);
      expect(authenticator.keys[_siteUrl], 'account-b-key');

      currentUserGate.complete();
      await connecting;

      expect(shell.currentInstance?.user, isNull);
      expect((await store.load()).single.user, isNull);
      expect(authenticator.keys[_siteUrl], isNull);
      expect(api.revokedKeys, ['account-a-key', 'account-b-key']);
      expect(shell.connectError, isNotNull);
    },
  );

  for (final anonymousAppearanceCompletesBeforeConnect in [true, false]) {
    test(
      anonymousAppearanceCompletesBeforeConnect
          ? 'connect replaces an anonymous appearance completed during lookup'
          : 'connect rejects an anonymous appearance completed after lookup',
      () async {
        const otherSite = 'https://other.example.com';
        final initialAnonymousAppearance = siteAppearance(
          accent: const Color(0xFF112233),
        );
        final racingAnonymousAppearance = siteAppearance(
          accent: const Color(0xFF0066BB),
        );
        final accountAppearance = siteAppearance(
          accent: const Color(0xFFAA2200),
        );
        final store = FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(appearance: initialAnonymousAppearance),
          instance('other.example.com'),
        ]);
        final authenticator = FakeAuthenticator(
          credentials: const UserApiCredentials(
            key: 'account-b-key',
            apiVersion: 4,
            push: false,
          ),
        );
        final api = _ConnectRaceAppearanceApi(
          initialAnonymousAppearance: initialAnonymousAppearance,
          racingAnonymousAppearance: racingAnonymousAppearance,
          accountAppearance: accountAppearance,
        );
        addTearDown(() {
          if (!api.finishCurrentUser.isCompleted) {
            api.finishCurrentUser.complete();
          }
          if (!api.finishRacingAppearance.isCompleted) {
            api.finishRacingAppearance.complete();
          }
        });
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await api.initialAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(shell.currentSiteAppearance, initialAnonymousAppearance);

        final connecting = shell.connectCurrentInstance();
        await api.currentUserStarted.future;

        // Re-entering the target while account lookup is held open starts a
        // public appearance request because the pending instance is signed out.
        shell.selectInstance(1);
        expect(shell.currentInstance?.url, otherSite);
        shell.selectInstance(0);
        await api.racingAppearanceStarted.future;

        if (anonymousAppearanceCompletesBeforeConnect) {
          api.finishRacingAppearance.complete();
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          expect(shell.currentSiteAppearance, racingAnonymousAppearance);
          api.finishCurrentUser.complete();
        } else {
          api.finishCurrentUser.complete();
          await api.accountAppearanceStarted.future;
          api.finishRacingAppearance.complete();
        }

        await connecting;
        await api.accountAppearanceStarted.future;
        for (
          var attempt = 0;
          attempt < 10 && shell.currentSiteAppearance != accountAppearance;
          attempt++
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(shell.currentInstance?.user?.username, 'account-b');
        expect(shell.currentSiteAppearance, accountAppearance);
        expect((await store.load()).first.appearance, accountAppearance);
        expect(api.targetAppearanceRequests, [
          (apiKey: null, clientId: null),
          (apiKey: null, clientId: null),
          (apiKey: 'account-b-key', clientId: 'test-client'),
        ]);
        expect(api.targetAppearanceUsernames, [null, null, 'account-b']);
      },
    );
  }

  test(
    'a failed connection refreshes appearance only after discarding its key',
    () async {
      final signedOutAppearance = siteAppearance();
      final accountAppearance = siteAppearance(accent: const Color(0xFFAA2200));
      final stored = instance(
        'meta.discourse.org',
      ).copyWith(appearance: signedOutAppearance);
      final store = FakeInstanceStore([stored]);
      final authenticator = FakeAuthenticator(
        credentials: const UserApiCredentials(
          key: 'discarded-account-key',
          apiVersion: 4,
          push: false,
        ),
      );
      final api = _RollbackAppearanceApi(
        authenticator: authenticator,
        signedOutAppearance: signedOutAppearance,
        accountAppearance: accountAppearance,
      );
      final shell = ShellController(
        instanceStore: store,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await api.initialAppearanceStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(api.appearanceRequests, [
        (apiKey: null, credentialsDiscarded: false),
      ]);

      final connecting = shell.connectCurrentInstance();
      await api.revocationStarted.future;
      await Future<void>.delayed(Duration.zero);

      // Rollback has already cleared the account presentation, but revocation
      // is deliberately held open and the replacement key still exists. No
      // appearance request may cross that boundary with the doomed key.
      expect(authenticator.keys[_siteUrl], 'discarded-account-key');
      expect(api.appearanceRequests, [
        (apiKey: null, credentialsDiscarded: false),
      ]);

      api.finishRevocation.complete();
      await connecting;
      await Future<void>.delayed(Duration.zero);

      expect(authenticator.keys[_siteUrl], isNull);
      expect(api.appearanceRequests, [
        (apiKey: null, credentialsDiscarded: false),
        (apiKey: null, credentialsDiscarded: true),
      ]);
      expect(shell.currentSiteAppearance, signedOutAppearance);
      expect((await store.load()).single.appearance, signedOutAppearance);
      expect(shell.connectError, isNotNull);
    },
  );

  test(
    'a failed private connection never retries appearance anonymously',
    () async {
      final stored = instance(
        'meta.discourse.org',
      ).copyWith(loginRequired: true);
      final store = FakeInstanceStore([stored]);
      final authenticator = FakeAuthenticator(
        credentials: const UserApiCredentials(
          key: 'discarded-account-key',
          apiVersion: 4,
          push: false,
        ),
      );
      final api = _RollbackAppearanceApi(
        authenticator: authenticator,
        signedOutAppearance: siteAppearance(),
        accountAppearance: siteAppearance(accent: const Color(0xFFAA2200)),
      );
      addTearDown(() {
        if (!api.finishRevocation.isCompleted) api.finishRevocation.complete();
      });
      final shell = ShellController(
        instanceStore: store,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await Future<void>.delayed(Duration.zero);
      expect(api.appearanceRequests, isEmpty);

      final connecting = shell.connectCurrentInstance();
      await api.revocationStarted.future;
      api.finishRevocation.complete();
      await connecting;
      await Future<void>.delayed(Duration.zero);

      expect(authenticator.keys[_siteUrl], isNull);
      expect(api.appearanceRequests, isEmpty);
      expect(shell.connectError, isNotNull);
    },
  );

  test(
    'a failed key deletion cannot authenticate a signed-out appearance',
    () async {
      final signedOutAppearance = siteAppearance();
      final accountAppearance = siteAppearance(accent: const Color(0xFFAA2200));
      final stored = instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'account'));
      final store = FakeInstanceStore([stored]);
      final authenticator = FakeAuthenticator(
        disconnectFailure: StateError('keychain unavailable'),
      )..keys[_siteUrl] = 'orphaned-account-key';
      final api = _DisconnectAppearanceApi(
        signedOutAppearance: signedOutAppearance,
        accountAppearance: accountAppearance,
      );
      final shell = ShellController(
        instanceStore: store,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await api.initialAppearanceStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(api.appearanceRequests, [
        (apiKey: 'orphaned-account-key', clientId: 'test-client'),
      ]);
      expect(api.configRequests, [
        (apiKey: 'orphaned-account-key', clientId: 'test-client'),
      ]);
      expect(api.customEmojiRequests, [
        (apiKey: 'orphaned-account-key', clientId: 'test-client'),
      ]);

      expect(await shell.disconnectInstance(_siteUrl), isTrue);
      await api.signedOutAppearanceStarted.future;
      await Future<void>.delayed(Duration.zero);

      // The keychain failure deliberately leaves the key behind. Instance
      // identity, rather than key presence alone, must prevent it reaching the
      // forum document once the account has been signed out.
      expect(authenticator.keys[_siteUrl], 'orphaned-account-key');
      expect(shell.currentInstance?.user, isNull);
      expect(api.appearanceRequests, [
        (apiKey: 'orphaned-account-key', clientId: 'test-client'),
        (apiKey: null, clientId: null),
      ]);
      expect(api.configRequests, [
        (apiKey: 'orphaned-account-key', clientId: 'test-client'),
        (apiKey: null, clientId: null),
      ]);
      expect(api.customEmojiRequests, [
        (apiKey: 'orphaned-account-key', clientId: 'test-client'),
        (apiKey: null, clientId: null),
      ]);
      expect(shell.currentSiteAppearance, signedOutAppearance);
      expect((await store.load()).single.appearance, signedOutAppearance);
      expect(api.revoked, [_siteUrl]);
    },
  );

  for (final accountAppearanceCompletesBeforeSignOut in [true, false]) {
    test(
      accountAppearanceCompletesBeforeSignOut
          ? 'disconnect drops an account appearance completed during revocation'
          : 'disconnect rejects an account appearance completed after sign-out',
      () async {
        const otherSite = 'https://other.example.com';
        final initialAccountAppearance = siteAppearance(
          accent: const Color(0xFF112233),
        );
        final racingAccountAppearance = siteAppearance(
          accent: const Color(0xFFAA2200),
        );
        final signedOutAppearance = siteAppearance(
          accent: const Color(0xFF0066BB),
        );
        final store = FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'account')),
          instance('other.example.com'),
        ]);
        final authenticator = FakeAuthenticator()
          ..keys[_siteUrl] = 'account-key';
        final api = _DisconnectRaceAppearanceApi(
          initialAccountAppearance: initialAccountAppearance,
          racingAccountAppearance: racingAccountAppearance,
          signedOutAppearance: signedOutAppearance,
        );
        addTearDown(() {
          if (!api.finishRevocation.isCompleted) {
            api.finishRevocation.complete();
          }
          if (!api.finishRacingAppearance.isCompleted) {
            api.finishRacingAppearance.complete();
          }
        });
        final shell = ShellController(
          instanceStore: store,
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);

        await shell.load();
        await api.initialAppearanceStarted.future;
        await Future<void>.delayed(Duration.zero);

        final disconnecting = shell.disconnectInstance(_siteUrl);
        await api.revocationStarted.future;

        // Re-entering the site while revocation is held open starts a new
        // authenticated appearance request in the generation created by the
        // first forget.
        shell.selectInstance(1);
        expect(shell.currentInstance?.url, otherSite);
        shell.selectInstance(0);
        await api.racingAppearanceStarted.future;
        expect(api.targetAppearanceRequests, [
          (apiKey: 'account-key', clientId: 'test-client'),
          (apiKey: 'account-key', clientId: 'test-client'),
        ]);

        if (accountAppearanceCompletesBeforeSignOut) {
          api.finishRacingAppearance.complete();
          await Future<void>.delayed(Duration.zero);
          expect(shell.currentSiteAppearance, racingAccountAppearance);
        }

        api.finishRevocation.complete();
        expect(await disconnecting, isTrue);
        await api.signedOutAppearanceStarted.future;

        if (!accountAppearanceCompletesBeforeSignOut) {
          api.finishRacingAppearance.complete();
        }
        await Future<void>.delayed(Duration.zero);

        expect(authenticator.keys[_siteUrl], isNull);
        expect(shell.currentInstance?.user, isNull);
        expect(api.targetAppearanceRequests, [
          (apiKey: 'account-key', clientId: 'test-client'),
          (apiKey: 'account-key', clientId: 'test-client'),
          (apiKey: null, clientId: null),
        ]);
        expect(shell.currentSiteAppearance, signedOutAppearance);
        expect(
          (await store.load())
              .firstWhere((instance) => instance.url == _siteUrl)
              .appearance,
          signedOutAppearance,
        );
      },
    );
  }

  test('removal survives an instance replacement during revocation', () async {
    const otherSite = 'https://other.example.com';
    final initialAccountAppearance = siteAppearance(
      accent: const Color(0xFF112233),
    );
    final racingAccountAppearance = siteAppearance(
      accent: const Color(0xFFAA2200),
    );
    final signedOutAppearance = siteAppearance(accent: const Color(0xFF0066BB));
    final connected = instance(
      'meta.discourse.org',
    ).copyWith(user: const DiscourseUser(id: 7, username: 'account'));
    final store = FakeInstanceStore([connected, instance('other.example.com')]);
    final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'account-key';
    final api = _DisconnectRaceAppearanceApi(
      initialAccountAppearance: initialAccountAppearance,
      racingAccountAppearance: racingAccountAppearance,
      signedOutAppearance: signedOutAppearance,
    );
    addTearDown(() {
      if (!api.finishRevocation.isCompleted) {
        api.finishRevocation.complete();
      }
      if (!api.finishRacingAppearance.isCompleted) {
        api.finishRacingAppearance.complete();
      }
    });
    final shell = ShellController(
      instanceStore: store,
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);

    await shell.load();
    await api.initialAppearanceStarted.future;
    await Future<void>.delayed(Duration.zero);

    final removing = shell.removeInstance(connected);
    await api.revocationStarted.future;
    shell.selectInstance(1);
    shell.selectInstance(0);
    await api.racingAppearanceStarted.future;

    // This accepted response replaces the immutable instance object while
    // removeInstance still holds the older snapshot supplied by its caller.
    api.finishRacingAppearance.complete();
    await Future<void>.delayed(Duration.zero);
    expect(shell.currentSiteAppearance, racingAccountAppearance);

    api.finishRevocation.complete();
    expect(await removing, isTrue);
    expect(authenticator.keys[_siteUrl], isNull);
    expect(shell.instances.map((instance) => instance.url), [otherSite]);
    expect((await store.load()).map((instance) => instance.url), [otherSite]);

    // Re-adding the URL in the same process must start from public colors;
    // the account palette completed during revocation was forgotten.
    expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
    await api.signedOutAppearanceStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(api.targetAppearanceRequests, [
      (apiKey: 'account-key', clientId: 'test-client'),
      (apiKey: 'account-key', clientId: 'test-client'),
      (apiKey: null, clientId: null),
    ]);
    expect(shell.currentSiteAppearance, signedOutAppearance);
    expect(
      (await store.load())
          .firstWhere((instance) => instance.url == _siteUrl)
          .appearance,
      signedOutAppearance,
    );
  });

  test(
    'a failed connected-profile save rolls back the account and key',
    () async {
      final stored = instance('meta.discourse.org');
      final store = _FailingConnectedSaveStore([stored]);
      final authenticator = FakeAuthenticator();
      final api = FakeDiscourseApi(
        user: const DiscourseUser(id: 2, username: 'account-b'),
      );
      final shell = ShellController(
        instanceStore: store,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await shell.connectCurrentInstance();

      expect(shell.currentInstance?.user, isNull);
      expect((await store.load()).single.user, isNull);
      expect(authenticator.keys[_siteUrl], isNull);
      expect(store.failedConnectedSnapshot, isTrue);
      expect(store.saveAttempts, greaterThanOrEqualTo(3));
      expect(api.revoked, [_siteUrl]);
      expect(shell.connectError, isNotNull);
    },
  );

  test(
    'removing a site during browser auth discards the key that lands later',
    () async {
      final connectGate = Completer<void>();
      final authenticator = _GatedAuthenticator(connectGate);
      final stored = instance('meta.discourse.org');
      final api = FakeDiscourseApi();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([stored]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      final connecting = shell.connectCurrentInstance();
      await authenticator.started.future;
      await shell.removeInstance(stored);

      connectGate.complete();
      await connecting;

      expect(shell.instances, isEmpty);
      expect(authenticator.keys[_siteUrl], isNull);
      expect(authenticator.disconnected, [_siteUrl, _siteUrl]);
      expect(api.revoked, [_siteUrl]);
      expect(shell.connectError, isNull);
    },
  );

  test(
    'connection progress and errors stay with the site being connected',
    () async {
      final gate = Completer<void>();
      final authenticator = _GatedAuthFailureAuthenticator(gate);
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org'),
          instance('other.example.com'),
        ]),
        api: FakeDiscourseApi(),
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      final connecting = shell.connectCurrentInstance();
      await authenticator.started.future;

      expect(shell.connecting, isTrue);
      shell.selectInstance(1);
      expect(shell.connecting, isFalse);
      expect(shell.connectError, isNull);

      gate.complete();
      await connecting;

      expect(shell.instanceIndex, 1);
      expect(shell.connecting, isFalse);
      expect(shell.connectError, isNull);

      shell.selectInstance(0);
      expect(shell.connectError, contains('Could not open'));
    },
  );

  test('an old disconnect cannot delete a newer connection', () async {
    final firstRevocation = Completer<void>();
    final api = _GatedRevocationApi(firstRevocation);
    final oldAccount = instance(
      'meta.discourse.org',
    ).copyWith(user: const DiscourseUser(id: 1, username: 'account-a'));
    final authenticator = FakeAuthenticator(
      credentials: const UserApiCredentials(
        key: 'account-b-key',
        apiVersion: 4,
        push: false,
      ),
    )..keys[_siteUrl] = 'account-a-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([oldAccount]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);

    await shell.load();
    final disconnecting = shell.disconnectCurrentInstance();
    await api.firstStarted.future;

    await shell.connectCurrentInstance();
    expect(shell.currentInstance?.user?.username, 'account-b');
    expect(authenticator.keys[_siteUrl], 'account-b-key');

    firstRevocation.complete();
    await disconnecting;

    expect(shell.currentInstance?.user?.username, 'account-b');
    expect(authenticator.keys[_siteUrl], 'account-b-key');
    expect(api.revokedKeys, ['account-a-key', 'account-a-key']);
    expect(authenticator.disconnected, isEmpty);
  });

  test("an off-screen topic cannot retitle another site's route", () async {
    final gate = Completer<void>();
    final api = _GatedTopicApi(gate);
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org'),
        instance('other.example.com'),
      ]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(shell.dispose);

    await shell.load();
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'first', title: 'First placeholder'),
    );
    final loading = shell.loadTopic(7, 'first');
    await api.started.future;

    shell.selectInstance(1);
    shell.pushContent(
      ContentRoute.topic(
        topicId: 7,
        slug: 'second',
        title: 'Second site title',
      ),
    );

    gate.complete();
    await loading;

    expect(shell.currentContent?.title, 'Second site title');
    expect(
      shell.store.read<TopicDetail>('https://meta.discourse.org', 7)?.title,
      'First site title',
    );
  });
}
