import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/site_basic_info.dart';
import 'package:discourse_native/src/models/site_config.dart';
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

  test('a failed reorder cannot restore a removed forum', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final store = _ControlledInstanceStore(
      sites,
      steps: [_SaveStep(gate: gate, started: started, fails: true)],
    );
    final controller = _controller(store);
    addTearDown(controller.dispose);
    await controller.load();

    final moving = controller.moveInstance(sites.first, 2);
    await started.future;
    expect(await controller.removeInstance(sites[1]), isTrue);
    gate.complete();

    expect(await moving, isFalse);
    expect(_urls(controller.instances), [sites[2].url, sites[0].url]);
    expect(_urls(store.saved), [sites[2].url, sites[0].url]);
    expect(controller.currentInstance?.url, sites[0].url);
  });

  test('order rollback preserves a replacement and its selection', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final basicInfoGate = Completer<void>();
    final store = _ControlledInstanceStore(
      sites,
      steps: [_SaveStep(gate: gate, started: started, fails: true)],
    );
    final controller = _controller(
      store,
      api: FakeDiscourseApi(
        basicInfoGate: basicInfoGate,
        basicInfos: {sites[1].url: const SiteBasicInfo(title: 'Renamed')},
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final moving = controller.moveInstance(sites.first, 2);
    await started.future;
    controller.selectInstance(0);
    basicInfoGate.complete();
    await pumpEventQueue();
    final replacement = controller.currentInstance;
    expect(replacement?.title, 'Renamed');
    expect(replacement, isNot(same(sites[1])));
    gate.complete();

    expect(await moving, isFalse);
    expect(_urls(controller.instances), _urls(sites));
    expect(controller.currentInstance, same(replacement));
    expect(controller.instanceIndex, 1);
    expect(store.saved[1], same(replacement));
  });

  test(
    'a re-add survives a failed removal through coalescing storage',
    () async {
      final persistence = _FailingRemovalPersistence(sites, sites[1].url);
      final store = InstanceStore(persistence: persistence);
      final controller = _controller(store);
      addTearDown(controller.dispose);
      addTearDown(() {
        if (!persistence.release.isCompleted) persistence.release.complete();
      });
      await controller.load();

      final removing = controller.removeInstance(controller.instances[1]);
      await persistence.started.future;
      final readded = instance('two.example', title: 'Re-added');
      final adding = controller.addInstance(readded);
      await pumpEventQueue();
      expect(controller.currentInstance, same(readded));
      persistence.release.complete();

      expect(await removing, isFalse);
      expect(await adding, isTrue);
      expect(_urls(controller.instances), [
        sites[0].url,
        sites[2].url,
        sites[1].url,
      ]);
      expect(controller.currentInstance, same(readded));
      final persisted = await store.load();
      expect(_urls(persisted), _urls(controller.instances));
      expect(persisted.last.title, 'Re-added');
    },
  );

  test('a superseded add reports its current-snapshot repair result', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final configGate = Completer<void>();
    final added = instance('new.example');
    final store = _ControlledInstanceStore(
      sites,
      steps: [_SaveStep(gate: gate, started: started, fails: true)],
    );
    final controller = _controller(
      store,
      api: FakeDiscourseApi(
        siteConfigGate: configGate,
        siteConfigs: {added.url: const SiteConfig(emojiEnabled: false)},
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final adding = controller.addInstance(added);
    await started.future;
    configGate.complete();
    await controller.resolveSiteConfig(added.url);
    final replacement = controller.currentInstance;
    expect(replacement, isNot(same(added)));
    expect(replacement?.config.emojiEnabled, isFalse);
    gate.complete();

    expect(await adding, isTrue);
    expect(controller.currentInstance, same(replacement));
    expect(store.saved.last, same(replacement));
  });

  for (final fails in [true, false]) {
    test(
      'disposal settles a pending reorder before its ${fails ? 'failed' : 'successful'} write',
      () async {
        final gate = Completer<void>();
        final started = Completer<void>();
        final store = _ControlledInstanceStore(
          sites,
          steps: [_SaveStep(gate: gate, started: started, fails: fails)],
        );
        final controller = _controller(store);
        var disposed = false;
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
          if (!disposed) controller.dispose();
        });
        await controller.load();

        final moving = controller.moveInstance(sites.first, 2);
        await started.future;
        controller.dispose();
        disposed = true;

        expect(await moving.timeout(const Duration(seconds: 1)), isFalse);
        gate.complete();
        await pumpEventQueue();
        expect(_urls(controller.instances), [
          sites[1].url,
          sites[2].url,
          sites[0].url,
        ]);
        expect(
          store.saveCount,
          1,
          reason: 'retirement must not start a repair',
        );
      },
    );
  }
}

ShellController _controller(InstanceStore store, {FakeDiscourseApi? api}) =>
    ShellController(
      instanceStore: store,
      api: api ?? FakeDiscourseApi(),
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

final class _FailingRemovalPersistence implements InstancePersistence {
  _FailingRemovalPersistence(List<DiscourseInstance> sites, this.removingUrl)
    : value = jsonEncode([for (final site in sites) site.toJson()]);

  String value;
  final String removingUrl;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async {
    final sites = (jsonDecode(next) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    if (!started.isCompleted &&
        !sites.any((site) => site['url'] == removingUrl)) {
      started.complete();
      await release.future;
      throw StateError('removal unavailable');
    }
    value = next;
  }
}
