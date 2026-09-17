import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_participants.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';
import 'support/participant_fixtures.dart';
import 'support/shell_test_harness.dart' show watchBrowser;

void main() {
  late EventTestPorts ports;
  setUp(() {
    ports = EventTestPorts();
    ports.transport.responses['GET /discourse-post-event/events/42.json'] = {
      'event': eventJson(),
    };
    ports.transport.responses['GET ${participantFixturePath()}'] = {
      'invitees': participantScreenshotRows,
    };
  });
  tearDown(() => ports.close());

  void reply({
    String filter = '',
    String? type,
    List<Object?> rows = const [],
  }) {
    ports
        .transport
        .responses['GET ${participantFixturePath(filter: filter, type: type)}'] = {
      'invitees': rows,
    };
  }

  Future<void> open(
    WidgetTester tester, {
    double width = 1000,
    double scale = 1,
    double keyboard = 0,
    TextDirection direction = TextDirection.ltr,
    TargetPlatform platform = TargetPlatform.macOS,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final handle = ports.controller.acquire(
      eventSite,
      PostEvent.decode(eventJson())!,
    );
    addTearDown(handle.dispose);
    await handle.refresh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: Directionality(
            textDirection: direction,
            child: DFocusHighlight(child: child!),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: DButton(
                label: const Text('Open participants'),
                onPressed: () => showEventParticipants(context, handle),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open participants'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('loading skeleton gives way to results and filtered empty state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final initial = Completer<Map<String, dynamic>>();
      ports.transport.responders['GET ${participantFixturePath()}'] = (_) =>
          initial.future;
      await open(tester, settle: false);
      expect(find.bySemanticsLabel('Loading participants'), findsOneWidget);
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(find.byType(DProgress), findsNothing);
      expect(find.text('6 shown'), findsNothing);
      final dialogBounds = tester.getRect(find.byType(DDialogContent));

      initial.complete({'invitees': participantScreenshotRows});
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.bySemanticsLabel('Loading participants'), findsNothing);
      expect(find.text('@Emily_Roman'), findsOneWidget);
      expect(tester.getRect(find.byType(DDialogContent)), dialogBounds);

      final filtered = Completer<Map<String, dynamic>>();
      ports
              .transport
              .responders['GET ${participantFixturePath(type: 'interested')}'] =
          (_) => filtered.future;
      await tester.tap(find.widgetWithText(DTabTrigger<String>, 'Interested'));
      await tester.pump();
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(find.text('@Emily_Roman'), findsNothing);
      filtered.complete({'invitees': <Object?>[]});
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.text('No participants found'), findsOneWidget);
      expect(tester.getRect(find.byType(DDialogContent)), dialogBounds);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('compact roster shows real identities and opens profile links', (
    tester,
  ) async {
    final browser = watchBrowser(tester);
    await open(tester);
    expect(find.text('Participants'), findsOneWidget);
    expect(find.text('6 shown'), findsOneWidget);
    for (final row in participantScreenshotRows) {
      final user = row['user']! as Map<String, Object?>;
      expect(find.text(user['name']! as String), findsOneWidget);
      expect(find.text('@${user['username']}'), findsOneWidget);
    }
    expect(find.text('FS'), findsOneWidget);
    await tester.tap(find.text('pengguna1'));
    await tester.pumpAndSettle();
    expect(browser, ['$eventSite/u/Alfima']);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Participants'), findsNothing);
    expect(ports.transport.writes, isEmpty);
  });

  testWidgets(
    'typing debounces server search and combines it with response filters',
    (tester) async {
      reply(filter: 'Emily', rows: [participantScreenshotRows[4]]);
      reply(filter: 'Emily', type: 'interested');
      reply(type: 'interested');
      await open(tester);
      final before = ports.transport.reads.length;
      await tester.enterText(find.byType(EditableText), '@Emily');
      await tester.pump(const Duration(milliseconds: 100));
      expect(ports.transport.reads, hasLength(before));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('@Emily_Roman'), findsOneWidget);
      expect(find.text('1 shown'), findsOneWidget);
      expect(find.text('@Alfima'), findsNothing);
      await tester.tap(find.widgetWithText(DTabTrigger<String>, 'Interested'));
      await tester.pumpAndSettle();
      expect(find.text('No participants found'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Try a different response filter.'), findsOneWidget);
      await tester.tap(find.text('Show all participants'));
      await tester.pumpAndSettle();
      expect(find.text('6 shown'), findsOneWidget);
    },
  );

  testWidgets('outdated results cannot appear during a newer query debounce', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    ports.transport.responders['GET ${participantFixturePath(filter: 'old')}'] =
        (_) => old.future;
    reply(filter: 'Emily', rows: [participantScreenshotRows[4]]);
    await open(tester);
    await tester.enterText(find.byType(EditableText), 'old');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(EditableText), 'Emily');
    old.complete({'invitees': participantScreenshotRows});
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('@Alfima'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('@Emily_Roman'), findsOneWidget);
    expect(find.text('1 shown'), findsOneWidget);
  });

  testWidgets(
    'failed requests offer retry without losing the selected response',
    (tester) async {
      final path = 'GET ${participantFixturePath(type: 'going')}';
      ports.transport.failures[path] = StateError('Offline');
      reply(type: 'going', rows: participantScreenshotRows);
      await open(tester);
      await tester.tap(find.widgetWithText(DTabTrigger<String>, 'Going'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load participants'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('6 shown'), findsOneWidget);
      expect(
        ports.transport.reads.last.path,
        participantFixturePath(type: 'going'),
      );
    },
  );

  testWidgets('lost access cancels debounced search and removes the roster', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(EditableText), 'Emily');
    final before = ports.transport.reads.length;
    ports.requests.forget(eventSite);
    ports.controller.forget(eventSite);
    await tester.pumpAndSettle();
    expect(
      find.text('Participant details are no longer available.'),
      findsOneWidget,
    );
    expect(find.text('@Alfima'), findsNothing);
    expect(ports.transport.reads, hasLength(before));
    expect(tester.widget<DInput>(find.byType(DInput)).enabled, isFalse);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('recurring and invited responses retain their meaning', (
    tester,
  ) async {
    reply(
      rows: [
        {...participantScreenshotRows[0], 'recurring': true},
        {...participantScreenshotRows[1], 'status': null},
      ],
    );
    await open(tester);
    expect(find.byTooltip('Every occurrence'), findsOneWidget);
    expect(find.text('Invited'), findsOneWidget);
    expect(find.text('2 shown'), findsOneWidget);
  });

  testWidgets(
    'a capped roster scrolls and identifies the server result limit',
    (tester) async {
      reply(
        rows: [
          for (var i = 0; i < 200; i++)
            {
              'status': 'going',
              'user': {'username': 'person$i'},
            },
        ],
      );
      await open(tester);
      expect(find.text('200 shown'), findsOneWidget);
      expect(
        find.text('Showing up to 200 people. Search to narrow the list.'),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(find.text('@person199'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'narrow large text and keyboard remain usable in ${direction.name}',
      (tester) async {
        final pending = Completer<Map<String, dynamic>>();
        ports.transport.responders['GET ${participantFixturePath()}'] = (_) =>
            pending.future;
        await open(
          tester,
          width: 320,
          scale: 2,
          keyboard: 280,
          direction: direction,
          platform: TargetPlatform.iOS,
          settle: false,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(DSkeletonRegion), findsOneWidget);
        pending.complete({'invitees': participantScreenshotRows});
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Participants'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'keyboard response navigation and Escape use the Native controls',
    (tester) async {
      reply(type: 'going', rows: participantScreenshotRows);
      await open(tester);
      await tester.tap(find.widgetWithText(DTabTrigger<String>, 'All'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        ports.transport.reads.last.path,
        participantFixturePath(type: 'going'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Participants'), findsNothing);
    },
  );
}
