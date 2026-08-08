import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

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
  _GatedTopicApi(this.topicGate);

  final Completer<void> topicGate;
  final started = Completer<void>();

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    started.complete();
    await topicGate.future;
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
