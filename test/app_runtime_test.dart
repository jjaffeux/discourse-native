import 'dart:async';

import 'package:discourse_native/src/app_runtime.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test(
    'constructs and replaces services without a scheduler binding',
    () async {
      expect(() => SchedulerBinding.instance, throwsA(isA<Error>()));
      const manifest = PluginManifest([]);
      final runtime = _runtime(
        const AppRuntimeDependencies(pluginManifest: manifest),
      );
      final first = runtime.controller;
      try {
        expect(
          runtime.replace(
            const AppRuntimeDependencies(
              pluginManifest: manifest,
              forumTabsEnabled: true,
            ),
          ),
          isFalse,
        );
        expect(runtime.controller, same(first));
        expect(first.rootMode, ShellRootMode.forum);

        expect(
          runtime.replace(
            AppRuntimeDependencies(
              pluginManifest: manifest,
              authenticator: FakeAuthenticator(),
              forumTabsEnabled: true,
            ),
          ),
          isTrue,
        );
        final next = runtime.controller;
        expect(next.forumTabsEnabled, isTrue);
        expect(next.instanceStore, same(first.instanceStore));
        expect(next.api.lifecycle, same(first.api.lifecycle));
        expect(next.appSettings.store, same(first.appSettings.store));
        expect(next.forumSettings.store, same(first.forumSettings.store));
        expect(next.drafts, same(first.drafts));
        expect(next.forumTabs, same(first.forumTabs));
        expect(next.recentDestinations, same(first.recentDestinations));
        expect(next.destinationBookmarks, same(first.destinationBookmarks));
        expect(next.plugins, same(first.plugins));
        expect(() => SchedulerBinding.instance, throwsA(isA<Error>()));
      } finally {
        runtime.dispose();
        await _turn();
      }
    },
  );

  test('plugin replacement rebuilds only model-dependent defaults', () async {
    final firstProbe = _LifecycleProbe();
    final nextProbe = _LifecycleProbe();
    final firstManifest = PluginManifest([_Module(firstProbe)]);
    final nextManifest = PluginManifest([_Module(nextProbe)]);
    final runtime = _runtime(
      AppRuntimeDependencies(pluginManifest: firstManifest),
    );
    final first = runtime.controller;
    try {
      await runtime.start(first);
      expect(
        runtime.replace(AppRuntimeDependencies(pluginManifest: nextManifest)),
        isTrue,
      );
      final next = runtime.controller;
      expect(next.instanceStore, isNot(same(first.instanceStore)));
      expect(next.api.lifecycle, isNot(same(first.api.lifecycle)));
      expect(next.api.models, same(next.plugins.models));
      expect(next.appSettings.store, same(first.appSettings.store));
      expect(next.recentDestinations, same(first.recentDestinations));
      expect(next.destinationBookmarks, same(first.destinationBookmarks));
      await runtime.start(next);
      await _turn();
      expect(firstProbe.closes, 1);
      expect(nextProbe.closes, 0);
    } finally {
      runtime.dispose();
      await _turn();
    }
    expect(nextProbe.closes, 1);
  });

  test('borrowed plugins and injected services survive replacement', () async {
    final firstProbe = _LifecycleProbe();
    final nextProbe = _LifecycleProbe();
    final firstPlugins = PluginInstaller.install(
      PluginManifest([_Module(firstProbe)]),
    );
    final nextPlugins = PluginInstaller.install(
      PluginManifest([_Module(nextProbe)]),
    );
    final fixture = _Fixture();
    final runtime = _runtime(fixture.dependencies(plugins: firstPlugins));
    try {
      await runtime.start(runtime.controller);
      final first = runtime.controller;
      expect(
        runtime.replace(fixture.dependencies(plugins: nextPlugins)),
        isTrue,
      );
      await runtime.start(runtime.controller);
      expect(runtime.controller.instanceStore, same(first.instanceStore));
      expect(runtime.controller.api.lifecycle, same(first.api.lifecycle));
      expect(fixture.api.closeCalls, 0);
      expect(firstProbe.closes, 0);
      expect(nextProbe.phases, [
        PluginStartupPhase.bootstrap,
        PluginStartupPhase.appReady,
      ]);
      runtime.dispose();
      runtime.dispose();
      await _turn();
      expect(fixture.api.closeCalls, 1);
      expect(firstProbe.closes, 0);
      expect(nextProbe.closes, 0);
    } finally {
      runtime.dispose();
      await firstPlugins.close();
      await nextPlugins.close();
    }
  });

  test(
    'retained plugins start phases once across shell replacements',
    () async {
      final probe = _LifecycleProbe();
      final manifest = PluginManifest([_Module(probe)]);
      final fixture = _Fixture();
      final runtime = _runtime(fixture.dependencies(manifest: manifest));
      try {
        await runtime.start(runtime.controller);
        runtime.replace(
          fixture.dependencies(store: FakeInstanceStore(), manifest: manifest),
        );
        await runtime.start(runtime.controller);
        expect(probe.phases, [
          PluginStartupPhase.bootstrap,
          PluginStartupPhase.appReady,
        ]);
        expect(probe.closes, 0);
        expect(fixture.api.closeCalls, 0);
      } finally {
        runtime.dispose();
        await _turn();
      }
    },
  );

  test('bootstrap failure still loads the shell', () async {
    final probe = _LifecycleProbe(failBootstrap: true);
    final fixture = _Fixture();
    final runtime = _runtime(
      fixture.dependencies(manifest: PluginManifest([_Module(probe)])),
    );
    try {
      await runtime.start(runtime.controller);
      expect(runtime.controller.loadStatus, InstanceLoadStatus.ready);
      expect(probe.phases, [PluginStartupPhase.bootstrap]);
    } finally {
      runtime.dispose();
      await _turn();
    }
    expect(fixture.api.closeCalls, 1);
  });

  test('pending bootstrap observes the latest foreground state', () async {
    final gate = Completer<void>();
    final probe = _LifecycleProbe(bootstrap: gate.future);
    final fixture = _Fixture();
    final runtime = _runtime(
      fixture.dependencies(manifest: PluginManifest([_Module(probe)])),
    );
    final starting = runtime.start(runtime.controller);
    try {
      await probe.bootstrapStarted.future;
      runtime.observeAppState('paused', foreground: false);
      gate.complete();
      await starting;
      expect(runtime.controller.loadStatus, InstanceLoadStatus.ready);
      expect(probe.states, isNotEmpty);
      expect(probe.states.every((state) => state == ('paused', false)), isTrue);
      expect(probe.flushes, 1);
      expect(probe.phases.last, PluginStartupPhase.appReady);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await starting;
      runtime.dispose();
      await _turn();
    }
  });

  test(
    'a stale load cannot take notification delivery from its successor',
    () async {
      final oldStore = _GatedStore();
      final connected = instance(
        'one.example',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));
      final opened = <int>[];
      var session = 0;
      final module = _Module(
        _LifecycleProbe(),
        session: () {
          final identity = ++session;
          return PluginSessionContribution(
            lifecycle: _SessionProbe(),
            capabilities: [
              _LinkHandler((_) async {
                opened.add(identity);
                return true;
              }),
            ],
          );
        },
      );
      final manifest = PluginManifest([module]);
      final fixture = _Fixture();
      final auth = FakeAuthenticator.signedIn([connected], site: fixture.api);
      final runtime = _runtime(
        fixture.dependencies(
          store: oldStore,
          authenticator: auth,
          manifest: manifest,
        ),
      );
      final urls = StreamController<String>(sync: true);
      runtime.listenNotificationOpens(urls.stream);
      final oldController = runtime.controller;
      final starting = runtime.start(oldController);
      try {
        await oldStore.started.future;
        urls.add('https://one.example/t/queued/42');
        runtime.replace(
          fixture.dependencies(
            store: FakeInstanceStore([connected]),
            authenticator: auth,
            manifest: manifest,
          ),
        );
        await runtime.start(runtime.controller);
        await _turn();
        expect(opened, [2]);
        oldStore.result.complete([connected]);
        await starting;
        urls.add('https://one.example/t/after-old-load/43');
        await _turn();
        expect(opened, [2, 2]);
      } finally {
        if (!oldStore.result.isCompleted) oldStore.result.complete([]);
        await starting;
        runtime.dispose();
        await urls.close();
        await _turn();
      }
    },
  );

  test(
    'retirement waits for session then plugin before closing transport',
    () async {
      final events = <String>[];
      final sessionGate = Completer<void>();
      final pluginGate = Completer<void>();
      final probe = _LifecycleProbe(
        closeGate: pluginGate.future,
        events: events,
      );
      final session = _SessionProbe(gate: sessionGate.future, events: events);
      final fixture = _Fixture(api: _ClosingApi(events));
      final runtime = _runtime(
        fixture.dependencies(
          manifest: PluginManifest([
            _Module(
              probe,
              session: () => PluginSessionContribution(lifecycle: session),
            ),
          ]),
        ),
      );
      try {
        await runtime.start(runtime.controller);
        runtime.dispose();
        await _turn();
        expect(events, ['session']);
        expect(fixture.api.closeCalls, 0);
        sessionGate.complete();
        await _turn();
        expect(events, ['session', 'plugin']);
        expect(fixture.api.closeCalls, 0);
        pluginGate.complete();
        await _turn();
        expect(events, ['session', 'plugin', 'api']);
        expect(fixture.api.closeCalls, 1);
        await runtime.start(runtime.controller);
        expect(probe.phases, [
          PluginStartupPhase.bootstrap,
          PluginStartupPhase.appReady,
        ]);
      } finally {
        if (!sessionGate.isCompleted) sessionGate.complete();
        if (!pluginGate.isCompleted) pluginGate.complete();
        runtime.dispose();
        await _turn();
      }
    },
  );
}

AppRuntime _runtime(AppRuntimeDependencies dependencies) => AppRuntime(
  dependencies: dependencies,
  foreground: true,
  lifecycleState: 'resumed',
);

Future<void> _turn() => Future<void>.delayed(Duration.zero);

final class _Fixture {
  _Fixture({FakeDiscourseApi? api}) : api = api ?? FakeDiscourseApi();

  final FakeDiscourseApi api;
  final store = FakeInstanceStore();
  final authenticator = FakeAuthenticator();
  final drafts = FakeDraftStore();
  final tabs = FakeForumTabStore();
  final trackers = FakeSiteTracker.reset();
  final updater = FakeUpdater();
  final updateStore = FakeUpdateStore();

  AppRuntimeDependencies dependencies({
    InstanceStore? store,
    FakeAuthenticator? authenticator,
    InstalledPlugins? plugins,
    PluginManifest manifest = const PluginManifest([]),
  }) => AppRuntimeDependencies(
    store: store ?? this.store,
    api: api,
    authenticator: authenticator ?? this.authenticator,
    drafts: drafts,
    forumTabs: tabs,
    trackers: trackers,
    updater: updater,
    updateStore: updateStore,
    plugins: plugins,
    pluginManifest: manifest,
  );
}

final class _Module implements PluginModule {
  const _Module(this.lifecycle, {this.session});

  final PluginAppLifecycle lifecycle;
  final PluginSessionContribution Function()? session;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('runtime-probe'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addAppLifecycle(lifecycle);
    final build = session;
    if (build != null) registrar.addSession((_, _) => build());
  }
}

final class _LifecycleProbe extends PluginAppLifecycle {
  _LifecycleProbe({
    this.bootstrap,
    this.failBootstrap = false,
    this.closeGate,
    this.events,
  });

  final Future<void>? bootstrap;
  final bool failBootstrap;
  final Future<void>? closeGate;
  final List<String>? events;
  final bootstrapStarted = Completer<void>();
  final phases = <PluginStartupPhase>[];
  final states = <(String, bool)>[];
  int closes = 0;
  int flushes = 0;

  @override
  Future<void> startPhase(
    PluginStartupPhase phase,
    PluginHostBindings bindings,
  ) async {
    phases.add(phase);
    if (phase == PluginStartupPhase.bootstrap) {
      bootstrapStarted.complete();
      if (failBootstrap) throw StateError('bootstrap refused');
      await bootstrap;
    }
  }

  @override
  void observeAppState(String state, {required bool foreground}) {
    states.add((state, foreground));
  }

  @override
  void flush() => flushes++;

  @override
  Future<void> close() async {
    closes++;
    events?.add('plugin');
    await closeGate;
  }
}

final class _GatedStore extends FakeInstanceStore {
  final result = Completer<List<DiscourseInstance>>();
  final started = Completer<void>();

  @override
  Future<List<DiscourseInstance>> load() {
    started.complete();
    return result.future;
  }
}

final class _SessionProbe extends PluginSessionLifecycle {
  _SessionProbe({this.gate, this.events});

  final Future<void>? gate;
  final List<String>? events;

  @override
  Future<void> close() async {
    events?.add('session');
    await gate;
  }
}

final class _ClosingApi extends FakeDiscourseApi {
  _ClosingApi(this.events);

  final List<String> events;

  @override
  void close() {
    events.add('api');
    super.close();
  }
}

final class _LinkHandler implements PluginLinkHandler {
  const _LinkHandler(this.open);

  final Future<bool> Function(String) open;

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
    void Function()? onNavigated,
  }) => open(url);
}
