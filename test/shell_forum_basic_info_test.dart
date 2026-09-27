import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/site_basic_info.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_text_scale.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

final class _PendingBasicInfo {
  _PendingBasicInfo(this.siteUrl);

  final String siteUrl;
  final Completer<SiteBasicInfo> response = Completer<SiteBasicInfo>();
}

/// Holds every basic-info read until the test answers it, in any order.
final class _HeldBasicInfoApi extends FakeDiscourseApi {
  final List<_PendingBasicInfo> reads = [];

  @override
  Future<SiteBasicInfo> basicInfo(String siteUrl) {
    basicInfoRequested.add(siteUrl);
    final read = _PendingBasicInfo(siteUrl);
    reads.add(read);
    return read.response.future;
  }
}

ShellController _shell(
  FakeInstanceStore store,
  FakeDiscourseApi api, {
  FakeAuthenticator? authenticator,
}) {
  final shell = ShellController(
    instanceStore: store,
    api: api,
    authenticator: authenticator ?? FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  return shell;
}

const _welcome = [Topic(id: 7, title: 'Welcome inside', slug: 'welcome')];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a stored public forum that became private puts up sign-in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = FakeInstanceStore([
      instance('meta.discourse.org', title: 'Meta'),
    ]);
    final gate = Completer<void>();
    final api = FakeDiscourseApi(
      basicInfos: {
        _siteUrl: const SiteBasicInfo(title: 'Meta', loginRequired: true),
      },
      basicInfoGate: gate,
      feeds: const {'/latest.json': _welcome},
    );
    final shell = _shell(store, api);
    await shell.load();
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) =>
              AppTextScaleRegion(controller: shell.appSettings, child: child!),
          home: const AdaptiveShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.basicInfoRequested, [_siteUrl]);
    expect(find.byKey(const ValueKey('private-forum-gate')), findsNothing);
    expect(find.byType(MainContent), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('private-forum-gate')), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.byType(MainContent), findsNothing);
    expect(shell.currentInstance!.loginRequired, isTrue);
    expect(shell.search.siteUrl, isNull);
    expect((await store.load()).single.loginRequired, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  group('basic info refresh', () {
    test('a renamed forum is redrawn and stored as it reads now', () async {
      final store = FakeInstanceStore([
        const DiscourseInstance(
          url: _siteUrl,
          title: 'Old name',
          description: 'Old description',
          iconUrl: '$_siteUrl/uploads/old-icon.png',
          apiVersion: 4,
        ),
      ]);
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        basicInfos: {
          _siteUrl: const SiteBasicInfo(
            title: 'New name',
            iconUrl: '$_siteUrl/uploads/new-icon.png',
          ),
        },
        basicInfoGate: gate,
      );
      final shell = _shell(store, api);
      await shell.load();
      await pumpEventQueue();
      final stale = shell.currentInstance!;
      expect(stale.title, 'Old name');
      var notifications = 0;
      shell.addListener(() => notifications++);

      gate.complete();
      await pumpEventQueue();

      final refreshed = shell.currentInstance!;
      expect(refreshed, isNot(same(stale)));
      expect(refreshed.title, 'New name');
      expect(refreshed.iconUrl, '$_siteUrl/uploads/new-icon.png');
      expect(refreshed.description, isNull);
      expect(refreshed.apiVersion, 4);
      expect(notifications, 1);
      final stored = (await store.load()).single;
      expect(stored.title, 'New name');
      expect(stored.iconUrl, '$_siteUrl/uploads/new-icon.png');
      expect(stored.description, isNull);
    });

    test('a forum stored before its privacy was recorded learns it', () async {
      // Entries written before `loginRequired` was stored read as public.
      final legacy = DiscourseInstance.fromJson(const {
        'url': _siteUrl,
        'title': 'Meta',
        'apiVersion': 4,
      });
      expect(legacy.loginRequired, isFalse);
      final store = FakeInstanceStore([legacy]);
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        basicInfos: {
          _siteUrl: const SiteBasicInfo(title: 'Meta', loginRequired: true),
        },
        basicInfoGate: gate,
      );
      final shell = _shell(store, api);

      await shell.load();
      await pumpEventQueue();
      final tracker = FakeSiteTracker.built.single;
      expect(tracker.polling, isTrue);
      expect(shell.search.siteUrl, _siteUrl);

      gate.complete();
      await pumpEventQueue();

      expect(shell.currentInstance!.loginRequired, isTrue);
      expect(shell.search.siteUrl, isNull);
      expect(
        tracker.polling,
        isFalse,
        reason: 'a private forum refuses every anonymous poll',
      );
      expect((await store.load()).single.loginRequired, isTrue);
    });

    test('a private forum that became public loads what it hid', () async {
      final store = FakeInstanceStore([
        instance(
          'meta.discourse.org',
          title: 'Meta',
        ).copyWith(loginRequired: true),
      ]);
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        basicInfos: {_siteUrl: const SiteBasicInfo(title: 'Meta')},
        basicInfoGate: gate,
        feeds: const {'/latest.json': _welcome},
      );
      final shell = _shell(store, api);

      await shell.load();
      await pumpEventQueue();
      expect(api.feedPaths, isEmpty);
      expect(shell.search.siteUrl, isNull);

      gate.complete();
      await pumpEventQueue();

      expect(shell.currentInstance!.loginRequired, isFalse);
      expect(api.feedPaths, contains('/latest.json'));
      expect(shell.search.siteUrl, _siteUrl);
      expect((await store.load()).single.loginRequired, isFalse);
      expect(api.basicInfoRequested, [
        _siteUrl,
      ], reason: 'activating the forum again does not read it again');
    });

    test('an unchanged or unreadable forum keeps what was stored', () async {
      final unchanged = instance('meta.discourse.org', title: 'Meta');
      final unreadable = instance('other.example', title: 'Other');
      final store = FakeInstanceStore([unchanged, unreadable]);
      final api = FakeDiscourseApi(
        basicInfos: {_siteUrl: const SiteBasicInfo(title: 'Meta')},
      );
      final shell = _shell(store, api);

      await shell.load();
      await pumpEventQueue();
      shell.selectInstance(1);
      await pumpEventQueue();

      expect(api.basicInfoRequested, [_siteUrl, 'https://other.example']);
      expect(shell.instances.first, same(unchanged));
      expect(shell.instances.last, same(unreadable));
      expect(store.saveCount, 0);
    });

    test('a read that lands after a remove and re-add is dropped', () async {
      final store = FakeInstanceStore([
        instance('meta.discourse.org', title: 'Meta'),
        instance('other.example', title: 'Other'),
      ]);
      final api = _HeldBasicInfoApi();
      final shell = _shell(store, api);
      await shell.load();
      await pumpEventQueue();
      expect(api.reads.map((read) => read.siteUrl), [_siteUrl]);

      expect(await shell.removeInstance(shell.instances.first), isTrue);
      await pumpEventQueue();
      final readsBeforeReadd = api.reads.length;
      final readded = instance('meta.discourse.org', title: 'Meta, again');
      expect(await shell.addInstance(readded), isTrue);
      await pumpEventQueue();
      expect(
        api.reads,
        hasLength(readsBeforeReadd),
        reason: 'the lookup that re-added the forum has just read it',
      );

      for (final read in api.reads.where((read) => read.siteUrl == _siteUrl)) {
        read.response.complete(
          const SiteBasicInfo(title: 'Stale', loginRequired: true),
        );
      }
      await pumpEventQueue();

      final held = shell.instances.singleWhere((item) => item.url == _siteUrl);
      expect(held, same(readded));
      final stored = (await store.load()).singleWhere(
        (item) => item.url == _siteUrl,
      );
      expect(stored.title, 'Meta, again');
      expect(stored.loginRequired, isFalse);
    });

    test(
      'a read an account change overtook cannot undo the newer one',
      () async {
        final store = FakeInstanceStore([
          instance('meta.discourse.org', title: 'Meta'),
        ]);
        final api = _HeldBasicInfoApi();
        final authenticator = FakeAuthenticator();
        final shell = _shell(store, api, authenticator: authenticator);
        await shell.load();
        await pumpEventQueue();
        expect(api.reads, hasLength(1));

        await shell.connectCurrentInstance();
        await pumpEventQueue();
        expect(shell.currentInstance!.isConnected, isTrue);
        expect(
          api.reads,
          hasLength(2),
          reason:
              'the account change discarded the first read, so it reads again',
        );

        api.reads.last.response.complete(
          const SiteBasicInfo(title: 'Newer name'),
        );
        await pumpEventQueue();
        expect(shell.currentInstance!.title, 'Newer name');

        api.reads.first.response.complete(
          const SiteBasicInfo(title: 'Older name', loginRequired: true),
        );
        await pumpEventQueue();

        expect(shell.currentInstance!.title, 'Newer name');
        expect(shell.currentInstance!.loginRequired, isFalse);
        expect(shell.currentInstance!.isConnected, isTrue);
        final stored = (await store.load()).single;
        expect(stored.title, 'Newer name');
        expect(stored.loginRequired, isFalse);
      },
    );
  });
}
