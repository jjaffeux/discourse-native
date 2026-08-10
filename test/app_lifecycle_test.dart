import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('replaces the controller when an injected dependency changes', (
    tester,
  ) async {
    final key = GlobalKey();
    final api = FakeDiscourseApi();
    final authenticator = FakeAuthenticator();
    final drafts = FakeDraftStore();
    final forumTabs = FakeForumTabStore();
    final updater = FakeUpdater();
    final updateStore = FakeUpdateStore();
    final trackers = FakeSiteTracker.reset();

    await tester.pumpWidget(
      DiscourseApp(
        key: key,
        store: FakeInstanceStore([instance('first.example')]),
        api: api,
        authenticator: authenticator,
        drafts: drafts,
        forumTabs: forumTabs,
        trackers: trackers,
        updater: updater,
        updateStore: updateStore,
      ),
    );
    await tester.pumpAndSettle();

    final firstController = _controller(tester);
    final firstTracker = FakeSiteTracker.built.single;
    expect(firstController.currentInstance?.host, 'first.example');

    await tester.pumpWidget(
      DiscourseApp(
        key: key,
        store: FakeInstanceStore([instance('second.example')]),
        api: api,
        authenticator: authenticator,
        drafts: drafts,
        forumTabs: forumTabs,
        trackers: trackers,
        updater: updater,
        updateStore: updateStore,
      ),
    );
    await tester.pumpAndSettle();

    final secondController = _controller(tester);
    expect(secondController, isNot(same(firstController)));
    expect(secondController.currentInstance?.host, 'second.example');
    expect(firstTracker.disposed, isTrue);
    expect(api.closeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(api.closeCalls, 1);
  });

  testWidgets('a replacement controller preserves the app lifecycle state', (
    tester,
  ) async {
    final key = GlobalKey();
    final longPollChecks = <bool Function()>[];
    final built = <FakeSiteTracker>[];
    SiteTracker trackers({
      required String siteUrl,
      required void Function() onIncomingTopics,
      required void Function(Object? data) onNotifications,
      required void Function(Object? data) onReviewableCounts,
      int? userId,
      String? apiKey,
      String? clientId,
      bool Function()? shouldLongPoll,
    }) {
      longPollChecks.add(shouldLongPoll!);
      final tracker = FakeSiteTracker(
        siteUrl: siteUrl,
        onIncomingTopics: onIncomingTopics,
        onNotifications: onNotifications,
        onReviewableCounts: onReviewableCounts,
        userId: userId,
        apiKey: apiKey,
      );
      built.add(tracker);
      return tracker;
    }

    final api = FakeDiscourseApi();
    final authenticator = FakeAuthenticator();
    final drafts = FakeDraftStore();
    final forumTabs = FakeForumTabStore();
    final updater = FakeUpdater();
    final updateStore = FakeUpdateStore();

    Widget app(InstanceStore store) => DiscourseApp(
      key: key,
      store: store,
      api: api,
      authenticator: authenticator,
      drafts: drafts,
      forumTabs: forumTabs,
      trackers: trackers,
      updater: updater,
      updateStore: updateStore,
    );

    await tester.pumpWidget(
      app(FakeInstanceStore([instance('first.example')])),
    );
    await tester.pumpAndSettle();
    final firstController = _controller(tester);
    final lifecycleObserver =
        tester.state(find.byType(DiscourseApp)) as WidgetsBindingObserver;
    expect(longPollChecks.single(), isTrue);

    lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(built.first.polling, isFalse);

    await tester.pumpWidget(
      app(FakeInstanceStore([instance('second.example')])),
    );
    await tester.pumpAndSettle();

    expect(_controller(tester), isNot(same(firstController)));
    // A controller created while the process is paused does not spend any
    // credentials or create a poller until the process becomes visible.
    expect(built, hasLength(1));
    expect(built.first.disposed, isTrue);

    lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(built, hasLength(2));
    expect(longPollChecks, hasLength(2));
    expect(longPollChecks.last(), isTrue);
    expect(built.last.polling, isTrue);
  });

  testWidgets('closes each API when the app releases it', (tester) async {
    final key = GlobalKey();
    final store = FakeInstanceStore();
    final authenticator = FakeAuthenticator();
    final drafts = FakeDraftStore();
    final forumTabs = FakeForumTabStore();
    final trackers = FakeSiteTracker.reset();
    final updater = FakeUpdater();
    final updateStore = FakeUpdateStore();
    final firstApi = FakeDiscourseApi();
    final secondApi = FakeDiscourseApi();

    Widget app(FakeDiscourseApi api) => DiscourseApp(
      key: key,
      store: store,
      api: api,
      authenticator: authenticator,
      drafts: drafts,
      forumTabs: forumTabs,
      trackers: trackers,
      updater: updater,
      updateStore: updateStore,
    );

    await tester.pumpWidget(app(firstApi));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(secondApi));
    await tester.pumpAndSettle();

    expect(firstApi.closeCalls, 1);
    expect(secondApi.closeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(firstApi.closeCalls, 1);
    expect(secondApi.closeCalls, 1);
  });

  test(
    'backgrounding while tracker credentials resolve starts no poll',
    () async {
      const siteUrl = 'https://first.example';
      const user = DiscourseUser(id: 7, username: 'reader');
      final api = FakeDiscourseApi(user: user);
      final authenticator = _GatedAuthenticator(siteUrl)
        ..keys[siteUrl] = 'first-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('first.example').copyWith(user: user),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await authenticator.started.future;

      shell.setForeground(false);
      authenticator.release();
      await pumpEventQueue();

      expect(
        FakeSiteTracker.built,
        isEmpty,
        reason:
            'a hidden app must not construct a tracker that starts one poll',
      );

      shell.setForeground(true);
      await pumpEventQueue();

      expect(FakeSiteTracker.built, hasLength(1));
      expect(FakeSiteTracker.built.single.siteUrl, siteUrl);
      expect(FakeSiteTracker.built.single.polling, isTrue);
    },
  );

  test(
    'switching sites while tracker credentials resolve starts only selected poll',
    () async {
      const firstUrl = 'https://first.example';
      const secondUrl = 'https://second.example';
      const user = DiscourseUser(id: 7, username: 'reader');
      final api = FakeDiscourseApi(user: user);
      final authenticator = _GatedAuthenticator(firstUrl)
        ..keys[firstUrl] = 'first-key'
        ..keys[secondUrl] = 'second-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('first.example').copyWith(user: user),
          instance('second.example').copyWith(user: user),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await authenticator.started.future;

      shell.selectInstance(1);
      await pumpEventQueue();
      expect(FakeSiteTracker.built.map((tracker) => tracker.siteUrl), [
        secondUrl,
      ]);

      authenticator.release();
      await pumpEventQueue();

      expect(
        FakeSiteTracker.built.map((tracker) => tracker.siteUrl),
        [secondUrl],
        reason: 'the deselected pending site must not spend a poll',
      );

      shell.selectInstance(0);
      await pumpEventQueue();

      expect(
        FakeSiteTracker.built.map((tracker) => tracker.siteUrl),
        [secondUrl, firstUrl],
        reason: 'deselection must leave tracker startup retryable on reselect',
      );
      expect(FakeSiteTracker.built.first.polling, isFalse);
      expect(FakeSiteTracker.built.last.polling, isTrue);
    },
  );

  test('a disposed controller ignores a pending initial load', () async {
    final gate = Completer<List<DiscourseInstance>>();
    final trackers = FakeSiteTracker.reset();
    final controller = ShellController(
      instanceStore: _GatedInstanceStore(gate.future),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: trackers,
      updateStore: FakeUpdateStore(),
    );

    final load = controller.load();
    controller.dispose();
    gate.complete([instance('late.example')]);
    await load;
    await Future<void>.delayed(Duration.zero);

    expect(controller.loaded, isFalse);
    expect(controller.instances, isEmpty);
    expect(FakeSiteTracker.built, isEmpty);
  });

  test('disposing invalidates an in-flight feed write', () async {
    final gate = Completer<void>();
    const topic = Topic(id: 7, title: 'Late topic', slug: 'late-topic');
    final api = FakeDiscourseApi(
      feeds: const {
        '/latest.json': [topic],
      },
      gate: gate,
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([instance('late.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );

    await controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(api.feedPaths, ['/latest.json']);

    controller.dispose();
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.store.read<Topic>('https://late.example', 7), isNull);
  });
}

ShellController _controller(WidgetTester tester) =>
    tester.widget<ShellScope>(find.byType(ShellScope)).notifier!;

final class _GatedInstanceStore implements InstanceStore {
  const _GatedInstanceStore(this.result);

  final Future<List<DiscourseInstance>> result;

  @override
  Future<List<DiscourseInstance>> load() => result;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {}
}

final class _GatedAuthenticator extends FakeAuthenticator {
  _GatedAuthenticator(this.gatedSiteUrl);

  final String gatedSiteUrl;
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (siteUrl != gatedSiteUrl) return super.apiKeyFor(siteUrl);
    if (!started.isCompleted) started.complete();
    await _release.future;
    return super.apiKeyFor(siteUrl);
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }
}
