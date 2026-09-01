import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mounting the shell starts optional preference reads that nothing awaits:
  // the sidebar and diagnostics panel widths, the sidebar sections, and the
  // Voice device selection. Without an in-memory store they cross the real
  // platform channel, whose reply arrives whenever the host process gets to
  // it. Under full-suite load that is after the widget tests' fake clock has
  // stopped, so the awaits holding those stores' catch blocks never resume and
  // the channel's MissingPluginException is reported as an unhandled error
  // against a test that has already completed.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('failed loads are coalesced and a later attempt can recover', () async {
    final first = Completer<List<DiscourseInstance>>();
    final second = Completer<List<DiscourseInstance>>();
    final store = _SequencedInstanceStore([first.future, second.future]);
    final controller = _controller(store);
    addTearDown(controller.dispose);

    final statuses = <InstanceLoadStatus>[];
    Future<void>? listenerRetry;
    controller.addListener(() {
      final status = controller.loadStatus;
      if (statuses.isEmpty || statuses.last != status) statuses.add(status);
      if (status == InstanceLoadStatus.loading) {
        listenerRetry ??= controller.load();
      }
    });

    final load = controller.load();
    expect(controller.load(), same(load));
    expect(store.loadCount, 1);

    first.completeError(StateError('preferences unavailable'));
    await load;

    expect(controller.loadStatus, InstanceLoadStatus.failed);
    expect(controller.loaded, isFalse);
    expect(controller.instances, isEmpty);

    final retry = controller.load();
    expect(controller.loadStatus, InstanceLoadStatus.loading);
    expect(listenerRetry, same(retry));
    expect(controller.load(), same(retry));
    expect(store.loadCount, 2);

    final stored = instance('saved.example', title: 'Saved site');
    second.complete([stored]);
    await retry;

    expect(controller.loadStatus, InstanceLoadStatus.ready);
    expect(controller.instances, [stored]);
    await controller.load();
    expect(store.loadCount, 2);
    expect(statuses.where((status) => status != InstanceLoadStatus.loading), [
      InstanceLoadStatus.failed,
      InstanceLoadStatus.ready,
    ]);
  });

  test(
    'adding cannot overwrite sites while their snapshot is unknown',
    () async {
      final stored = instance('saved.example');
      final added = instance('new.example');
      final first = Completer<List<DiscourseInstance>>();
      final second = Completer<List<DiscourseInstance>>();
      final store = _SequencedInstanceStore([first.future, second.future]);
      final controller = _controller(store);
      addTearDown(controller.dispose);

      final failedAdd = controller.addInstance(added);
      first.completeError(StateError('preferences unavailable'));
      expect(await failedAdd, isFalse);
      expect(controller.loadStatus, InstanceLoadStatus.failed);
      expect(controller.instances, isEmpty);
      expect(store.saved, isEmpty);

      final recoveredAdd = controller.addInstance(added);
      second.complete([stored]);
      expect(await recoveredAdd, isTrue);
      expect(controller.instances, [stored, added]);
      expect(store.saved, [stored, added]);
    },
  );

  test(
    'a failed first save rolls the site back and remains retryable',
    () async {
      final stored = instance('saved.example');
      final added = instance('new.example');
      final store = _FailingFirstSaveStore(stored);
      final controller = _controller(store);
      addTearDown(controller.dispose);

      await controller.load();
      final previousDestination = controller.destinationId;
      final previousContent = controller.currentContent;

      expect(await controller.addInstance(added), isFalse);
      expect(controller.instances, [stored]);
      expect(controller.currentInstance, stored);
      expect(controller.destinationId, previousDestination);
      expect(controller.currentContent, previousContent);
      expect(store.saved, [stored]);
      expect(store.saveCount, 2);

      expect(await controller.addInstance(added), isTrue);
      expect(controller.instances, [stored, added]);
      expect(controller.currentInstance, added);
      expect(store.saved, [stored, added]);
    },
  );

  test('a failed removal save restores a signed-out retryable site', () async {
    const user = DiscourseUser(username: 'sam', id: 7);
    final stored = instance('saved.example').copyWith(user: user);
    final store = _FailingFirstSaveStore(stored, failureCalls: {2});
    final controller = _controller(store);
    addTearDown(controller.dispose);

    await controller.load();

    expect(await controller.removeInstance(stored), isFalse);
    expect(controller.instances, hasLength(1));
    expect(controller.currentInstance?.url, stored.url);
    expect(controller.currentInstance?.user, isNull);
    expect(store.saved, hasLength(1));
    expect(store.saved.single.url, stored.url);
    expect(store.saved.single.user, isNull);
    expect(store.saveCount, 3);

    expect(
      await controller.removeInstance(controller.instances.single),
      isTrue,
    );
    expect(controller.instances, isEmpty);
    expect(store.saved, isEmpty);
    expect(store.saveCount, 5);
  });

  test('disconnect retries a transient signed-out snapshot failure', () async {
    const user = DiscourseUser(username: 'sam', id: 7);
    final stored = instance('saved.example').copyWith(user: user);
    final store = _FailingFirstSaveStore(stored);
    final controller = _controller(store);
    addTearDown(controller.dispose);

    await controller.load();

    expect(await controller.disconnectInstance(stored.url), isTrue);
    expect(controller.currentInstance?.user, isNull);
    expect(store.saveCount, 2);
    expect(store.saved, hasLength(1));
    expect(store.saved.single.url, stored.url);
    expect(store.saved.single.user, isNull);
  });

  for (final layout in [
    (name: 'compact', size: const Size(390, 844)),
    (name: 'wide', size: const Size(1000, 800)),
  ]) {
    testWidgets(
      '${layout.name} shell and rail recover through retry controls',
      (tester) async {
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final first = Completer<List<DiscourseInstance>>();
        final retry = Completer<List<DiscourseInstance>>();
        final store = _SequencedInstanceStore([first.future, retry.future]);

        await tester.pumpWidget(
          DiscourseApp(
            store: store,
            api: FakeDiscourseApi(),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: FakeForumTabStore(),
            trackers: FakeSiteTracker.reset(),
            updater: FakeUpdater(),
            updateStore: FakeUpdateStore(),
            initialRootMode: ShellRootMode.forum,
          ),
        );
        expect(store.loadCount, 1);

        first.completeError(StateError('preferences unavailable'));
        await tester.pumpAndSettle();

        expect(find.text("Couldn't load your sites"), findsOneWidget);
        expect(
          find.byKey(const ValueKey('instance-load-retry-panel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('instance-load-retry-rail')),
          findsOneWidget,
        );
        expect(find.text('No sites yet'), findsNothing);
        expect(find.byTooltip('Add a Discourse site'), findsNothing);
        expect(store.saved, isEmpty);

        await tester.tap(
          find.byKey(const ValueKey('instance-load-retry-panel')),
        );
        await tester.tap(
          find.byKey(const ValueKey('instance-load-retry-rail')),
        );
        expect(store.loadCount, 2);

        await tester.pump();
        final shell = tester
            .widget<ShellScope>(find.byType(ShellScope))
            .notifier!;
        expect(shell.loadStatus, InstanceLoadStatus.loading);
        expect(
          find.byKey(const ValueKey('instance-load-retry-rail')),
          findsNothing,
        );

        retry.complete([instance('saved.example', title: 'Saved site')]);
        await tester.pumpAndSettle();

        expect(shell.loadStatus, InstanceLoadStatus.ready);
        expect(find.text('Saved site'), findsOneWidget);
        expect(store.saved, isEmpty);
      },
    );
  }
}

ShellController _controller(InstanceStore store) => ShellController(
  instanceStore: store,
  api: FakeDiscourseApi(),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
  updateStore: FakeUpdateStore(),
);

final class _SequencedInstanceStore implements InstanceStore {
  _SequencedInstanceStore(Iterable<Future<List<DiscourseInstance>>> loads)
    : _loads = Queue.of(loads);

  final Queue<Future<List<DiscourseInstance>>> _loads;
  int loadCount = 0;
  List<DiscourseInstance> saved = const [];

  @override
  Future<List<DiscourseInstance>> load() {
    loadCount++;
    return _loads.removeFirst();
  }

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    saved = List.of(instances);
  }
}

final class _FailingFirstSaveStore implements InstanceStore {
  _FailingFirstSaveStore(this.stored, {this.failureCalls = const {1}});

  final DiscourseInstance stored;
  final Set<int> failureCalls;
  int saveCount = 0;
  List<DiscourseInstance> saved = const [];

  @override
  Future<List<DiscourseInstance>> load() async => [stored];

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    saveCount++;
    if (failureCalls.contains(saveCount)) {
      throw StateError('preferences unavailable');
    }
    saved = List.of(instances);
  }
}
