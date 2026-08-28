import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_diagnostics_plugin.dart';
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
        initialRootMode: ShellRootMode.forum,
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
        initialRootMode: ShellRootMode.forum,
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
      initialRootMode: ShellRootMode.forum,
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
      initialRootMode: ShellRootMode.forum,
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

  testWidgets('leaves injected installed plugins caller-owned', (tester) async {
    final key = GlobalKey();
    final bridgeReleased = Completer<void>();
    final first = await ResenhaDiagnosticsController.create(
      persistence: MemoryResenhaDiagnosticsPersistence(),
      sdkLogBridges: [
        CallbackResenhaDiagnosticsSdkLogBridge(
          install: (_) {},
          uninstall: () {
            if (!bridgeReleased.isCompleted) bridgeReleased.complete();
          },
        ),
      ],
    );
    final second = await ResenhaDiagnosticsController.create(
      persistence: MemoryResenhaDiagnosticsPersistence(),
    );
    await first.startCapture();
    final firstPlugins = PluginInstaller.install(
      PluginManifest([_DiagnosticsTestModule(first)]),
    );
    final secondPlugins = PluginInstaller.install(
      PluginManifest([_DiagnosticsTestModule(second)]),
    );
    addTearDown(firstPlugins.close);
    addTearDown(secondPlugins.close);

    final store = FakeInstanceStore();
    final api = FakeDiscourseApi();
    final authenticator = FakeAuthenticator();
    final drafts = FakeDraftStore();
    final forumTabs = FakeForumTabStore();
    final trackers = FakeSiteTracker.reset();
    final updater = FakeUpdater();
    final updateStore = FakeUpdateStore();

    Widget app(InstalledPlugins plugins) => DiscourseApp(
      key: key,
      store: store,
      api: api,
      authenticator: authenticator,
      drafts: drafts,
      forumTabs: forumTabs,
      trackers: trackers,
      updater: updater,
      updateStore: updateStore,
      initialRootMode: ShellRootMode.forum,
      plugins: plugins,
    );

    await tester.pumpWidget(app(firstPlugins));
    await tester.pump();
    expect(first.captureEnabled, isTrue);

    await tester.pumpWidget(app(secondPlugins));
    await tester.pump();

    expect(bridgeReleased.isCompleted, isFalse);
    expect(first.captureEnabled, isTrue);
    expect(second.captureEnabled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await firstPlugins.close();
    await secondPlugins.close();
    expect(bridgeReleased.isCompleted, isTrue);
  });

  testWidgets(
    'dispatches app state and background flush to every registered lifecycle',
    (tester) async {
      final persistence = _TrackingDiagnosticsPersistence();
      final diagnostics = await DiagnosticsController.create(
        persistence: persistence,
        sessionId: 'app-lifecycle-dispatch',
      );
      addTearDown(diagnostics.close);
      final first = _LifecycleProbe();
      final second = _LifecycleProbe();
      final manifest = PluginManifest([
        _LifecycleTestModule('lifecycle-one', first),
        _LifecycleTestModule('lifecycle-two', second),
      ]);

      await tester.pumpWidget(
        DiscourseApp(
          store: FakeInstanceStore(),
          api: FakeDiscourseApi(),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
          diagnostics: diagnostics,
          pluginManifest: manifest,
          initialRootMode: ShellRootMode.forum,
        ),
      );
      await tester.pumpAndSettle();
      final appendCallsBeforeBackground = persistence.appendCalls;
      diagnostics.recordLog(name: 'before.background', source: 'test');
      expect(persistence.appendCalls, appendCallsBeforeBackground);

      final observer =
          tester.state(find.byType(DiscourseApp)) as WidgetsBindingObserver;
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();

      for (final probe in [first, second]) {
        expect(probe.states.last, ('paused', false));
        expect(probe.flushCalls, 1);
      }
      expect(persistence.appendCalls, appendCallsBeforeBackground + 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await diagnostics.close();
    },
  );

  testWidgets('releases replaced diagnostics without replacing the shell', (
    tester,
  ) async {
    final firstPersistence = _TrackingDiagnosticsPersistence();
    final secondPersistence = _TrackingDiagnosticsPersistence();
    final firstDiagnostics = await DiagnosticsController.create(
      persistence: firstPersistence,
      sessionId: 'first-app-diagnostics',
    );
    final secondDiagnostics = await DiagnosticsController.create(
      persistence: secondPersistence,
      sessionId: 'second-app-diagnostics',
    );
    addTearDown(firstDiagnostics.close);
    addTearDown(secondDiagnostics.close);

    final key = GlobalKey();
    final api = FakeDiscourseApi();
    final store = FakeInstanceStore();
    final authenticator = FakeAuthenticator();
    final drafts = FakeDraftStore();
    final forumTabs = FakeForumTabStore();
    final trackers = FakeSiteTracker.reset();
    final updater = FakeUpdater();
    final updateStore = FakeUpdateStore();
    final reporterProbe = _ReporterProbe();
    final manifest = PluginManifest([_ReporterTestModule(reporterProbe)]);

    Widget app(DiagnosticsController diagnostics) => DiscourseApp(
      key: key,
      store: store,
      api: api,
      authenticator: authenticator,
      drafts: drafts,
      forumTabs: forumTabs,
      trackers: trackers,
      updater: updater,
      updateStore: updateStore,
      diagnostics: diagnostics,
      pluginManifest: manifest,
      initialRootMode: ShellRootMode.forum,
    );

    await tester.pumpWidget(app(firstDiagnostics));
    await tester.pumpAndSettle();
    final shell = _controller(tester);
    reporterProbe.record('before-replacement');
    expect(
      firstDiagnostics.events.whereType<DiagnosticLogEvent>().map(
        (event) => event.name,
      ),
      contains('before-replacement'),
    );

    await tester.pumpWidget(app(secondDiagnostics));
    await tester.pumpAndSettle();
    await firstPersistence.closed.future;
    reporterProbe.record('after-replacement');

    expect(_controller(tester), same(shell));
    expect(api.closeCalls, 0);
    expect(firstPersistence.closeCalls, 1);
    expect(secondPersistence.closeCalls, 0);
    expect(
      secondDiagnostics.events.whereType<DiagnosticLogEvent>().map(
        (event) => event.name,
      ),
      contains('after-replacement'),
    );
    expect(
      firstDiagnostics.events.whereType<DiagnosticLogEvent>().map(
        (event) => event.name,
      ),
      isNot(contains('after-replacement')),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await secondPersistence.closed.future;

    expect(api.closeCalls, 1);
    expect(firstPersistence.closeCalls, 1);
    expect(secondPersistence.closeCalls, 1);
  });

  testWidgets('observes a released diagnostics close failure', (tester) async {
    final closeError = StateError('diagnostics persistence close failed');
    final firstPersistence = _TrackingDiagnosticsPersistence(
      closeError: closeError,
    );
    final secondPersistence = _TrackingDiagnosticsPersistence();
    final firstDiagnostics = await DiagnosticsController.create(
      persistence: firstPersistence,
      sessionId: 'failing-app-diagnostics',
    );
    final secondDiagnostics = await DiagnosticsController.create(
      persistence: secondPersistence,
      sessionId: 'replacement-app-diagnostics',
    );
    addTearDown(firstDiagnostics.close);
    addTearDown(secondDiagnostics.close);
    final diagnosticsSink = _RecordingDiagnosticsSink();
    final sinkBinding = DiagnosticsSink.install(diagnosticsSink);
    addTearDown(sinkBinding.close);

    final key = GlobalKey();
    final api = FakeDiscourseApi();
    final store = FakeInstanceStore();
    final authenticator = FakeAuthenticator();
    final drafts = FakeDraftStore();
    final forumTabs = FakeForumTabStore();
    final trackers = FakeSiteTracker.reset();
    final updater = FakeUpdater();
    final updateStore = FakeUpdateStore();

    Widget app(DiagnosticsController diagnostics) => DiscourseApp(
      key: key,
      store: store,
      api: api,
      authenticator: authenticator,
      drafts: drafts,
      forumTabs: forumTabs,
      trackers: trackers,
      updater: updater,
      updateStore: updateStore,
      diagnostics: diagnostics,
      initialRootMode: ShellRootMode.forum,
    );

    await tester.pumpWidget(app(firstDiagnostics));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(secondDiagnostics));
    await firstPersistence.closed.future;
    await diagnosticsSink.reported.future;

    expect(diagnosticsSink.error, same(closeError));
    expect(diagnosticsSink.operation, 'app.diagnostics.close');
    expect(diagnosticsSink.source, 'diagnostics');
    expect(diagnosticsSink.severity, DiagnosticSeverity.warning);
    expect(diagnosticsSink.handled, isTrue);
    expect(diagnosticsSink.degraded, isFalse);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await secondPersistence.closed.future;
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

  test('connected tracker startup survives a site switch', () async {
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

    expect(FakeSiteTracker.built.map((tracker) => tracker.siteUrl), [
      secondUrl,
      firstUrl,
    ], reason: 'connected forum badges need both polls while visible');
    expect(FakeSiteTracker.built.every((tracker) => tracker.polling), isTrue);
  });

  test('the app lifecycle controls every connected forum poll', () async {
    const firstUrl = 'https://first.example';
    const secondUrl = 'https://second.example';
    const user = DiscourseUser(id: 7, username: 'reader');
    final authenticator = FakeAuthenticator()
      ..keys[firstUrl] = 'first-key'
      ..keys[secondUrl] = 'second-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('first.example').copyWith(user: user),
        instance('second.example').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(user: user),
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);

    await shell.load();
    await pumpEventQueue();
    expect(FakeSiteTracker.built, hasLength(2));
    expect(FakeSiteTracker.built.every((tracker) => tracker.polling), isTrue);

    shell.setForeground(false);
    expect(FakeSiteTracker.built.every((tracker) => !tracker.polling), isTrue);

    shell.setForeground(true);
    expect(FakeSiteTracker.built.every((tracker) => tracker.polling), isTrue);
    expect(
      FakeSiteTracker.built.map((tracker) => tracker.pollNowCalls),
      everyElement(1),
    );
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

final class _DiagnosticsTestModule implements PluginModule {
  const _DiagnosticsTestModule(this.controller);

  final ResenhaDiagnosticsController controller;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('resenha'));

  @override
  void register(PluginRegistrar registrar) {
    final plugin = ResenhaDiagnosticsPlugin(controller: controller);
    registrar.addCapability(plugin);
    registrar.addAppLifecycle(
      plugin,
      requires: const [pluginDiagnosticsReporterPort],
    );
  }
}

final class _LifecycleTestModule implements PluginModule {
  const _LifecycleTestModule(this.id, this.lifecycle);

  final String id;
  final PluginAppLifecycle lifecycle;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(id: PluginId(id));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addAppLifecycle(lifecycle);
  }
}

final class _LifecycleProbe extends PluginAppLifecycle {
  final List<(String, bool)> states = [];
  int flushCalls = 0;

  @override
  void observeAppState(String state, {required bool foreground}) {
    states.add((state, foreground));
  }

  @override
  void flush() {
    flushCalls++;
  }
}

final class _ReporterTestModule implements PluginModule {
  const _ReporterTestModule(this.lifecycle);

  final _ReporterProbe lifecycle;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('diagnostics-probe'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addAppLifecycle(
      lifecycle,
      requires: const [pluginDiagnosticsReporterPort],
    );
  }
}

final class _ReporterProbe extends PluginAppLifecycle {
  PluginDiagnosticsReporter? _reporter;

  @override
  void startPhase(PluginStartupPhase phase, PluginHostBindings bindings) {
    _reporter ??= bindings.require(pluginDiagnosticsReporterPort);
  }

  void record(String name) {
    _reporter!.recordLog(name: name, source: 'diagnostics-probe');
  }
}

final class _TrackingDiagnosticsPersistence implements DiagnosticsPersistence {
  _TrackingDiagnosticsPersistence({this.closeError});

  final MemoryDiagnosticsPersistence _delegate = MemoryDiagnosticsPersistence();
  final Completer<void> closed = Completer<void>();
  final Object? closeError;
  int appendCalls = 0;
  int closeCalls = 0;

  @override
  Future<DiagnosticsPersistenceState> load({required DateTime nowUtc}) =>
      _delegate.load(nowUtc: nowUtc);

  @override
  Future<void> appendEvents(
    List<DiagnosticEvent> events, {
    required DateTime nowUtc,
  }) {
    appendCalls++;
    return _delegate.appendEvents(events, nowUtc: nowUtc);
  }

  @override
  Future<void> writeLastSeenSequence(int sequence) =>
      _delegate.writeLastSeenSequence(sequence);

  @override
  Future<void> compact({required DateTime nowUtc}) =>
      _delegate.compact(nowUtc: nowUtc);

  @override
  Future<void> clear() => _delegate.clear();

  @override
  Future<void> close() async {
    closeCalls++;
    await _delegate.close();
    if (!closed.isCompleted) closed.complete();
    if (closeError case final error?) throw error;
  }
}

final class _RecordingDiagnosticsSink implements DiagnosticsSink {
  final Completer<void> reported = Completer<void>();
  Object? error;
  String? operation;
  String? source;
  DiagnosticSeverity? severity;
  bool? handled;
  bool? degraded;

  @override
  void recordLog({
    required String name,
    String source = 'application',
    String? component,
    String? message,
    Map<String, Object?> attributes = const {},
    DiagnosticSeverity severity = DiagnosticSeverity.info,
    String? operation,
    String? correlationId,
    bool handled = true,
    bool degraded = false,
  }) {}

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    String? operation,
    String source = 'application',
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    bool handled = true,
    bool degraded = true,
    String? correlationId,
  }) {
    this.error = error;
    this.operation = operation;
    this.source = source;
    this.severity = severity;
    this.handled = handled;
    this.degraded = degraded;
    if (!reported.isCompleted) reported.complete();
  }
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
