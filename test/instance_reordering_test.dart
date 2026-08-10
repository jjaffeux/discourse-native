import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sites = [
    instance('one.example', title: 'One'),
    instance('two.example', title: 'Two'),
    instance('three.example', title: 'Three'),
  ];

  test(
    'moving a site persists its order without changing navigation',
    () async {
      final store = FakeInstanceStore(sites);
      final controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.load();

      controller.selectInstance(1);
      controller.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'kept', title: 'Kept route'),
      );
      final workspace = controller.currentWorkspace;
      final content = controller.currentContent;
      final pane = controller.mobilePane;

      expect(await controller.moveInstance(sites.first, 2), isTrue);

      expect(_urls(controller.instances), [
        sites[1].url,
        sites[2].url,
        sites[0].url,
      ]);
      expect(controller.currentInstance?.url, sites[1].url);
      expect(controller.instanceIndex, 0);
      expect(controller.currentWorkspace, same(workspace));
      expect(controller.currentContent, same(content));
      expect(controller.mobilePane, pane);
      expect(_urls(await store.load()), _urls(controller.instances));
      expect(store.saveCount, 1);

      expect(await controller.moveInstance(sites.first, 2), isTrue);
      expect(store.saveCount, 1, reason: 'a no-op does not need another write');
    },
  );

  test('a new controller restores the saved order', () async {
    final store = FakeInstanceStore(sites);
    final first = _controller(store);
    addTearDown(first.dispose);
    await first.load();

    expect(await first.moveInstance(sites.last, 0), isTrue);

    final restarted = _controller(store);
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(_urls(restarted.instances), [
      sites[2].url,
      sites[0].url,
      sites[1].url,
    ]);
    expect(restarted.currentInstance?.url, sites[2].url);
  });

  test(
    'a failed save rolls back order but keeps the latest selection',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final store = _ControlledInstanceStore(
        sites,
        steps: [
          _SaveStep(gate: gate, started: started, fails: true),
          const _SaveStep(),
        ],
      );
      final controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.load();

      final moving = controller.moveInstance(sites.first, 2);
      await started.future;
      expect(_urls(controller.instances), [
        sites[1].url,
        sites[2].url,
        sites[0].url,
      ]);

      controller.selectInstance(0);
      gate.complete();

      expect(await moving, isFalse);
      expect(_urls(controller.instances), _urls(sites));
      expect(controller.currentInstance?.url, sites[1].url);
      expect(controller.instanceIndex, 1);
      expect(_urls(store.saved), _urls(sites));
      expect(store.saveCount, 2, reason: 'the rollback is repaired on disk');
    },
  );

  test('an older failed write cannot roll back a newer order', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final store = _ControlledInstanceStore(
      sites,
      steps: [
        _SaveStep(gate: gate, started: started, fails: true),
        const _SaveStep(),
      ],
    );
    final controller = _controller(store);
    addTearDown(controller.dispose);
    await controller.load();

    final firstMove = controller.moveInstance(sites.first, 2);
    await started.future;
    final secondMove = controller.moveInstance(sites[2], 0);
    gate.complete();

    expect(await firstMove, isTrue);
    expect(await secondMove, isTrue);
    expect(_urls(controller.instances), [
      sites[2].url,
      sites[1].url,
      sites[0].url,
    ]);
    expect(_urls(store.saved), _urls(controller.instances));
    expect(store.saveCount, 2);
  });

  test('a later failed write rolls back only to the durable move', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final store = _ControlledInstanceStore(
      sites,
      steps: [
        _SaveStep(gate: gate, started: started),
        const _SaveStep(fails: true),
        const _SaveStep(),
      ],
    );
    final controller = _controller(store);
    addTearDown(controller.dispose);
    await controller.load();

    final firstMove = controller.moveInstance(sites.first, 2);
    await started.future;
    final secondMove = controller.moveInstance(sites[2], 0);
    gate.complete();

    expect(await firstMove, isTrue);
    expect(await secondMove, isFalse);
    expect(_urls(controller.instances), [
      sites[1].url,
      sites[2].url,
      sites[0].url,
    ]);
    expect(_urls(store.saved), _urls(controller.instances));
    expect(store.saveCount, 3);
  });

  test('a move during rollback repair is not treated as durable', () async {
    final repairGate = Completer<void>();
    final repairStarted = Completer<void>();
    final store = _ControlledInstanceStore(
      sites,
      steps: [
        const _SaveStep(fails: true),
        _SaveStep(gate: repairGate, started: repairStarted),
        const _SaveStep(fails: true),
        const _SaveStep(),
      ],
    );
    final controller = _controller(store);
    addTearDown(controller.dispose);
    await controller.load();

    final firstMove = controller.moveInstance(sites.first, 2);
    await repairStarted.future;
    expect(await firstMove, isFalse);

    final secondMove = controller.moveInstance(sites.last, 0);
    expect(_urls(controller.instances), [
      sites[2].url,
      sites[0].url,
      sites[1].url,
    ]);
    repairGate.complete();

    expect(await secondMove, isFalse);
    expect(_urls(controller.instances), _urls(sites));
    expect(_urls(store.saved), _urls(sites));
    expect(store.saveCount, 4);
  });
}

ShellController _controller(InstanceStore store) => ShellController(
  instanceStore: store,
  api: FakeDiscourseApi(),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
  updateStore: FakeUpdateStore(),
);

List<String> _urls(Iterable<DiscourseInstance> instances) => [
  for (final instance in instances) instance.url,
];

final class _ControlledInstanceStore implements InstanceStore {
  _ControlledInstanceStore(
    Iterable<DiscourseInstance> instances, {
    Iterable<_SaveStep> steps = const [],
  }) : saved = List.of(instances),
       _steps = Queue.of(steps);

  List<DiscourseInstance> saved;
  final Queue<_SaveStep> _steps;
  int saveCount = 0;

  @override
  Future<List<DiscourseInstance>> load() async => List.of(saved);

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    saveCount++;
    final snapshot = List.of(instances);
    final step = _steps.isEmpty ? const _SaveStep() : _steps.removeFirst();
    step.started?.complete();
    if (step.gate case final gate?) await gate.future;
    if (step.fails) throw StateError('preferences unavailable');
    saved = snapshot;
  }
}

final class _SaveStep {
  const _SaveStep({this.gate, this.started, this.fails = false});

  final Completer<void>? gate;
  final Completer<void>? started;
  final bool fails;
}
