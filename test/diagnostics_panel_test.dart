import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/diagnostics_panel_width_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/diagnostics_panel.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('docks at its preferred width and becomes a responsive overlay', (
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

  testWidgets('resizes from the left edge and restores the width on reload', (
    tester,
  ) async {
    final firstDiagnostics = await _controller();
    await _pumpApp(tester, const Size(1440, 900), firstDiagnostics);
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();

    final panel = tester.getRect(
      find.byKey(const ValueKey('diagnostics-panel')),
    );
    await tester.dragFrom(
      Offset(panel.left + 1, panel.top + 28),
      // Flutter reserves the first 20 logical pixels for drag recognition.
      const Offset(-140, 0),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('diagnostics-panel'))).width,
      560,
    );
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        DiagnosticsPanelWidthStore.storageKey,
      ),
      560,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await firstDiagnostics.close();

    final reloadedDiagnostics = await _controller();
    await _pumpApp(tester, const Size(1440, 900), reloadedDiagnostics);
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('diagnostics-panel'))).width,
      560,
    );
  });

  testWidgets('detail back button is not covered by the resize handle', (
    tester,
  ) async {
    final diagnostics = await _controller();
    _recordRequest(diagnostics);
    await _pumpApp(tester, const Size(1000, 800), diagnostics);
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://example.test/t/42?token'));
    await tester.pump();

    expect(find.text('Event details'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diagnostics-detail-back')));
    await tester.pump();

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Event details'), findsNothing);
  });

  testWidgets('resize handle is keyboard and semantics adjustable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final diagnostics = await _controller();
    await _pumpApp(tester, const Size(1440, 900), diagnostics);
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey('diagnostics-resize-handle'));
    expect(tester.getSize(handle).width, diagnosticsPanelResizeHandleWidth);
    final node = tester.getSemantics(handle);
    final data = node.getSemanticsData();
    expect(data.label, 'Resize diagnostics panel');
    expect(data.value, '440 pixels wide');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('diagnostics-resize-focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    expect(focus.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('diagnostics-panel'))).width,
      456,
    );
    expect(
      (await SharedPreferences.getInstance()).getDouble(
        DiagnosticsPanelWidthStore.storageKey,
      ),
      456,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('diagnostics-panel'))).width,
      440,
    );
    semantics.dispose();
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

          // The account action remains mounted behind the modal layer. Hitting
          // its coordinates must be consumed by diagnostics rather than
          // starting the underlying sign-in flow.
          final signIn = find.byKey(UserMenuButton.signInKey);
          expect(signIn, findsOneWidget);
          await tester.tapAt(tester.getCenter(signIn));
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
    final badge = find.byKey(const ValueKey('diagnostics-rail-badge'));
    final badgeContainer = find.descendant(
      of: badge,
      matching: find.byType(Container),
    );
    final decoration = tester.widget<Container>(badgeContainer).decoration;
    expect(
      (decoration! as BoxDecoration).color,
      Theme.of(tester.element(badge)).colorScheme.error,
    );
    final node = tester.getSemantics(button);
    expect(node.label, 'Diagnostics, 105 unseen errors');
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  group('timeline interactions', () {
    testWidgets('category, severity, source, and text filters compose', (
      tester,
    ) async {
      await _pumpPopulatedDiagnosticsPanel(tester);

      final request = find.text('https://example.test/t/42?token');
      final error = find.textContaining('topic load took too long');
      expect(request, findsOneWidget);
      expect(error, findsOneWidget);
      final timeline = tester.widget<ListView>(
        find.byKey(const ValueKey('diagnostics-timeline')),
      );
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.controller, same(timeline.controller));

      await tester.tap(find.text('Requests'));
      await tester.pump();
      expect(request, findsOneWidget);
      expect(error, findsNothing);

      await tester.tap(find.text('Errors'));
      await tester.pump();
      expect(request, findsNothing);
      expect(error, findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.tap(
        find.byKey(const ValueKey('diagnostics-severity-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_diagnosticsMenuItem('Error'));
      await tester.pumpAndSettle();
      expect(request, findsNothing);
      expect(error, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('diagnostics-severity-filter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(_diagnosticsMenuItem('Error'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('diagnostics-source-filter')));
      await tester.pumpAndSettle();
      await tester.tap(_diagnosticsMenuItem('Topic'));
      await tester.pumpAndSettle();
      expect(request, findsNothing);
      expect(error, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('diagnostics-source-filter')));
      await tester.pumpAndSettle();
      await tester.tap(_diagnosticsMenuItem('Topic'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diagnostics-search')),
        '/t/42',
      );
      await tester.pump();
      expect(request, findsOneWidget);
      expect(error, findsNothing);
    });

    testWidgets('freezing holds new events until the timeline resumes', (
      tester,
    ) async {
      final diagnostics = await _pumpPopulatedDiagnosticsPanel(tester);

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
      expect(diagnostics.panelState.frozen, isFalse);
      expect(find.textContaining('arrived while frozen'), findsOneWidget);
    });

    testWidgets('copied reports and event details redact request secrets', (
      tester,
    ) async {
      final copied = _recordClipboardWrites(tester);
      await _pumpPopulatedDiagnosticsPanel(tester);
      final request = find.text('https://example.test/t/42?token');

      expect(find.textContaining('Bodies, credentials, cookies'), findsNothing);
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
    });

    testWidgets('clear keeps an unavailable source filter resettable', (
      tester,
    ) async {
      final diagnostics = await _pumpPopulatedDiagnosticsPanel(tester);
      diagnostics.reportError(
        StateError('background refresh failed'),
        StackTrace.fromString('refresh stack'),
        operation: 'background refresh',
        source: 'refresh',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('diagnostics-source-filter')));
      await tester.pumpAndSettle();
      await tester.tap(_diagnosticsMenuItem('Refresh'));
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
      expect(_diagnosticsMenuItem('Refresh'), findsOneWidget);
      await tester.tap(_diagnosticsMenuItem('Refresh'));
      await tester.pumpAndSettle();
      expect(diagnostics.panelState.sources, isEmpty);
    });
  });

  testWidgets('starts, stops, and copies a topic scroll capture', (
    tester,
  ) async {
    final copied = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final diagnostics = await _controller();
    await _pumpApp(tester, const Size(1000, 800), diagnostics);
    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Topic scroll'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('topic-scroll-capture-panel')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('topic-scroll-capture-start')));
    await tester.pumpAndSettle();

    expect(diagnostics.topicScrollCapture.isRecording, isTrue);
    expect(diagnostics.isPanelOpen, isFalse);
    diagnostics.topicScrollCapture.recordTopicEvent(
      'scroll.notification',
      const {'pixels': 120.0},
    );

    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();
    expect(find.text('Recording'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('topic-scroll-capture-stop')));
    await tester.pump();
    expect(find.text('Capture ready'), findsOneWidget);

    await tester.runAsync(() async {
      final clipboardWrite = Completer<void>();
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
          if (!clipboardWrite.isCompleted) clipboardWrite.complete();
        }
        return null;
      });
      await tester.tap(find.byKey(const ValueKey('topic-scroll-capture-copy')));
      await clipboardWrite.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            fail('copying the capture never reached the platform clipboard'),
      );
    });
    await tester.pump();

    expect(copied, hasLength(1));
    expect(copied.single, contains('"kind": "topic-scroll-capture"'));
    expect(copied.single, contains('scroll.notification'));
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

  testWidgets('an old clear dialog cannot clear replacement diagnostics', (
    tester,
  ) async {
    final oldDiagnostics = await _controller();
    final replacement = await _controller();
    _recordRequest(oldDiagnostics);
    _recordRequest(replacement);
    final current = ValueNotifier<DiagnosticsController>(oldDiagnostics);

    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ValueListenableBuilder<DiagnosticsController>(
            valueListenable: current,
            builder: (context, controller, _) =>
                DiagnosticsPanel(controller: controller, onClose: () {}),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('diagnostics-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Clear diagnostics history?'), findsOneWidget);

      current.value = replacement;
      await tester.pump();
      expect(find.text('Clear diagnostics history?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await tester.pumpAndSettle();

      expect(replacement.events.whereType<HttpDiagnosticEvent>(), isNotEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
      await oldDiagnostics.close();
      await replacement.close();
    }
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

  testWidgets('Settings temporarily replaces a docked diagnostics panel', (
    tester,
  ) async {
    final diagnostics = await _controller();
    await _pumpApp(tester, const Size(1440, 900), diagnostics);

    await tester.tap(find.byKey(const ValueKey('diagnostics-rail-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('diagnostics-docked-slot')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
    await tester.pumpAndSettle();

    expect(find.byType(AppSettingsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostics-docked-slot')), findsNothing);
    expect(diagnostics.isPanelOpen, isTrue);

    await tester.tap(find.byKey(const ValueKey('app-settings-back')));
    await tester.pumpAndSettle();

    expect(find.byType(AppSettingsPage), findsNothing);
    expect(
      find.byKey(const ValueKey('diagnostics-docked-slot')),
      findsOneWidget,
    );
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

Finder _diagnosticsMenuItem(String label) =>
    find.widgetWithText(CheckedPopupMenuItem<String>, label);

List<String> _recordClipboardWrites(WidgetTester tester) {
  final copied = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

Future<DiagnosticsController> _pumpPopulatedDiagnosticsPanel(
  WidgetTester tester,
) async {
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
  return diagnostics;
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
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      diagnostics: diagnostics,
      initialRootMode: ShellRootMode.forum,
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
