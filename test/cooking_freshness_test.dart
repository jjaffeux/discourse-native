import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/application_cooking.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://a.test';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'application epochs reject prepared work after metadata and reconnect',
    () async {
      final plugins = PluginInstaller.install(const PluginManifest([]));
      final app = ApplicationCooking(plugins: plugins, service: _Service());
      addTearDown(app.dispose);
      addTearDown(plugins.close);
      CookingRequest request() => app.request(
        siteUrl: _site,
        accountId: '7',
        raw: 'hello',
        config: const SiteConfig(),
        context: const CookingContext(asOfEpochMilliseconds: 123),
      );
      final first = request();
      expect(app.isCurrent(first), isTrue);
      expect(app.isCurrent(CookingRequest.fromJson(first.toJson())), isFalse);
      final lease = app.captureUploads(_site, '7');
      app.ingestMetadata(
        lease,
        CookingCachedMetadata(oneboxes: {'hello': 'card'}),
      );
      expect(app.isCurrent(first), isFalse);
      final second = request();
      expect(second.snapshot.context.asOfEpochMilliseconds, 123);
      app.ingestUploads(lease, {
        'upload://a': {'url': '/a.png'},
      });
      expect(app.isCurrent(second), isFalse);
      final beforeReconnect = request();
      app.forget(_site);
      expect(app.ingestMetadata(lease, CookingCachedMetadata()), isFalse);
      expect(app.isCurrent(beforeReconnect), isFalse);
      expect(app.isCurrent(request()), isTrue);
      expect(app.isCurrent(beforeReconnect), isFalse);
    },
  );

  test(
    'application observations are deferred, coalesced and cancellable',
    () async {
      final plugins = PluginInstaller.install(const PluginManifest([]));
      final app = ApplicationCooking(plugins: plugins, service: _Service());
      addTearDown(app.dispose);
      addTearDown(plugins.close);
      var calls = 0;
      app.contextChanged(_site);
      final stop = app.watchContext(_site, () => calls++);
      await pumpEventQueue();
      expect(calls, 0, reason: 'subscribing never replays a pending change');
      app.contextChanged('https://other.test');
      app.contextChanged(_site);
      app.contextChanged(_site);
      expect(calls, 0);
      await pumpEventQueue();
      expect(calls, 1);
      app.contextChanged(_site);
      stop();
      stop();
      await pumpEventQueue();
      expect(calls, 1);
      app.watchContext(_site, () => calls++);
      app.contextChanged(_site);
      await app.dispose();
      await pumpEventQueue();
      expect(calls, 1);
    },
  );

  test(
    'shell observes only selected entity refs and keeps frozen identity',
    () async {
      final shell = _shell();
      final request = shell.cookingRequest(
        siteUrl: _site,
        raw: '@Alice [quote="Bob, topic:12"]body[/quote]',
        context: const CookingContext(asOfEpochMilliseconds: 456),
      );
      var calls = 0;
      final stop = shell.watchCooking(
        siteUrl: _site,
        raw: request.raw,
        onChanged: () => calls++,
      );
      expect(shell.cookingRequestIsCurrent(request), isTrue);
      shell.store.put(_site, const UserCard(username: 'unrelated'));
      await pumpEventQueue();
      expect(calls, 0);
      shell.store.put(
        _site,
        const UserCard(username: 'Alice', avatarUrl: '/a.png'),
      );
      expect(calls, 0);
      expect(shell.cookingRequestIsCurrent(request), isFalse);
      await pumpEventQueue();
      expect(calls, 1);
      final next = shell.cookingRequest(
        siteUrl: _site,
        raw: request.raw,
        context: request.snapshot.context,
      );
      expect(next.snapshot.context.asOfEpochMilliseconds, 456);
      shell.store.put(
        _site,
        const TopicDetail(id: 12, title: 'New title', stream: []),
      );
      expect(shell.cookingRequestIsCurrent(next), isFalse);
      await pumpEventQueue();
      expect(calls, 2);
      shell.store.put(
        _site,
        const UserCard(username: 'Alice', avatarUrl: '/b.png'),
      );
      stop();
      await pumpEventQueue();
      expect(calls, 2);
    },
  );

  test(
    'settings and same-account identity changes invalidate without new raw',
    () async {
      final shell = _shell(
        instances: [
          const DiscourseInstance(url: _site, title: 'A', loginRequired: true),
        ],
      );
      await shell.load();
      await pumpEventQueue();
      var calls = 0;
      final stop = shell.watchCooking(
        siteUrl: _site,
        raw: 'hello',
        onChanged: () => calls++,
      );
      addTearDown(stop);
      CookingRequest request() =>
          shell.cookingRequest(siteUrl: _site, raw: 'hello');
      void replace({DiscourseUser? user, SiteConfig? config}) {
        final held = shell.accountSessionInstance(_site)!;
        shell.applyAccountSessionInstance(
          held.copyWith(user: user, config: config),
          AccountSessionPhase.connecting,
        );
      }

      final first = request();
      replace(config: SiteConfig.fromSettings(const {'enable_emoji': false}));
      expect(shell.cookingRequestIsCurrent(first), isFalse);
      await pumpEventQueue();
      expect(calls, 1);
      final second = request();
      replace(
        config: shell
            .siteConfigFor(_site)
            .withPlugins(
              PluginData.none.withValue(
                localDatesSettingsDataKey,
                const LocalDatesSettings(enabled: true),
              ),
            ),
      );
      expect(shell.cookingRequestIsCurrent(second), isFalse);
      replace(
        user: const DiscourseUser(
          id: 7,
          username: 'Alice',
          timezone: 'Etc/UTC',
        ),
      );
      await pumpEventQueue();
      final third = request();
      replace(
        user: const DiscourseUser(
          id: 7,
          username: 'Alice',
          timezone: 'Europe/Paris',
        ),
      );
      expect(shell.cookingRequestIsCurrent(third), isFalse);
      await pumpEventQueue();
      final fourth = request();
      replace(
        user: const DiscourseUser(
          id: 7,
          username: 'Renamed',
          timezone: 'Europe/Paris',
        ),
      );
      expect(shell.cookingRequestIsCurrent(fourth), isFalse);
      await pumpEventQueue();
      expect(shell.cookingRequestIsCurrent(request()), isTrue);
    },
  );

  test(
    'site presentation and ingested caches notify without shell rebuild listeners',
    () async {
      final config = SiteConfig.fromSettings(const {'enable_emoji': false});
      final shell = _shell(
        api: FakeDiscourseApi(
          siteConfigs: {_site: config, 'https://b.test': config},
        ),
      );
      final first = shell.cookingRequest(siteUrl: _site, raw: 'hello');
      var calls = 0;
      final stop = shell.watchCooking(
        siteUrl: _site,
        raw: first.raw,
        onChanged: () => calls++,
      );
      addTearDown(stop);
      await shell.resolveSiteConfig('https://b.test');
      await pumpEventQueue();
      expect(calls, 0);
      await shell.resolveSiteConfig(_site);
      await pumpEventQueue();
      expect(calls, 1);
      expect(shell.cookingRequestIsCurrent(first), isFalse);
      final next = shell.cookingRequest(siteUrl: _site, raw: 'hello');
      shell.cooking.ingestMetadata(
        shell.cooking.captureUploads(_site, 'anonymous'),
        CookingCachedMetadata(oneboxes: {'hello': 'card'}),
      );
      expect(shell.cookingRequestIsCurrent(next), isFalse);
      await pumpEventQueue();
      expect(calls, 2);
      shell.cooking.forget(_site);
      shell.dispose();
      await pumpEventQueue();
      expect(calls, 2, reason: 'disposal cancels queued callbacks');
    },
  );

  test(
    'custom emoji arrival invalidates a prepared unchanged source',
    () async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        siteConfigs: {_site: const SiteConfig()},
        customEmojisBySite: {
          _site: {'custom': 'https://a.test/custom.png'},
        },
        customEmojiGate: gate,
      );
      final shell = _shell(
        api: api,
        instances: [const DiscourseInstance(url: _site, title: 'A')],
      );
      await shell.load();
      await pumpEventQueue();
      expect(api.customEmojisRequired, contains(_site));
      final request = shell.cookingRequest(siteUrl: _site, raw: ':custom:');
      expect(request.snapshot.customEmoji, isEmpty);
      var calls = 0;
      final stop = shell.watchCooking(
        siteUrl: _site,
        raw: request.raw,
        onChanged: () => calls++,
      );
      addTearDown(stop);
      gate.complete();
      await pumpEventQueue();
      expect(shell.cookingRequestIsCurrent(request), isFalse);
      expect(calls, 1);
      expect(
        shell
            .cookingRequest(siteUrl: _site, raw: request.raw)
            .snapshot
            .customEmoji,
        contains('custom'),
      );
    },
  );

  test('device timezone fallback changes invalidate and notify', () async {
    final environment = TimezoneEnvironment.instance;
    final previous = environment.deviceTimezone;
    addTearDown(() => environment.setDeviceTimezone(previous));
    environment.setDeviceTimezone('Etc/UTC');
    final shell = _shell();
    final request = shell.cookingRequest(siteUrl: _site, raw: 'hello');
    var calls = 0;
    final stop = shell.watchCooking(
      siteUrl: _site,
      raw: 'hello',
      onChanged: () => calls++,
    );
    addTearDown(stop);
    environment.setDeviceTimezone('Europe/Paris');
    expect(shell.cookingRequestIsCurrent(request), isFalse);
    expect(calls, 0);
    await pumpEventQueue();
    expect(calls, 1);
  });
}

ShellController _shell({
  FakeDiscourseApi? api,
  List<DiscourseInstance> instances = const [],
}) {
  final plugins = PluginInstaller.install(const PluginManifest([]));
  final shell = ShellController(
    instanceStore: FakeInstanceStore(instances),
    api: api ?? FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
    plugins: plugins,
    cookingService: _Service(),
  );
  addTearDown(() async {
    // The disposal regression closes the shell before the shared teardown.
    // ignore: invalid_use_of_protected_member
    if (!shell.isDisposed) shell.dispose();
    await shell.cooking.dispose();
    await plugins.close();
  });
  return shell;
}

final class _Service implements CookingServicePort {
  @override
  Future<bool> start() async => true;
  @override
  Future<CookingResult> cook(CookingRequest request) async =>
      CookingResult(html: request.raw).forRequest(request);
  @override
  void invalidate() {}
  @override
  Future<void> dispose() async {}
}
