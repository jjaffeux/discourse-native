import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
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

    await tester.pumpWidget(
      app(FakeInstanceStore([instance('second.example')])),
    );
    await tester.pumpAndSettle();

    expect(_controller(tester), isNot(same(firstController)));
    expect(built, hasLength(2));
    expect(built.first.disposed, isTrue);
    expect(longPollChecks, hasLength(2));
    expect(longPollChecks.last(), isFalse);

    lifecycleObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(longPollChecks.last(), isTrue);
    expect(built.last.pollNowCalls, 1);
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
