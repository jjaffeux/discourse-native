import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/diagnostics_panel.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('diagnostics entry survives loading, failure, and no sites', (
    tester,
  ) async {
    final load = Completer<List<DiscourseInstance>>();
    final diagnostics = await _controller();
    await _pumpApp(
      tester,
      const Size(390, 844),
      diagnostics,
      store: _PendingStore(load.future),
      settle: false,
    );

    expect(
      find.byKey(const ValueKey('diagnostics-rail-button')),
      findsOneWidget,
    );

    load.completeError(StateError('preferences unavailable'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load your sites"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('diagnostics-rail-button')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await diagnostics.close();

    final emptyDiagnostics = await _controller();
    await _pumpApp(
      tester,
      const Size(390, 844),
      emptyDiagnostics,
      store: FakeInstanceStore(),
    );

    expect(find.text('No sites yet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('diagnostics-rail-button')),
      findsOneWidget,
    );
  });

  testWidgets('docks at 440px and becomes a responsive right overlay', (
    tester,
  ) async {
    final diagnostics = await _controller();
    await _pumpApp(tester, const Size(1440, 900), diagnostics);

    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('diagnostics-modal-barrier')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('diagnostics-panel'))).width,
      diagnosticsPanelWidth,
    );

    await tester.enterText(
      find.byKey(const ValueKey('diagnostics-search')),
      'keep this filter',
    );
    expect(diagnostics.panelState.query, 'keep this filter');

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('diagnostics-modal-barrier')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('diagnostics-panel'))).width,
      diagnosticsPanelWidth,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('diagnostics-search')))
          .controller!
          .text,
      'keep this filter',
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('diagnostics-panel'))).width,
      390,
    );
  });

  testWidgets(
    'phone and medium overlays cover and block the window title bar',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final diagnostics = await _controller();
        final authenticator = FakeAuthenticator();
        await _pumpApp(
          tester,
          const Size(390, 844),
          diagnostics,
          store: FakeInstanceStore([
            instance('meta.discourse.org', title: 'Meta'),
          ]),
          authenticator: authenticator,
        );

        for (final size in const [Size(390, 844), Size(1000, 800)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('diagnostics-rail-button')),
          );
          await tester.pumpAndSettle();

          final panel = tester.getRect(
            find.byKey(const ValueKey('diagnostics-panel')),
          );
          final barrier = tester.getRect(
            find.byKey(const ValueKey('diagnostics-modal-barrier')),
          );
          final titleBar = tester.getRect(find.byType(ShellTitleBar));
          final expectedPanelWidth = size.width < 600
              ? size.width
              : diagnosticsPanelWidth;

          expect(
            panel,
            Rect.fromLTWH(
              size.width - expectedPanelWidth,
              0,
              expectedPanelWidth,
              size.height,
            ),
            reason: 'diagnostics panel at $size',
          );
          expect(
            barrier,
            Rect.fromLTWH(0, 0, size.width, size.height),
            reason: 'modal barrier at $size',
          );
          expect(panel.top, lessThanOrEqualTo(titleBar.top));
          expect(panel.bottom, greaterThanOrEqualTo(titleBar.bottom));

          // The avatar remains mounted behind the modal layer. Hitting the
          // coordinates it owns must be consumed by diagnostics rather than
          // starting the underlying sign-in flow.
          final avatar = find.byKey(UserMenuButton.avatarKey);
          expect(avatar, findsOneWidget);
          await tester.tapAt(tester.getCenter(avatar));
          await tester.pumpAndSettle();
          expect(
            authenticator.connected,
            isEmpty,
            reason: 'title bar at $size',
          );

          if (diagnostics.isPanelOpen) {
            diagnostics.closePanel();
            await tester.pumpAndSettle();
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets('badge clears when the panel opens', (tester) async {
    final diagnostics = await _controller();
    diagnostics.reportError(
      TimeoutException('topic load took too long'),
      StackTrace.fromString('loadTopic (shell_controller.dart:1203)'),
      operation: 'load topic',
      source: 'topic',
    );
    await _pumpApp(tester, const Size(1000, 800), diagnostics);

    final button = find.byKey(const ValueKey('diagnostics-rail-button'));
    expect(
      find.descendant(of: button, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(diagnostics.unseenErrorCountListenable.value, 0);
    expect(find.descendant(of: button, matching: find.text('1')), findsNothing);
  });

  testWidgets('the diagnostics entry caps its badge and names unseen errors', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final diagnostics = await _controller();
    for (var index = 0; index < 105; index += 1) {
      diagnostics.reportError(
        StateError('background failure $index'),
        StackTrace.current,
      );
    }
    await _pumpApp(tester, const Size(390, 844), diagnostics);

    final button = find.byKey(const ValueKey('diagnostics-rail-button'));
    expect(
      find.descendant(of: button, matching: find.text('99+')),
      findsOneWidget,
    );
    final node = tester.getSemantics(button);
    expect(node.label, 'Diagnostics, 105 unseen errors');
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  testWidgets('filters, freezes, inspects, and clears diagnostics', (
    tester,
  ) async {
    Finder menuItem(String label) =>
        find.widgetWithText(CheckedPopupMenuItem<String>, label);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final diagnostics = await _controller();
    _recordRequest(diagnostics);
    diagnostics.reportError(
      TimeoutException('topic load took too long'),
      StackTrace.fromString('loadTopic (shell_controller.dart:1203)'),
      operation: 'load topic',
      source: 'topic',
    );
    await _pumpApp(tester, const Size(1000, 800), diagnostics);
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();

    final request = find.text('https://example.test/t/42?token');
    expect(request, findsOneWidget);
    expect(find.textContaining('topic load took too long'), findsOneWidget);
    expect(find.textContaining('Bodies, credentials, cookies'), findsOneWidget);
    final timeline = tester.widget<ListView>(
      find.byKey(const ValueKey('diagnostics-timeline')),
    );
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.controller, same(timeline.controller));

    await tester.tap(find.text('Requests'));
    await tester.pump();
    expect(request, findsOneWidget);
    expect(find.textContaining('topic load took too long'), findsNothing);

    await tester.tap(find.text('Errors'));
    await tester.pump();
    expect(request, findsNothing);
    expect(find.textContaining('topic load took too long'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.tap(find.byKey(const ValueKey('diagnostics-severity-filter')));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Error'));
    await tester.pumpAndSettle();
    expect(request, findsNothing);
    expect(find.textContaining('topic load took too long'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diagnostics-severity-filter')));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Error'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diagnostics-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Topic'));
    await tester.pumpAndSettle();
    expect(request, findsNothing);
    expect(find.textContaining('topic load took too long'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diagnostics-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Topic'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('diagnostics-search')),
      '/t/42',
    );
    await tester.pump();
    expect(request, findsOneWidget);
    expect(find.textContaining('topic load took too long'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('diagnostics-search')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('diagnostics-freeze')));
    await tester.pump();
    expect(diagnostics.panelState.frozen, isTrue);

    diagnostics.reportError(
      StateError('arrived while frozen'),
      StackTrace.fromString('frozen stack'),
      operation: 'background refresh',
      source: 'refresh',
    );
    await tester.pump();
    expect(find.textContaining('arrived while frozen'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('diagnostics-freeze')));
    await tester.pump();
    expect(find.textContaining('arrived while frozen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('diagnostics-copy-report')));
    await tester.pump();
    expect(copied, hasLength(1));
    expect(copied.single, contains('"version": 1'));
    expect(copied.single, contains('https://example.test/t/42?token'));
    expect(copied.single, isNot(contains('secret')));

    await tester.tap(request);
    await tester.pump();
    expect(find.text('Event details'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diagnostics-copy-event')));
    await tester.pump();
    expect(copied, hasLength(2));
    expect(copied.last, contains('"id": "request-42"'));
    expect(copied.last, isNot(contains('secret')));
    final detail = find.byKey(const ValueKey('diagnostic-detail-request-42'));
    await tester.drag(detail, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Response Headers'), findsOneWidget);
    await tester.drag(detail, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('120000'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Event details'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('diagnostics-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Refresh'));
    await tester.pumpAndSettle();
    expect(diagnostics.panelState.sources, {'refresh'});

    await tester.tap(find.byKey(const ValueKey('diagnostics-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Clear diagnostics history?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
    await tester.pumpAndSettle();

    expect(diagnostics.events, isEmpty);
    expect(find.text('No diagnostics yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diagnostics-source-filter')));
    await tester.pumpAndSettle();
    expect(menuItem('Refresh'), findsOneWidget);
    await tester.tap(menuItem('Refresh'));
    await tester.pumpAndSettle();
    expect(diagnostics.panelState.sources, isEmpty);
  });

  testWidgets('Escape returns from details, then closes the panel', (
    tester,
  ) async {
    final diagnostics = await _controller();
    _recordRequest(diagnostics);
    await _pumpApp(tester, const Size(1000, 800), diagnostics);
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://example.test/t/42?token'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(diagnostics.isPanelOpen, isTrue);
    expect(find.text('Event details'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(diagnostics.isPanelOpen, isFalse);
    expect(find.byKey(const ValueKey('diagnostics-panel')), findsNothing);
  });

  testWidgets('system Back closes diagnostics at every shell width', (
    tester,
  ) async {
    final diagnostics = await _controller();
    await _pumpApp(tester, const Size(390, 844), diagnostics);

    for (final size in const [
      Size(390, 844),
      Size(1000, 800),
      Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
      await tester.pumpAndSettle();
      expect(diagnostics.isPanelOpen, isTrue, reason: 'open at $size');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(diagnostics.isPanelOpen, isFalse, reason: 'closed at $size');
    }
  });

  testWidgets('HTTP events rebuild the panel but not the shell columns', (
    tester,
  ) async {
    final diagnostics = await _controller();
    await _pumpApp(
      tester,
      const Size(1000, 800),
      diagnostics,
      store: FakeInstanceStore([instance('meta.discourse.org', title: 'Meta')]),
    );
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();

    final rail = tester.element(find.byType(InstanceRail));
    final sidebar = tester.element(find.byType(InstanceSidebar));
    final content = tester.element(find.byType(MainContent));
    final panelListener = tester.element(
      find.byKey(const ValueKey('diagnostics-events-listener')),
    );
    final rebuilt = <Element>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element);
      previous?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    _recordRequest(diagnostics);
    await tester.pump();

    expect(rebuilt, contains(panelListener));
    expect(rebuilt, isNot(contains(rail)));
    expect(rebuilt, isNot(contains(sidebar)));
    expect(rebuilt, isNot(contains(content)));
  });
}

Future<DiagnosticsController> _controller() => DiagnosticsController.create(
  persistence: MemoryDiagnosticsPersistence(),
  sessionId: 'diagnostics-panel-test',
  clock: () => DateTime.utc(2026, 8, 8, 10, 12, 37),
);

void _recordRequest(DiagnosticsController diagnostics) {
  final timestamp = DateTime.utc(2026, 8, 8, 10, 12, 37);
  final uri = Uri.parse('https://example.test/t/42?token=secret');
  diagnostics.recordHttp(
    HttpDiagnosticRecord(
      eventId: 'request-42',
      phase: HttpDiagnosticPhase.started,
      timestamp: timestamp,
      method: 'GET',
      uri: uri,
      sentBytes: 0,
      receivedBytes: 0,
      operationId: 'load topic',
    ),
  );
  diagnostics.recordHttp(
    HttpDiagnosticRecord(
      eventId: 'request-42',
      phase: HttpDiagnosticPhase.completed,
      timestamp: timestamp.add(const Duration(milliseconds: 120)),
      method: 'GET',
      uri: uri,
      sentBytes: 0,
      receivedBytes: 2048,
      operationId: 'load topic',
      statusCode: 200,
      reasonPhrase: 'OK',
      responseHeaders: const {'content-type': 'application/json'},
      headerDuration: const Duration(milliseconds: 40),
      totalDuration: const Duration(milliseconds: 120),
    ),
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  Size size,
  DiagnosticsController diagnostics, {
  InstanceStore? store,
  FakeAuthenticator? authenticator,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(diagnostics.close);

  await tester.pumpWidget(
    DiscourseApp(
      store: store ?? FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: authenticator ?? FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      diagnostics: diagnostics,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _PendingStore implements InstanceStore {
  _PendingStore(this.result);

  final Future<List<DiscourseInstance>> result;

  @override
  Future<List<DiscourseInstance>> load() => result;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {}
}
