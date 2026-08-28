import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _otherSiteUrl = 'https://team.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', hidePresence: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'optimistically updates and persists the confirmed preference',
    () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final api = FakeDiscourseApi(
        user: _user,
        presenceGate: gate,
        feeds: const {'/latest.json': <Topic>[]},
      );
      final fixture = await _shell(api: api);
      addTearDown(fixture.shell.dispose);

      final write = fixture.shell.toggleHidePresence(_siteUrl);

      expect(fixture.shell.hidePresenceFor(_siteUrl), isTrue);
      expect(fixture.shell.hidePresenceWriteInFlight(_siteUrl), isTrue);
      expect(fixture.shell.currentInstance?.user?.hidePresence, isFalse);
      await pumpEventQueue();
      expect(api.presencePreferencesUpdated, [
        (siteUrl: _siteUrl, username: 'reader', hidePresence: true),
      ]);

      gate.complete();
      await write;
      await pumpEventQueue();

      expect(fixture.shell.hidePresenceFor(_siteUrl), isTrue);
      expect(fixture.shell.hidePresenceWriteInFlight(_siteUrl), isFalse);
      expect(fixture.shell.hidePresenceErrorFor(_siteUrl), isNull);
      expect(fixture.shell.currentInstance?.user?.hidePresence, isTrue);
      expect(
        (await fixture.store.load()).single.user?.hidePresence,
        isTrue,
        reason: 'only the confirmed choice becomes durable',
      );
    },
  );

  test('rolls back a refusal and gates a duplicate tap', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final api = FakeDiscourseApi(
      user: _user,
      presenceGate: gate,
      writeFailure: const WriteException(WriteFailure.unreachable),
      feeds: const {'/latest.json': <Topic>[]},
    );
    final fixture = await _shell(api: api);
    addTearDown(fixture.shell.dispose);
    final savesBeforeWrite = fixture.store.saveCount;

    final first = fixture.shell.toggleHidePresence(_siteUrl);
    await fixture.shell.toggleHidePresence(_siteUrl);
    await pumpEventQueue();

    expect(fixture.shell.hidePresenceFor(_siteUrl), isTrue);
    expect(api.presencePreferencesUpdated, hasLength(1));

    gate.complete();
    await first;
    await pumpEventQueue();

    expect(fixture.shell.hidePresenceFor(_siteUrl), isFalse);
    expect(fixture.shell.currentInstance?.user?.hidePresence, isFalse);
    expect(
      fixture.shell.hidePresenceErrorFor(_siteUrl),
      "Couldn't update presence. Check the connection and try again.",
    );
    expect(fixture.store.saveCount, savesBeforeWrite);
  });

  test('keeps preferences and errors isolated by site', () async {
    const otherUser = DiscourseUser(
      id: 8,
      username: 'teammate',
      hidePresence: true,
    );
    final api = FakeDiscourseApi(
      user: _user,
      feeds: const {'/latest.json': <Topic>[]},
    );
    final fixture = await _shell(
      api: api,
      instances: [
        _instance('meta.discourse.org', _user),
        _instance('team.discourse.org', otherUser),
      ],
    );
    addTearDown(fixture.shell.dispose);

    await fixture.shell.toggleHidePresence(_siteUrl);

    expect(fixture.shell.hidePresenceFor(_siteUrl), isTrue);
    expect(fixture.shell.hidePresenceFor(_otherSiteUrl), isTrue);
    expect(fixture.shell.hidePresenceErrorFor(_otherSiteUrl), isNull);
    expect(
      fixture.shell.instances
          .firstWhere((instance) => instance.url == _otherSiteUrl)
          .user,
      otherUser,
    );
    expect(api.presencePreferencesUpdated.single.siteUrl, _siteUrl);
  });

  test(
    'a session read started before the write cannot restore old state',
    () async {
      final api = _PendingCurrentUserApi();
      final fixture = await _shell(api: api, settle: false);
      addTearDown(fixture.shell.dispose);
      await api.started.future;

      await fixture.shell.toggleHidePresence(_siteUrl);
      api.response.complete(
        const DiscourseUser(
          id: 7,
          username: 'reader',
          name: 'Fresh account data',
          hidePresence: false,
        ),
      );
      await pumpEventQueue();

      expect(fixture.shell.currentInstance?.user?.name, 'Fresh account data');
      expect(fixture.shell.hidePresenceFor(_siteUrl), isTrue);
      expect(fixture.shell.currentInstance?.user?.hidePresence, isTrue);
    },
  );

  test('an old account write cannot reach a replacement account', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final api = FakeDiscourseApi(
      user: _user,
      presenceGate: gate,
      feeds: const {'/latest.json': <Topic>[]},
    );
    final fixture = await _shell(api: api);
    addTearDown(fixture.shell.dispose);

    final oldWrite = fixture.shell.toggleHidePresence(_siteUrl);
    await pumpEventQueue();
    expect(api.presencePreferencesUpdated, hasLength(1));

    expect(
      await fixture.shell.removeInstance(fixture.shell.currentInstance!),
      isTrue,
    );
    const replacement = DiscourseUser(
      id: 19,
      username: 'replacement',
      hidePresence: false,
    );
    fixture.auth.keys[_siteUrl] = 'replacement-key';
    expect(
      await fixture.shell.addInstance(
        _instance('meta.discourse.org', replacement),
      ),
      isTrue,
    );

    gate.complete();
    await oldWrite;
    await pumpEventQueue();

    expect(fixture.shell.currentInstance?.user, replacement);
    expect(fixture.shell.hidePresenceFor(_siteUrl), isFalse);
    expect(fixture.shell.hidePresenceWriteInFlight(_siteUrl), isFalse);
    expect(fixture.shell.hidePresenceErrorFor(_siteUrl), isNull);
  });

  test(
    'an unknown stored value can retry a failed current-user read',
    () async {
      final api = _RetryCurrentUserApi();
      final fixture = await _shell(
        api: api,
        user: const DiscourseUser(id: 7, username: 'reader'),
      );
      addTearDown(fixture.shell.dispose);

      expect(fixture.shell.hidePresenceFor(_siteUrl), isNull);
      expect(
        fixture.shell.hidePresenceErrorFor(_siteUrl),
        "Couldn't load the presence setting. Try again.",
      );

      await fixture.shell.retryHidePresence(_siteUrl);

      expect(api.currentUserCalls, 2);
      expect(fixture.shell.hidePresenceFor(_siteUrl), isFalse);
      expect(fixture.shell.hidePresenceErrorFor(_siteUrl), isNull);
    },
  );
}

final class _PendingCurrentUserApi extends FakeDiscourseApi {
  _PendingCurrentUserApi() : super(feeds: const {'/latest.json': <Topic>[]});

  final Completer<void> started = Completer<void>();
  final Completer<DiscourseUser> response = Completer<DiscourseUser>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}

final class _RetryCurrentUserApi extends FakeDiscourseApi {
  _RetryCurrentUserApi() : super(feeds: const {'/latest.json': <Topic>[]});

  int currentUserCalls = 0;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    currentUserCalls += 1;
    if (currentUserCalls == 1) {
      throw const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl);
    }
    return _user;
  }
}

typedef _ShellFixture = ({
  ShellController shell,
  FakeInstanceStore store,
  FakeAuthenticator auth,
});

Future<_ShellFixture> _shell({
  required FakeDiscourseApi api,
  DiscourseUser user = _user,
  List<DiscourseInstance>? instances,
  bool settle = true,
}) async {
  final store = FakeInstanceStore(
    instances ?? [_instance('meta.discourse.org', user)],
  );
  final auth = FakeAuthenticator()
    ..keys[_siteUrl] = 'meta-key'
    ..keys[_otherSiteUrl] = 'team-key';
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: store,
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  if (settle) await pumpEventQueue();
  return (shell: shell, store: store, auth: auth);
}

DiscourseInstance _instance(String host, DiscourseUser user) =>
    instance(host).copyWith(user: user);
